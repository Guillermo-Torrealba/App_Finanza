import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_settings.dart';

class RecurrentItem {
  final String id;
  String name;
  double amount;

  RecurrentItem(this.id, this.name, this.amount);
}

class VariableExpense {
  final String category;
  double amount;
  double maxAmount;

  VariableExpense(this.category, this.amount, this.maxAmount);
}

class SimuladorFinancieroScreen extends StatefulWidget {
  final SettingsController settingsController;

  const SimuladorFinancieroScreen({
    super.key,
    required this.settingsController,
  });

  @override
  State<SimuladorFinancieroScreen> createState() =>
      _SimuladorFinancieroScreenState();
}

class _SimuladorFinancieroScreenState extends State<SimuladorFinancieroScreen> {
  bool _cargando = true;

  // Datos reales
  double _saldoRealActual = 0;

  // Listas locales para la simulación
  final List<RecurrentItem> _ingresosRecurrentes = [];
  final List<RecurrentItem> _gastosFijos = [];
  final List<VariableExpense> _gastosVariables = [];

  // Tasa de inversión anual esperada
  double _tasaInversionAnual = 5.0;

  // Resultados calculados
  final int _anosProyeccion = 20;
  final List<FlSpot> _puntosGrafico = [];
  double _patrimonioFinal = 0;
  double _flujoMensualActual = 0;
  int? _anoLibertadFinanciera;

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  Future<void> _cargarDatosIniciales() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final settings = widget.settingsController.settings;

    try {
      // 1. Calcular Saldo Real Total (Liquidez Débito)
      final gastosResponse = await supabase
          .from('gastos')
          .select('monto, tipo, metodo_pago, cuenta')
          .eq('user_id', user.id);

      double saldoNeto = 0;
      for (final g in gastosResponse) {
        if ((g['metodo_pago'] ?? 'Debito') == 'Credito') continue;
        final cuenta = (g['cuenta'] ?? '').toString();
        // Solo considerar cuentas activas
        if (!settings.activeAccounts.contains(cuenta)) continue;

        final m = (g['monto'] as num? ?? 0).toDouble();
        if (g['tipo'] == 'Ingreso') {
          saldoNeto += m;
        } else {
          saldoNeto -= m;
        }
      }
      _saldoRealActual = saldoNeto;

      // 2. Cargar Gastos Programados para inicializar Recurrentes y Fijos
      final programadosResponse = await supabase
          .from('gastos_programados')
          .select('id, item, monto, tipo, activo')
          .eq('user_id', user.id)
          .eq('activo', true);

      for (final p in programadosResponse) {
        final tipo = p['tipo'].toString();
        final item = RecurrentItem(
          p['id'].toString(),
          p['item'].toString(),
          (p['monto'] as num).toDouble(),
        );

        if (tipo == 'Ingreso') {
          _ingresosRecurrentes.add(item);
        } else if (tipo == 'Gasto') {
          _gastosFijos.add(item);
        }
      }

      // 3. Inicializar Gastos Variables desde Presupuestos
      for (final cat in settings.activeCategories) {
        final presupuesto = settings.categoryBudgets[cat] ?? 0;
        if (presupuesto > 0) {
          _gastosVariables.add(
            VariableExpense(
              cat,
              presupuesto.toDouble(),
              max(presupuesto * 2.0, 1000000.0),
            ),
          );
        } else {
          _gastosVariables.add(
            VariableExpense(cat, 0, 500000.0), // Default sin presupuesto
          );
        }
      }
    } catch (e) {
      debugPrint('Error cargando iniciales para simulador: $e');
    }

