import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_settings.dart';

class FlujoCajaScreen extends StatefulWidget {
  final SettingsController settingsController;

  const FlujoCajaScreen({super.key, required this.settingsController});

  @override
  State<FlujoCajaScreen> createState() => _FlujoCajaScreenState();
}

class _FlujoCajaScreenState extends State<FlujoCajaScreen> {
  bool _cargando = true;
  int _anoSeleccionado = DateTime.now().year;

  // Estructura de datos: Mes (1 al 12) -> Categoría -> Monto Total
  final Map<int, Map<String, double>> _ingresosVariables = {};
  final Map<int, Map<String, double>> _gastosVariables = {};

  final List<Map<String, dynamic>> _ingresosFijos = [];
  final List<Map<String, dynamic>> _gastosFijos = [];

  double _saldoInicialAno = 0.0;
  final Map<int, double> _flujoMensual = {};
  final Map<int, double> _cajaAcumulada = {};

  final ScrollController _verticalScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();

  static const double _columnWidth = 100.0;
  static const double _firstColumnWidth = 140.0;
  static const double _rowHeight = 45.0;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final settings = widget.settingsController.settings;

    // Reiniciar mapas
    for (int i = 1; i <= 12; i++) {
      _ingresosVariables[i] = {};
      _gastosVariables[i] = {};
      _flujoMensual[i] = 0;
      _cajaAcumulada[i] = 0;

      for (final cat in settings.activeIncomeCategories) {
        _ingresosVariables[i]![cat] = 0.0;
      }
      for (final cat in settings.activeCategories) {
        _gastosVariables[i]![cat] = 0.0;
      }
    }
    _ingresosFijos.clear();
    _gastosFijos.clear();

