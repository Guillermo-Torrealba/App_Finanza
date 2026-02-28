import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SimuladorFinancieroScreen extends StatefulWidget {
  const SimuladorFinancieroScreen({super.key});

  @override
  State<SimuladorFinancieroScreen> createState() =>
      _SimuladorFinancieroScreenState();
}

class _SimuladorFinancieroScreenState extends State<SimuladorFinancieroScreen> {
  // --- Valores Iniciales ---
  double _ingresoMensual = 1500000;
  double _gastosFijos = 500000;
  double _gastosVariables = 300000; // El valor más importante para jugar
  double _tasaInversionAnual = 5.0; // En porcentaje (0 a 15%)

  // Años de proyección
  final int _anosProyeccion = 20;

  final List<FlSpot> _puntosGrafico = [];

  // Calculados
  double _patrimonioFinal = 0;
  double _ahorroMensualActual = 0;
  int? _anoLibertadFinanciera; // Año en el que el interés mensual > gastos

  @override
  void initState() {
    super.initState();
    _calcularProyeccion();
  }

  void _calcularProyeccion() {
    _puntosGrafico.clear();
    double capitalAcumulado = 0;

    _ahorroMensualActual = _ingresoMensual - _gastosFijos - _gastosVariables;
    _anoLibertadFinanciera = null;

    // Convertir tasa anual a mensual (ej: 5% anual / 12 = 0.416% mensual)
    double tasaMensual = (_tasaInversionAnual / 100) / 12;

    for (int mes = 1; mes <= _anosProyeccion * 12; mes++) {
      // 1. Interés generado sobre el capital del mes anterior
      double interesGenerado = capitalAcumulado > 0
          ? capitalAcumulado * tasaMensual
          : 0; // Si hay deuda, simplificamos asumiendo 0% de retorno o podríamos aplicar un costo de deuda.

      // 2. Nuevo capital: Capital anterior + Interés + Flujo mensual
      capitalAcumulado += interesGenerado + _ahorroMensualActual;

      // 3. Revisar Libertad Financiera
      // Si el interés generado por sí solo cubre los gastos fijos + variables
      if (_anoLibertadFinanciera == null &&
          interesGenerado >= (_gastosFijos + _gastosVariables) &&
          mes > 0) {
        _anoLibertadFinanciera = (mes / 12).ceil();
      }

      // Guardar el punto cada 12 meses (al final de cada año) para el gráfico
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorPrincipal = Colors.teal;
    final colorDeuda = Colors.redAccent;
    final formatterLong = NumberFormat.simpleCurrency(
      decimalDigits: 0,
      name: '',
    );

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
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.only(
                  right: 24,
                  left: 16,
                  top: 24,
                  bottom: 12,
                ),
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      horizontalInterval: _patrimonioFinal > 0
                          ? max(1000000, _patrimonioFinal / 5)
                          : 1000000,
                      getDrawingHorizontalLine: (value) {
                        return FlLine(
                          color: isDark ? Colors.white12 : Colors.black12,
                          strokeWidth: 1,
                        );
                      },
                      getDrawingVerticalLine: (value) {
                        return FlLine(
                          color: isDark ? Colors.white12 : Colors.black12,
                          strokeWidth: 1,
                        );
                      },
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
                                'Año ${value.toInt()}',
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
                          interval: _patrimonioFinal > 0
                              ? max(1000000, _patrimonioFinal / 4)
                              : 1000000,
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
                    minX: 1,
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
                                  .withValues(alpha: 0.2),
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
                                  text: '\$${formatterLong.format(spot.y)}',
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
                    title: 'Ahorro Mensual',
                    value: '\$${formatterLong.format(_ahorroMensualActual)}',
                    color: _ahorroMensualActual >= 0
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
                    title: 'Libertad Financiera',
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

            // --- CONTROLES (Sliders) ---
            Expanded(
              flex: 6,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildControlHeader(
                    'Gastos Variables (Ocio, Restaurantes, etc)',
                    _gastosVariables,
                    colorPrincipal,
                    isDark,
                    true,
                  ),
                  Slider(
                    value: _gastosVariables,
                    min: 0,
                    max: 2000000,
                    divisions: 40,
                    activeColor: colorPrincipal,
                    label: '\$${formatterLong.format(_gastosVariables)}',
                    onChanged: (val) {
                      setState(() {
                        _gastosVariables = val;
                        _calcularProyeccion();
                      });
                    },
                  ),

                  const SizedBox(height: 8),

                  _buildControlHeader(
                    'Gastos Fijos (Arriendo, Cuentas, etc)',
                    _gastosFijos,
                    Colors.grey,
                    isDark,
                    false,
                  ),
                  Slider(
                    value: _gastosFijos,
                    min: 0,
                    max: 3000000,
                    divisions: 60,
                    activeColor: Colors.grey,
                    label: '\$${formatterLong.format(_gastosFijos)}',
                    onChanged: (val) {
                      setState(() {
                        _gastosFijos = val;
                        _calcularProyeccion();
                      });
                    },
                  ),

                  const SizedBox(height: 8),

                  _buildControlHeader(
                    'Ingreso Mensual',
                    _ingresoMensual,
                    Colors.blue,
                    isDark,
                    false,
                  ),
                  Slider(
                    value: _ingresoMensual,
                    min: 0,
                    max: 5000000,
                    divisions: 50,
                    activeColor: Colors.blue,
                    label: '\$${formatterLong.format(_ingresoMensual)}',
                    onChanged: (val) {
                      setState(() {
                        _ingresoMensual = val;
                        _calcularProyeccion();
                      });
                    },
                  ),

                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Rendimiento Anual Inversiones',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade700,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_tasaInversionAnual.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildControlHeader(
    String title,
    double value,
    Color color,
    bool isDark,
    bool isHero,
  ) {
    final formatter = NumberFormat.simpleCurrency(decimalDigits: 0, name: '');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontWeight: isHero ? FontWeight.w900 : FontWeight.bold,
              fontSize: isHero ? 16 : 14,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '\$${formatter.format(value)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ],
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
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