    if (mounted) {
      setState(() {
        _cargando = false;
        _calcularProyeccion();
      });
    }
  }

  void _calcularProyeccion() {
    _puntosGrafico.clear();
    double capitalAcumulado = _saldoRealActual;

    double sumaIngresos = _ingresosRecurrentes.fold(
      0,
      (sum, item) => sum + item.amount,
    );
    double sumaGastosFijos = _gastosFijos.fold(
      0,
      (sum, item) => sum + item.amount,
    );
    double sumaGastosVar = _gastosVariables.fold(
      0,
      (sum, item) => sum + item.amount,
    );

    _flujoMensualActual = sumaIngresos - sumaGastosFijos - sumaGastosVar;
    _anoLibertadFinanciera = null;

    // Agregar el punto inicial (Mes 0)
    _puntosGrafico.add(FlSpot(0, capitalAcumulado));

    // Convertir tasa anual a mensual (ej: 5% anual = 0.416% mensual)
    double tasaMensual = (_tasaInversionAnual / 100) / 12;

    for (int mes = 1; mes <= _anosProyeccion * 12; mes++) {
      // 1. Interés generado sobre el capital del mes anterior
      // Solo aplicamos interes si el capital es positivo (ahorro o inversiones)
      double interesGenerado = capitalAcumulado > 0
          ? capitalAcumulado * tasaMensual
          : 0;

      // 2. Nuevo capital
      capitalAcumulado += interesGenerado + _flujoMensualActual;

      // 3. Revisar Libertad Financiera
      // Se alcanza cuando los puros intereses generados en un mes cubren ambos gastos
      if (_anoLibertadFinanciera == null &&
          interesGenerado >= (sumaGastosFijos + sumaGastosVar) &&
          mes > 0) {
        _anoLibertadFinanciera = (mes / 12).ceil();
      }

      // Guardar punto cada 12 meses (fin de año)
      if (mes % 12 == 0) {
        int ano = mes ~/ 12;
        _puntosGrafico.add(FlSpot(ano.toDouble(), capitalAcumulado));
      }
    }

    _patrimonioFinal = capitalAcumulado;
    setState(() {});
  }

  String _formatDinero(double value) {
    if (value.abs() >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value.abs() >= 1000) {
      return '\$${(value / 1000).toStringAsFixed(0)}k';
    }
    final formatCurrency = NumberFormat.simpleCurrency(
      decimalDigits: 0,
      name: '',
    );
    return '\$${formatCurrency.format(value)}';
  }

  String _formatDineroFull(double value) {
    final formatCurrency = NumberFormat.simpleCurrency(
      decimalDigits: 0,
      name: '',
    );
    return '\$${formatCurrency.format(value)}';
  }

  void _mostrarDialogoAgregar(String tipo, List<RecurrentItem> listaDestino) {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Simular nuevo $tipo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Nombre (ej. Sueldo Extra)',
                ),
              ),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'Monto mensual'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty && amountCtrl.text.isNotEmpty) {
                  setState(() {
                    listaDestino.add(
                      RecurrentItem(
                        DateTime.now().millisecondsSinceEpoch.toString(),
                        nameCtrl.text,
                        double.parse(amountCtrl.text),
                      ),
                    );
                    _calcularProyeccion();
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorPrincipal = Colors.teal;
    final colorDeuda = Colors.redAccent;

    if (_cargando) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Simulador Financiero'),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulador Financiero'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // --- GRÁFICO ---
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.only(
                  right: 24,
                  left: 16,
                  top: 24,
                  bottom: 8,
                ),
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      horizontalInterval: _patrimonioFinal.abs() > 0
                          ? max(1000000.0, _patrimonioFinal.abs() / 5)
                          : 1000000.0,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: isDark ? Colors.white12 : Colors.black12,
                        strokeWidth: 1,
                      ),
                      getDrawingVerticalLine: (_) => FlLine(
                        color: isDark ? Colors.white12 : Colors.black12,
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          interval: 5,
                          getTitlesWidget: (value, meta) {
                            if (value == 0) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'A ${value.toInt()}',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: _patrimonioFinal.abs() > 0
                              ? max(1000000.0, _patrimonioFinal.abs() / 4)
                              : 1000000.0,
                          reservedSize: 55,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              _formatDinero(value),
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black54,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.right,
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                    minX: 0,
                    maxX: _anosProyeccion.toDouble(),
                    minY: min(0, _puntosGrafico.lastOrNull?.y ?? 0),
                    maxY: max(1000000, _patrimonioFinal * 1.1),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _puntosGrafico,
                        isCurved: true,
                        curveSmoothness: 0.3,
                        color: _patrimonioFinal >= 0
                            ? colorPrincipal
                            : colorDeuda,
                        barWidth: 4,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color:
                              (_patrimonioFinal >= 0
                                      ? colorPrincipal
                                      : colorDeuda)
                                  .withAlpha(51),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) =>
                            isDark ? Colors.grey.shade800 : Colors.white,
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            return LineTooltipItem(
                              'Año ${spot.x.toInt()}\n',
                              TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                              children: [
                                TextSpan(
                                  text: _formatDineroFull(spot.y),
                                  style: TextStyle(
                                    color: spot.y >= 0
                                        ? Colors.teal
                                        : Colors.red,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // --- KPIs / RESUMEN ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildKPICard(
                    title: 'Flujo Mensual',
                    value: _formatDineroFull(_flujoMensualActual),
                    color: _flujoMensualActual >= 0
                        ? colorPrincipal
                        : colorDeuda,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildKPICard(
                    title: 'Patrimonio Año 20',
                    value: _formatDinero(_patrimonioFinal),
                    color: _patrimonioFinal >= 0 ? colorPrincipal : colorDeuda,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildKPICard(
                    title: 'Libertad Finance',
                    value: _anoLibertadFinanciera != null
                        ? 'Año $_anoLibertadFinanciera'
                        : 'No Alcanzada',
                    color: _anoLibertadFinanciera != null
                        ? colorPrincipal
                        : Colors.orange,
                    isDark: isDark,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),

            // --- PANELES ESTILO LISTA / PLANILLA ---
            Expanded(
              flex: 5,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  // Tasa Inversión
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.trending_up, color: Colors.green),
                                SizedBox(width: 8),
                                Text(
                                  'Tasa Inversión Anual',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${_tasaInversionAnual.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _tasaInversionAnual,
                          min: 0,
                          max: 15,
                          divisions: 30,
                          activeColor: Colors.green,
                          label: '${_tasaInversionAnual.toStringAsFixed(1)}%',
                          onChanged: (val) {
                            setState(() {
                              _tasaInversionAnual = val;
                              _calcularProyeccion();
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  // INGRESOS
                  _buildSectionCard(
                    title: 'Ingresos Recurrentes',
                    icon: Icons.arrow_upward,
                    color: Colors.green,
                    items: _ingresosRecurrentes,
                    isDark: isDark,
                    onAdd: () =>
                        _mostrarDialogoAgregar('Ingreso', _ingresosRecurrentes),
                    onDelete: (item) {
                      setState(() {
                        _ingresosRecurrentes.remove(item);
                        _calcularProyeccion();
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // GASTOS FIJOS
                  _buildSectionCard(
                    title: 'Gastos Fijos',
                    icon: Icons.arrow_downward,
                    color: Colors.redAccent,
                    items: _gastosFijos,
                    isDark: isDark,
                    onAdd: () =>
                        _mostrarDialogoAgregar('Gasto Fijo', _gastosFijos),
                    onDelete: (item) {
                      setState(() {
                        _gastosFijos.remove(item);
                        _calcularProyeccion();
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // GASTOS VARIABLES (SLIDERS)
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tune, color: Colors.blue),
                            const SizedBox(width: 8),
                            const Text(
                              'Presupuesto: Gastos Variables',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ..._gastosVariables.map((ve) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(ve.category),
                                  Text(
                                    _formatDineroFull(ve.amount),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: ve.amount,
                                min: 0,
                                max: ve.maxAmount,
                                activeColor: Colors.blue,
                                onChanged: (val) {
                                  setState(() {
                                    ve.amount = val;
                                    _calcularProyeccion();
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<RecurrentItem> items,
    required bool isDark,
    required VoidCallback onAdd,
    required Function(RecurrentItem) onDelete,
  }) {
    double total = items.fold(0, (sum, i) => sum + i.amount);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              Text(
                _formatDineroFull(total),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No hay items aquí. Agrega uno para empezar.',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ...items.map((item) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(item.name)),
                Text(_formatDineroFull(item.amount)),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                  onPressed: () => onDelete(item),
                ),
              ],
            );
          }),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text('Agregar $title'),
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard({
    required String title,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