    try {
      // 1. Cargar Gastos Programados (Fijos)
      final programadosResp = await supabase
          .from('gastos_programados')
          .select('id, item, monto, tipo, frecuencia')
          .eq('user_id', user.id)
          .eq('activo', true);

      for (final p in programadosResp) {
        if (p['tipo'] == 'Ingreso') {
          _ingresosFijos.add(p);
        } else {
          _gastosFijos.add(p);
        }
      }

      // 2. Cargar Transacciones Reales (Variables) para el año actual
      final gastosAnualesResp = await supabase
          .from('gastos')
          .select('monto, tipo, categoria, fecha, metodo_pago, cuenta')
          .eq('user_id', user.id)
          .gte('fecha', '$_anoSeleccionado-01-01')
          .lte('fecha', '$_anoSeleccionado-12-31');

      for (final tx in gastosAnualesResp) {
        if ((tx['metodo_pago'] ?? 'Debito') == 'Credito') continue;
        final cuenta = (tx['cuenta'] ?? '').toString();
        if (!settings.activeAccounts.contains(cuenta)) continue;

        try {
          final fecha = DateTime.parse(tx['fecha']);
          final mes = fecha.month;
          final cat = tx['categoria']?.toString() ?? 'Varios';
          final monto = (tx['monto'] as num? ?? 0).toDouble();

          if (tx['tipo'] == 'Ingreso') {
            if (_ingresosVariables[mes]!.containsKey(cat)) {
              _ingresosVariables[mes]![cat] =
                  _ingresosVariables[mes]![cat]! + monto;
            } else {
              _ingresosVariables[mes]![cat] = monto;
            }
          } else {
            // Gasto
            if (_gastosVariables[mes]!.containsKey(cat)) {
              _gastosVariables[mes]![cat] =
                  _gastosVariables[mes]![cat]! + monto;
            } else {
              _gastosVariables[mes]![cat] = monto;
            }
          }
        } catch (_) {}
      }

      // 3. Calcular Saldo Inicial del Año (Caja al 1 de Enero)
      // Todo lo anterior al 1 de Enero del año seleccionado
      final historicoResp = await supabase
          .from('gastos')
          .select('monto, tipo, metodo_pago, cuenta')
          .eq('user_id', user.id)
          .lt('fecha', '$_anoSeleccionado-01-01');

      _saldoInicialAno = 0;
      for (final tx in historicoResp) {
        if ((tx['metodo_pago'] ?? 'Debito') == 'Credito') continue;
        final cuenta = (tx['cuenta'] ?? '').toString();
        if (!settings.activeAccounts.contains(cuenta)) continue;

        final monto = (tx['monto'] as num? ?? 0).toDouble();
        if (tx['tipo'] == 'Ingreso') {
          _saldoInicialAno += monto;
        } else {
          _saldoInicialAno -= monto;
        }
      }

      _calcularFlujoYCaja();
    } catch (e) {
      debugPrint('Error cargando datos de flujo de caja: $e');
    } finally {
      if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  void _calcularFlujoYCaja() {
    double cajaAnterior = _saldoInicialAno;

    for (int mes = 1; mes <= 12; mes++) {
      double totalIngresos = 0;
      double totalGastos = 0;

      // Sumar Ingresos Fijos
      for (final fijo in _ingresosFijos) {
        // Asume mensual para simplificar. Si es anual, habría que evaluar el mes de inicio.
        totalIngresos += (fijo['monto'] as num).toDouble();
      }

      // Sumar Ingresos Variables
      for (final amount in _ingresosVariables[mes]!.values) {
        totalIngresos += amount;
      }

      // Sumar Gastos Fijos
      for (final fijo in _gastosFijos) {
        totalGastos += (fijo['monto'] as num).toDouble();
      }

      // Sumar Gastos Variables
      for (final amount in _gastosVariables[mes]!.values) {
        totalGastos += amount;
      }

      _flujoMensual[mes] = totalIngresos - totalGastos;
      cajaAnterior = cajaAnterior + _flujoMensual[mes]!;
      _cajaAcumulada[mes] = cajaAnterior;
    }
  }

  String _formatDinero(double value) {
    if (value == 0) return '-';
    final formatCurrency = NumberFormat.simpleCurrency(
      decimalDigits: 0,
      name: '',
    );
    return formatCurrency.format(value);
  }

  List<String> get _mesesContext {
    return [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsController.settings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Preparar listas de categorías a renderizar (evitar renders vacíos si se desea, pero listemos todas por ahora)
    final incomesCats = settings.activeIncomeCategories;
    final expensesCats = settings.activeCategories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flujo de Caja'),
        centerTitle: true,
        actions: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _anoSeleccionado--;
                  });
                  _cargarDatos();
                },
              ),
              Text(
                '$_anoSeleccionado',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _anoSeleccionado++;
                  });
                  _cargarDatos();
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  // KPI Header extra? O directo a la tabla.
                  Expanded(
                    child: _buildCrossScrollView(
                      isDark,
                      incomesCats,
                      expensesCats,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // --- REFACTOR PARA SCROLL EN DOS DIRECCIONES ---
  // A column that stays fixed vertically?
  // Custom approach:
  Widget _buildCrossScrollView(
    bool isDark,
    List<String> incomesCats,
    List<String> expensesCats,
  ) {
    // This method will construct the grid.
    // Total rows: Header, Ingresos Section, Fixed Incomes, Var Incomes, Total Incomes
    // Gastos Section... etc

    List<Widget> firstColumnCells = [];
    List<List<Widget>> dataCells =
        []; // List of rows, each row is a list of cells (month 1 to 12)

    // Helper to add a full row
    void addRow(
      String concept,
      List<double> monthValues, {
      bool isSection = false,
      bool isSubtotal = false,
      Color? textColor,
    }) {
      firstColumnCells.add(
        _buildCell(
          concept,
          isHeader: isSection,
          isDark: isDark,
          bold: isSection || isSubtotal,
          alignLeft: true,
          textColor: textColor,
          isFirstCol: true,
        ),
      );

      List<Widget> rowData = [];
      for (int m = 1; m <= 12; m++) {
        final val = monthValues.isEmpty ? 0.0 : monthValues[m - 1];
        rowData.add(
          _buildCell(
            isSection ? '' : _formatDinero(val),
            isHeader: isSection,
            isDark: isDark,
            bold: isSubtotal,
            textColor: val < 0 ? Colors.red : textColor,
          ),
        );
      }
      dataCells.add(rowData);
    }

    // 1. Header Row
    List<Widget> headerMonths = [];
    for (int i = 0; i < 12; i++) {
      headerMonths.add(
        _buildCell(
          _mesesContext[i],
          isHeader: true,
          isDark: isDark,
          bold: true,
          isStickyTop: true,
        ),
      );
    }

    // 2. INGRESOS
    addRow('INGRESOS', [], isSection: true, textColor: Colors.green);
    // Fijos
    for (final fijo in _ingresosFijos) {
      List<double> vals = [];
      for (int m = 1; m <= 12; m++) {
        vals.add((fijo['monto'] as num).toDouble());
      }
      addRow('  ${fijo['item']}', vals);
    }
    // Variables
    for (final cat in incomesCats) {
      List<double> vals = [];
      for (int m = 1; m <= 12; m++) {
        vals.add(_ingresosVariables[m]![cat]!);
      }
      if (vals.any((v) => v > 0)) {
        // Mostrar solo si hay data en algun mes para ahorrar espacio
        addRow('  $cat', vals);
      }
    }
    // Total Ingresos
    List<double> tIng = [];
    for (int m = 1; m <= 12; m++) {
      double s = 0;
      for (final f in _ingresosFijos) {
        s += f['monto'];
      }
      for (final cat in incomesCats) {
        s += _ingresosVariables[m]![cat]!;
      }
      tIng.add(s);
    }
    addRow('Total Ingresos', tIng, isSubtotal: true, textColor: Colors.green);

    // 3. GASTOS
    addRow('GASTOS', [], isSection: true, textColor: Colors.redAccent);
    // Fijos
    for (final fijo in _gastosFijos) {
      List<double> vals = [];
      for (int m = 1; m <= 12; m++) {
        vals.add((fijo['monto'] as num).toDouble());
      }
      addRow('  ${fijo['item']}', vals);
    }
    // Variables
    for (final cat in expensesCats) {
      List<double> vals = [];
      for (int m = 1; m <= 12; m++) {
        vals.add(_gastosVariables[m]![cat]!);
      }
      if (vals.any((v) => v > 0)) {
        addRow('  $cat', vals);
      }
    }
    // Total Gastos
    List<double> tGas = [];
    for (int m = 1; m <= 12; m++) {
      double s = 0;
      for (final f in _gastosFijos) {
        s += f['monto'];
      }
      for (final cat in expensesCats) {
        s += _gastosVariables[m]![cat]!;
      }
      tGas.add(s);
    }
    addRow('Total Gastos', tGas, isSubtotal: true, textColor: Colors.redAccent);

    // 4. RESULTADOS
    addRow('RESULTADOS', [], isSection: true, textColor: Colors.blue);
    List<double> flujos = [];
    List<double> cajas = [];
    for (int m = 1; m <= 12; m++) {
      flujos.add(_flujoMensual[m]!);
      cajas.add(_cajaAcumulada[m]!);
    }
    addRow('Flujo del Mes', flujos, isSubtotal: true);
    addRow(
      'CAJA ACUMULADA',
      cajas,
      isSubtotal: true,
      textColor: Colors.amber.shade700,
    );

    // Constructor de la tabla scrolleable
    return Column(
      children: [
        // Sticky Header Row (Empty corner + Months)
        Row(
          children: [
            _buildCell(
              '',
              isHeader: true,
              isDark: isDark,
              isFirstCol: true,
              isStickyTop: true,
            ), // Top-left blank
            Expanded(
              child: SingleChildScrollView(
                controller:
                    ScrollController(), // Idealmente sincronizado, pero como no podemos instalar packages facil, vamos a dejar que el scroll horizontal mueva toda la tabla inferior junta
                scrollDirection: Axis.horizontal,
                physics:
                    const NeverScrollableScrollPhysics(), // Este será movido por el body
                child: Row(children: headerMonths),
              ),
            ),
          ],
        ),
        // Body
        Expanded(
          child: SingleChildScrollView(
            controller: _verticalScroll,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fixed First Column
                Column(children: firstColumnCells),
                // Scrollable Data Columns
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontalScroll,
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: dataCells
                          .map((row) => Row(children: row))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCell(
    String text, {
    bool isHeader = false,
    bool isDark = false,
    bool bold = false,
    bool alignLeft = false,
    Color? textColor,
    bool isFirstCol = false,
    double height = _rowHeight,
    bool isStickyTop = false,
  }) {
    Color bgColor = isDark
        ? (isHeader ? const Color(0xFF1E1E1E) : Colors.transparent)
        : (isHeader ? Colors.grey.shade100 : Colors.white);

    // Add alternating row colors or distinct backgrounds if needed here
    if (isFirstCol && !isHeader) {
      bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;
    }

    return Container(
      width: isFirstCol ? _firstColumnWidth : _columnWidth,
      height: height,
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
            width: 0.5,
          ),
          right: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: isHeader ? 12 : 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: textColor,
        ),
      ),
    );
  }
}
