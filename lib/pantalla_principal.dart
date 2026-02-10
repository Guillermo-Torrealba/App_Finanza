import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_settings.dart';
import 'finance_alert.dart';
import 'login_screen.dart';

final supabase = Supabase.instance.client;

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key, required this.settingsController});

  final SettingsController settingsController;

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal>
    with WidgetsBindingObserver {
  final _stream = supabase
      .from('gastos')
      .stream(primaryKey: ['id'])
      .order('fecha', ascending: false);

  final _itemController = TextEditingController();
  final _montoController = TextEditingController();
  final _cuentaController = TextEditingController();

  DateTime _mesVisualizado = DateTime.now();
  String? _categoriaSeleccionada;
  int _indicePestana = 0;

  bool _bloqueada = false;
  bool _desbloqueando = false;
  DateTime? _pausedAt;
  List<String> _cuentasSeleccionadas = [];

  final List<String> _titulosPestanas = const [
    'Mis Finanzas Cloud',
    'Analisis',
    'Crédito',
    'Ajustes',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settingsController.addListener(_onSettingsChanged);
    _cuentaController.text = widget.settingsController.settings.defaultAccount;
    _cuentasSeleccionadas = List<String>.from(
      widget.settingsController.settings.activeAccounts,
    );
    _programarBloqueoInicial();
  }

  @override
  void dispose() {
    widget.settingsController.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    widget.settingsController.removeListener(_onSettingsChanged);
    _itemController.dispose();
    _montoController.dispose();
    _cuentaController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pausedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_bloquearSiCorrespondePorTiempo());
    }
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final settings = widget.settingsController.settings;

    // Validar cuenta por defecto en controller
    if (_cuentaController.text.trim().isEmpty ||
        !settings.activeAccounts.contains(_cuentaController.text)) {
      _cuentaController.text = settings.defaultAccount;
    }

    // Limpiar selección de cuentas eliminadas
    setState(() {
      _cuentasSeleccionadas.removeWhere(
        (acc) => !settings.activeAccounts.contains(acc),
      );

      // Si se desbloqueó desde ajustes
      if (!settings.lockEnabled && _bloqueada) {
        _bloqueada = false;
      }
    });
  }

  void _programarBloqueoInicial() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = widget.settingsController.settings;
      if (!settings.lockEnabled ||
          !widget.settingsController.hasPinConfigured) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _bloqueada = true;
      });
      await _intentarDesbloqueo();
    });
  }

  Future<void> _bloquearSiCorrespondePorTiempo() async {
    final settings = widget.settingsController.settings;
    if (!settings.lockEnabled || !widget.settingsController.hasPinConfigured) {
      return;
    }

    final minutos = settings.autoLockMinutes;
    var debeBloquear = false;
    if (minutos == 0) {
      debeBloquear = true;
    } else if (_pausedAt != null) {
      final diff = DateTime.now().difference(_pausedAt!);
      debeBloquear = diff.inMinutes >= minutos;
    }

    if (!debeBloquear || !mounted) {
      return;
    }

    setState(() {
      _bloqueada = true;
    });
    await _intentarDesbloqueo();
  }

  Future<void> _intentarDesbloqueo({bool forzarPin = false}) async {
    if (_desbloqueando) {
      return;
    }
    _desbloqueando = true;

    var ok = false;
    if (!forzarPin && widget.settingsController.settings.biometricEnabled) {
      ok = await widget.settingsController.authenticateBiometric();
    }
    if (!ok) {
      ok = await _mostrarDialogoPinDesbloqueo();
    }

    if (!mounted) {
      _desbloqueando = false;
      return;
    }

    setState(() {
      _bloqueada = !ok;
    });
    if (!ok) {
      _mostrarSnack('PIN incorrecto');
    }
    _desbloqueando = false;
  }

  Future<bool> _mostrarDialogoPinDesbloqueo() async {
    final pinController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Desbloquear app'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: pinController,
              decoration: const InputDecoration(labelText: 'PIN'),
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                final pin = value?.trim() ?? '';
                if (pin.length < 4 || pin.length > 6) {
                  return 'Debe tener 4 a 6 digitos';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) {
                  return;
                }
                final ok = await widget.settingsController.verifyPin(
                  pinController.text.trim(),
                );
                if (!mounted) {
                  return;
                }
                Navigator.pop(context, ok);
              },
              child: const Text('Desbloquear'),
            ),
          ],
        );
      },
    );

    pinController.dispose();
    return result ?? false;
  }

  IconData obtenerIcono(String categoria) {
    final value = categoria.toLowerCase();
    if (value.contains('comida')) return Icons.restaurant;
    if (value.contains('transporte')) return Icons.directions_bus;
    if (value.contains('regalo')) return Icons.card_giftcard;
    if (value.contains('suscrip')) return Icons.subscriptions;
    if (value.contains('carrete')) return Icons.nightlife;
    if (value.contains('panorama')) return Icons.local_activity;
    if (value.contains('ropa')) return Icons.checkroom;
    if (value.contains('bencina')) return Icons.local_gas_station;
    if (value.contains('salud')) return Icons.medical_services;
    if (value.contains('deporte')) return Icons.sports_soccer;
    if (value.contains('peluquer')) return Icons.content_cut;
    if (value.contains('supermercado')) return Icons.shopping_cart;
    return Icons.sell;
  }

  String _simboloMoneda(String code) {
    switch (code) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'CLP':
      default:
        return '\$';
    }
  }

  String formatoMoneda(num numero, {bool ocultar = false}) {
    if (ocultar) {
      return '••••';
    }
    final settings = widget.settingsController.settings;
    final decimals = settings.currencyCode == 'CLP' ? 0 : 2;
    try {
      final formatter = NumberFormat.currency(
        locale: settings.localeCode,
        name: settings.currencyCode,
        symbol: _simboloMoneda(settings.currencyCode),
        decimalDigits: decimals,
      );
      return formatter.format(numero);
    } catch (_) {
      final abs = numero.abs().toStringAsFixed(decimals);
      return numero < 0
          ? '-${_simboloMoneda(settings.currencyCode)}$abs'
          : '${_simboloMoneda(settings.currencyCode)}$abs';
    }
  }

  String _textoMonto(num numero, {bool ocultable = true}) {
    final ocultar = ocultable && widget.settingsController.settings.hideAmounts;
    return formatoMoneda(numero, ocultar: ocultar);
  }

  String obtenerNombreMes(int mes) {
    const meses = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return meses[mes - 1];
  }

  int calcularSaldo(List<Map<String, dynamic>> movimientos) {
    var saldo = 0;
    for (final mov in movimientos) {
      // Excluir transacciones de crédito del saldo líquido
      if (mov['metodo_pago'] == 'Credito') continue;

      final monto = (mov['monto'] as num? ?? 0).toInt();
      if (mov['tipo'] == 'Ingreso') {
        saldo += monto;
      } else {
        saldo -= monto;
      }
    }
    return saldo;
  }

  int _parseMonto(String value) {
    final onlyNumbers = value.replaceAll(RegExp(r'[^0-9-]'), '');
    return int.tryParse(onlyNumbers) ?? 0;
  }

  void _cambiarMes(int salto) {
    setState(() {
      _mesVisualizado = DateTime(
        _mesVisualizado.year,
        _mesVisualizado.month + salto,
      );
    });
  }

  Future<void> guardarNuevo(String tipo, DateTime fecha) async {
    final settings = widget.settingsController.settings;
    final monto = _parseMonto(_montoController.text);
    final categoria = _categoriaSeleccionada ?? 'Varios';
    final cuenta = _cuentaController.text.trim().isEmpty
        ? settings.defaultAccount
        : _cuentaController.text.trim();
    final fechaStr = fecha.toIso8601String().split('T').first;

    await supabase.from('gastos').insert({
      'user_id': supabase.auth.currentUser!.id,
      'fecha': fechaStr,
      'item': _itemController.text.trim(),
      'monto': monto,
      'categoria': categoria,
      'cuenta': cuenta,
      'tipo': tipo,
    });
    _limpiarYCerrar();
  }

  Future<void> actualizarExistente(int id, DateTime fecha) async {
    final settings = widget.settingsController.settings;
    final monto = _parseMonto(_montoController.text);
    final categoria = _categoriaSeleccionada ?? 'Varios';
    final cuenta = _cuentaController.text.trim().isEmpty
        ? settings.defaultAccount
        : _cuentaController.text.trim();
    final fechaStr = fecha.toIso8601String().split('T').first;

    await supabase
        .from('gastos')
        .update({
          'fecha': fechaStr,
          'item': _itemController.text.trim(),
          'monto': monto,
          'categoria': categoria,
          'cuenta': cuenta,
        })
        .eq('id', id);
    _limpiarYCerrar();
  }

  void _limpiarYCerrar() {
    _itemController.clear();
    _montoController.clear();
    _categoriaSeleccionada = null;
    _cuentaController.text = widget.settingsController.settings.defaultAccount;
    if (mounted) {
      Navigator.pop(context);
    }
  }

  List<Map<String, dynamic>> calcularGastosPorCategoria(
    List<Map<String, dynamic>> movimientosDelMes,
  ) {
    final agrupado = <String, int>{};
    var total = 0;
    for (final mov in movimientosDelMes) {
      if (mov['tipo'] != 'Gasto') {
        continue;
      }
      final cat = (mov['categoria'] ?? 'Varios').toString();
      final monto = (mov['monto'] as num? ?? 0).toInt();
      agrupado[cat] = (agrupado[cat] ?? 0) + monto;
      total += monto;
    }
    final lista = agrupado.entries.map((entry) {
      return {
        'categoria': entry.key,
        'monto': entry.value,
        'porcentaje': total == 0 ? 0.0 : entry.value / total,
      };
    }).toList();
    lista.sort((a, b) => (b['monto'] as int).compareTo(a['monto'] as int));
    return lista;
  }

  Map<String, int> _calcularResumenMes(
    List<Map<String, dynamic>> movimientos,
    DateTime mes,
  ) {
    var ingresos = 0;
    var gastos = 0;
    for (final mov in movimientos) {
      final fechaMov = DateTime.parse(mov['fecha']);
      if (fechaMov.year != mes.year || fechaMov.month != mes.month) {
        continue;
      }
      final monto = (mov['monto'] as num? ?? 0).toInt();
      if (mov['tipo'] == 'Ingreso') {
        ingresos += monto;
      } else {
        gastos += monto;
      }
    }
    return {'ingresos': ingresos, 'gastos': gastos, 'flujo': ingresos - gastos};
  }

  List<Map<String, dynamic>> _calcularSerieFlujoCaja(
    List<Map<String, dynamic>> movimientos, {
    int meses = 6,
  }) {
    final serie = <Map<String, dynamic>>[];
    for (var i = meses - 1; i >= 0; i--) {
      final mes = DateTime(_mesVisualizado.year, _mesVisualizado.month - i, 1);
      final resumen = _calcularResumenMes(movimientos, mes);
      serie.add({
        'mes': mes,
        'ingresos': resumen['ingresos'] ?? 0,
        'gastos': resumen['gastos'] ?? 0,
        'flujo': resumen['flujo'] ?? 0,
      });
    }
    return serie;
  }

  String _mesCorto(DateTime fecha) {
    const meses = [
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
    return meses[fecha.month - 1];
  }

  Map<String, dynamic> _obtenerCategoriaTop(
    List<Map<String, dynamic>> movimientosDelMes,
  ) {
    final desglose = calcularGastosPorCategoria(movimientosDelMes);
    if (desglose.isEmpty) {
      return {'categoria': 'Sin datos', 'monto': 0, 'porcentaje': 0.0};
    }
    return desglose.first;
  }

  DateTime _inicioCiclo(DateTime referencia) {
    final day = widget.settingsController.settings.budgetCycleDay.clamp(1, 28);
    if (referencia.day >= day) {
      return DateTime(referencia.year, referencia.month, day);
    }
    return DateTime(referencia.year, referencia.month - 1, day);
  }

  DateTime _finCicloExclusivo(DateTime inicio) {
    return DateTime(inicio.year, inicio.month + 1, inicio.day);
  }

  List<Map<String, dynamic>> _movimientosEnRango(
    List<Map<String, dynamic>> movimientos,
    DateTime inicio,
    DateTime finExclusivo,
  ) {
    return movimientos.where((mov) {
      final fecha = DateTime.parse(mov['fecha']);
      return !fecha.isBefore(inicio) && fecha.isBefore(finExclusivo);
    }).toList();
  }

  int _sumarGastosEnRango(
    List<Map<String, dynamic>> movimientos,
    DateTime inicio,
    DateTime finInclusive,
  ) {
    var total = 0;
    for (final mov in movimientos) {
      final fecha = DateTime.parse(mov['fecha']);
      if (fecha.isBefore(inicio) || fecha.isAfter(finInclusive)) {
        continue;
      }
      if (mov['tipo'] == 'Gasto') {
        total += (mov['monto'] as num? ?? 0).toInt();
      }
    }
    return total;
  }

  List<FinanceAlert> _generarAlertas(List<Map<String, dynamic>> movimientos) {
    final alerts = <FinanceAlert>[];
    final settings = widget.settingsController.settings;

    final ahora = DateTime.now();
    final inicioCiclo = _inicioCiclo(ahora);
    final finCicloExclusivo = _finCicloExclusivo(inicioCiclo);
    final cicloMov = _movimientosEnRango(
      movimientos,
      inicioCiclo,
      finCicloExclusivo,
    );

    var ingresosCiclo = 0;
    var gastosCiclo = 0;
    for (final mov in cicloMov) {
      final monto = (mov['monto'] as num? ?? 0).toInt();
      if (mov['tipo'] == 'Ingreso') {
        ingresosCiclo += monto;
      } else {
        gastosCiclo += monto;
      }
    }
    final flujoCiclo = ingresosCiclo - gastosCiclo;

    if (settings.enableCashflowAlerts && flujoCiclo < 0) {
      alerts.add(
        FinanceAlert(
          id: 'cashflow_negative',
          title: 'Flujo de caja negativo',
          message:
              'Tu flujo del ciclo actual es ${_textoMonto(flujoCiclo, ocultable: false)}.',
          icon: Icons.trending_down,
          color: Colors.red.shade700,
        ),
      );
    }

    if (settings.enableBudgetAlerts &&
        settings.globalMonthlyBudget != null &&
        settings.globalMonthlyBudget! > 0) {
      final ratio = gastosCiclo / settings.globalMonthlyBudget!;
      final threshold = settings.budgetAlertThresholdPercent / 100;
      if (ratio >= threshold) {
        final pct = (ratio * 100).toStringAsFixed(1);
        alerts.add(
          FinanceAlert(
            id: 'global_budget',
            title: 'Presupuesto global exigido',
            message:
                'Llevas $pct% del presupuesto global (${_textoMonto(settings.globalMonthlyBudget!, ocultable: false)}).',
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.orange.shade700,
          ),
        );
      }

      for (final entry in settings.categoryBudgets.entries) {
        if (entry.value <= 0) {
          continue;
        }
        var gastoCategoria = 0;
        for (final mov in cicloMov) {
          if (mov['tipo'] != 'Gasto') {
            continue;
          }
          if ((mov['categoria'] ?? 'Varios').toString() != entry.key) {
            continue;
          }
          gastoCategoria += (mov['monto'] as num? ?? 0).toInt();
        }
        final ratioCat = gastoCategoria / entry.value;
        if (ratioCat >= threshold) {
          alerts.add(
            FinanceAlert(
              id: 'category_budget_${entry.key}',
              title: 'Categoria en alerta: ${entry.key}',
              message:
                  'Consumo ${(ratioCat * 100).toStringAsFixed(1)}% de su presupuesto.',
              icon: Icons.pie_chart_outline,
              color: Colors.deepOrange.shade700,
            ),
          );
        }
      }
    }

    if (settings.enableUnusualSpendAlerts) {
      final finActual = DateTime(ahora.year, ahora.month, ahora.day);
      final inicioActual = finActual.subtract(const Duration(days: 6));
      final gastoActual = _sumarGastosEnRango(
        movimientos,
        inicioActual,
        finActual,
      );
      final historicos = <int>[];
      for (var i = 1; i <= 8; i++) {
        final finHist = inicioActual.subtract(Duration(days: 1 + (i - 1) * 7));
        final inicioHist = finHist.subtract(const Duration(days: 6));
        historicos.add(_sumarGastosEnRango(movimientos, inicioHist, finHist));
      }
      final validos = historicos.where((x) => x > 0).toList();
      if (validos.isNotEmpty) {
        final promedio = validos.reduce((a, b) => a + b) / validos.length;
        if (promedio > 0 &&
            gastoActual > promedio * settings.unusualSpendMultiplier) {
          alerts.add(
            FinanceAlert(
              id: 'unusual_spend',
              title: 'Gasto inusual detectado',
              message:
                  'Ultimos 7 dias: ${_textoMonto(gastoActual, ocultable: false)} (promedio: ${_textoMonto(promedio.round(), ocultable: false)}).',
              icon: Icons.warning_amber_rounded,
              color: Colors.amber.shade800,
            ),
          );
        }
      }
    }

    return alerts;
  }

  Widget _tarjetaAlerta(FinanceAlert alert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alert.color.withAlpha(24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(alert.icon, color: alert.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: alert.color,
                  ),
                ),
                Text(alert.message),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_titulosPestanas[_indicePestana]),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final todosLosDatos = snapshot.data!;

          return _indicePestana == 0
              ? _construirPaginaInicio(todosLosDatos)
              : _indicePestana == 1
              ? _construirPaginaAnalisis(todosLosDatos)
              : _indicePestana == 2
              ? _construirPaginaCredito(todosLosDatos)
              : _construirPaginaAjustes();
        },
      ),
      floatingActionButton: !_bloqueada
          ? FloatingActionButton(
              onPressed: () => _mostrarDialogo(),
              child: const Icon(Icons.add),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            const SizedBox(width: 16),
            IconButton(
              icon: Icon(
                _indicePestana == 0 ? Icons.home : Icons.home_outlined,
                color: _indicePestana == 0
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              onPressed: () => setState(() => _indicePestana = 0),
              tooltip: 'Inicio',
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                _indicePestana == 1 ? Icons.pie_chart : Icons.pie_chart_outline,
                color: _indicePestana == 1
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              onPressed: () => setState(() => _indicePestana = 1),
              tooltip: 'Analisis',
            ),
            const Spacer(flex: 3), // Gran espacio central
            IconButton(
              icon: Icon(
                _indicePestana == 2
                    ? Icons.credit_card
                    : Icons.credit_card_outlined,
                color: _indicePestana == 2
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              onPressed: () => setState(() => _indicePestana = 2),
              tooltip: 'Crédito',
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                _indicePestana == 3 ? Icons.settings : Icons.settings_outlined,
                color: _indicePestana == 3
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              onPressed: () => setState(() => _indicePestana = 3),
              tooltip: 'Ajustes',
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );

    if (!_bloqueada) {
      return scaffold;
    }

    return Stack(
      children: [
        scaffold,
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withAlpha(215),
            child: Center(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock, size: 40),
                      const SizedBox(height: 12),
                      const Text(
                        'App bloqueada',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Desbloquea para continuar'),
                      const SizedBox(height: 16),
                      if (_desbloqueando)
                        const CircularProgressIndicator()
                      else ...[
                        FilledButton.icon(
                          onPressed: () => _intentarDesbloqueo(),
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Desbloquear'),
                        ),
                        TextButton(
                          onPressed: () => _intentarDesbloqueo(forzarPin: true),
                          child: const Text('Usar PIN'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _construirPaginaInicio(List<Map<String, dynamic>> todosLosDatos) {
    final compacto = widget.settingsController.settings.compactMode;
    final margin = compacto ? 12.0 : 16.0;
    final padding = compacto ? 12.0 : 16.0;

    // Filtrar por cuentas seleccionadas
    final datosFiltrados = todosLosDatos.where((mov) {
      final cuenta = (mov['cuenta'] ?? '').toString();
      return _cuentasSeleccionadas.contains(cuenta);
    }).toList();

    final saldoTotalGlobal = calcularSaldo(datosFiltrados);

    final datosDelMes = datosFiltrados.where((mov) {
      final fechaMov = DateTime.parse(mov['fecha']);
      return fechaMov.year == _mesVisualizado.year &&
          fechaMov.month == _mesVisualizado.month;
    }).toList();

    var ingresoMes = 0;
    var gastoMes = 0;
    for (final mov in datosDelMes) {
      final monto = (mov['monto'] as num? ?? 0).toInt();
      if (mov['tipo'] == 'Ingreso') {
        ingresoMes += monto;
      } else {
        gastoMes += monto;
      }
    }
    final totalNetoMes = ingresoMes - gastoMes;
    final desgloseCategorias = calcularGastosPorCategoria(datosDelMes);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  children: [
                    _selectorCuentas(),
                    const SizedBox(height: 16),
                    const Text(
                      'Saldo Total Disponible',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    Text(
                      _textoMonto(saldoTotalGlobal),
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color: saldoTotalGlobal >= 0
                            ? Colors.teal.shade800
                            : Colors.red.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: EdgeInsets.symmetric(horizontal: margin),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _cambiarMes(-1),
                    ),
                    Text(
                      '${obtenerNombreMes(_mesVisualizado.month)} ${_mesVisualizado.year}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _cambiarMes(1),
                    ),
                  ],
                ),
              ),
              Container(
                margin: EdgeInsets.all(margin),
                padding: EdgeInsets.all(padding),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _construirResumen(
                      'Ingresos',
                      ingresoMes,
                      Colors.green,
                      Icons.arrow_upward,
                    ),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.grey.shade200,
                    ),
                    _construirResumen(
                      'Gastos',
                      gastoMes,
                      Colors.red,
                      Icons.arrow_downward,
                    ),
                    Container(
                      height: 40,
                      width: 1,
                      color: Colors.grey.shade200,
                    ),
                    _construirResumen(
                      'Total Mes',
                      totalNetoMes,
                      Colors.teal,
                      Icons.summarize,
                    ),
                  ],
                ),
              ),
              if (gastoMes > 0) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Gastos por Categoria',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: margin, vertical: 8),
                  padding: EdgeInsets.all(padding),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: desgloseCategorias.map((catData) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      obtenerIcono(
                                        catData['categoria'] as String,
                                      ),
                                      size: 18,
                                      color: Colors.grey.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      catData['categoria'] as String,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  _textoMonto(catData['monto'] as int),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: catData['porcentaje'] as double,
                                backgroundColor: Colors.grey.shade100,
                                color: Colors.teal.shade300,
                                minHeight: 8,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Movimientos',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (datosDelMes.isEmpty)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'Sin movimientos',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = datosDelMes[index];
              final esIngreso = item['tipo'] == 'Ingreso';
              final categoria = (item['categoria'] ?? 'Varios').toString();
              final fechaItem = DateTime.parse(item['fecha']);

              return Container(
                margin: EdgeInsets.symmetric(horizontal: margin, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Dismissible(
                  key: Key(item['id'].toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    decoration: BoxDecoration(
                      color: Colors.red.shade400,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.centerRight,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 20),
                      child: Icon(Icons.delete, color: Colors.white),
                    ),
                  ),
                  onDismissed: (_) async {
                    await supabase.from('gastos').delete().eq('id', item['id']);
                  },
                  child: ListTile(
                    onTap: () => _mostrarDialogo(itemParaEditar: item),
                    leading: CircleAvatar(
                      backgroundColor: esIngreso
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      child: Icon(
                        esIngreso
                            ? Icons.arrow_upward
                            : obtenerIcono(categoria),
                        color: esIngreso ? Colors.green : Colors.red,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      (item['item'] ?? 'Sin nombre').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${fechaItem.day} de ${obtenerNombreMes(fechaItem.month)} · ${(item['cuenta'] ?? '-').toString()}',
                    ),
                    trailing: Text(
                      _textoMonto(item['monto'] as num),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: esIngreso
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ),
                ),
              );
            }, childCount: datosDelMes.length),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }

  Widget _selectorCuentas() {
    final accounts = widget.settingsController.settings.activeAccounts;
    final allSelected =
        _cuentasSeleccionadas.length == accounts.length &&
        _cuentasSeleccionadas.toSet().containsAll(accounts);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: const Text('Todas'),
              selected: allSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _cuentasSeleccionadas = List.from(accounts);
                  } else {
                    // Si deseleccionamos "Todas", ¿qué hacemos?
                    // Quizás dejar solo la por defecto o ninguna?
                    // Dejar ninguna podría mostrar "Sin movimientos".
                    _cuentasSeleccionadas.clear();
                  }
                });
              },
            ),
          ),
          ...accounts.map((account) {
            final isSelected = _cuentasSeleccionadas.contains(account);
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: FilterChip(
                label: Text(account),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _cuentasSeleccionadas.add(account);
                    } else {
                      _cuentasSeleccionadas.remove(account);
                    }
                  });
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _construirPaginaAnalisis(List<Map<String, dynamic>> todosLosDatos) {
    // StreamBuilder removed
    final settings = widget.settingsController.settings;
    final datosDelMes = todosLosDatos.where((mov) {
      final fechaMov = DateTime.parse(mov['fecha']);
      return fechaMov.year == _mesVisualizado.year &&
          fechaMov.month == _mesVisualizado.month;
    }).toList();

    final resumenMes = _calcularResumenMes(todosLosDatos, _mesVisualizado);
    final ingresoMes = resumenMes['ingresos'] ?? 0;
    final gastoMes = resumenMes['gastos'] ?? 0;
    final flujoMes = resumenMes['flujo'] ?? 0;
    final tasaAhorro = ingresoMes > 0 ? (flujoMes / ingresoMes) : 0.0;

    final hoy = DateTime.now();
    final diasDelMes = DateUtils.getDaysInMonth(
      _mesVisualizado.year,
      _mesVisualizado.month,
    );
    final esMesActual =
        hoy.year == _mesVisualizado.year && hoy.month == _mesVisualizado.month;
    var diasTranscurridos = diasDelMes;
    if (esMesActual) {
      diasTranscurridos = hoy.day.clamp(1, diasDelMes);
    }
    final gastoDiarioPromedio = gastoMes / diasTranscurridos;
    final ingresoDiarioPromedio = ingresoMes / diasTranscurridos;
    final proyeccionIngreso = (ingresoDiarioPromedio * diasDelMes).round();
    final proyeccionGasto = (gastoDiarioPromedio * diasDelMes).round();
    final proyeccionFlujo = proyeccionIngreso - proyeccionGasto;

    final serieFlujo = _calcularSerieFlujoCaja(todosLosDatos, meses: 6);
    var sumaFlujo = 0;
    var maxAbsFlujo = 1.0;
    for (final punto in serieFlujo) {
      final flujo = punto['flujo'] as int;
      sumaFlujo += flujo;
      final absFlujo = flujo.abs().toDouble();
      if (absFlujo > maxAbsFlujo) {
        maxAbsFlujo = absFlujo;
      }
    }
    final flujoPromedio6Meses = (sumaFlujo / serieFlujo.length).round();

    final categoriaTop = _obtenerCategoriaTop(datosDelMes);
    final nombreCategoriaTop = categoriaTop['categoria'] as String;
    final montoCategoriaTop = categoriaTop['monto'] as int;
    final porcentajeCategoriaTop = categoriaTop['porcentaje'] as double;

    final presupuestoGlobal = settings.globalMonthlyBudget;
    final consumoPresupuesto =
        presupuestoGlobal != null && presupuestoGlobal > 0
        ? gastoMes / presupuestoGlobal
        : null;
    final cumplimientoMetaAhorro =
        settings.savingsTargetPercent <= 0 || ingresoMes <= 0
        ? null
        : (tasaAhorro * 100) / settings.savingsTargetPercent;
    final alertas = _generarAlertas(todosLosDatos);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alertas.isNotEmpty) ...[
            ...alertas.map(_tarjetaAlerta),
            const SizedBox(height: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _cambiarMes(-1),
                ),
                Text(
                  '${obtenerNombreMes(_mesVisualizado.month)} ${_mesVisualizado.year}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _cambiarMes(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _tarjetaAnalisis(
            titulo: 'Flujo de caja del mes',
            valor: _textoMonto(flujoMes),
            descripcion:
                'Ingresos ${_textoMonto(ingresoMes)} | Gastos ${_textoMonto(gastoMes)}',
            icono: Icons.waterfall_chart,
            color: flujoMes >= 0 ? Colors.teal : Colors.red,
          ),
          const SizedBox(height: 12),
          _tarjetaAnalisis(
            titulo: 'Tasa de ahorro',
            valor: '${(tasaAhorro * 100).toStringAsFixed(1)}%',
            descripcion: ingresoMes > 0
                ? 'Porcentaje de ingreso que queda como ahorro'
                : 'Sin ingresos para calcular tasa',
            icono: Icons.savings_outlined,
            color: tasaAhorro >= 0 ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 12),
          _tarjetaAnalisis(
            titulo: 'Proyeccion de cierre',
            valor: _textoMonto(proyeccionFlujo),
            descripcion: 'Proyeccion mensual basada en promedio diario actual',
            icono: Icons.trending_up,
            color: proyeccionFlujo >= 0 ? Colors.teal : Colors.red,
          ),
          const SizedBox(height: 12),
          _tarjetaAnalisis(
            titulo: 'Gasto diario promedio',
            valor: _textoMonto(gastoDiarioPromedio.round()),
            descripcion:
                'Calculado sobre $diasTranscurridos dia(s) del periodo',
            icono: Icons.calendar_view_day,
            color: Colors.orange.shade700,
          ),
          const SizedBox(height: 12),
          _tarjetaAnalisis(
            titulo: 'Categoria con mayor gasto',
            valor: nombreCategoriaTop,
            descripcion:
                '${_textoMonto(montoCategoriaTop)} (${(porcentajeCategoriaTop * 100).toStringAsFixed(1)}% del gasto)',
            icono: Icons.label_important_outline,
            color: Colors.indigo,
          ),
          if (consumoPresupuesto != null) ...[
            const SizedBox(height: 12),
            _tarjetaAnalisis(
              titulo: 'Consumo de presupuesto global',
              valor: '${(consumoPresupuesto * 100).toStringAsFixed(1)}%',
              descripcion:
                  'Presupuesto ${_textoMonto(presupuestoGlobal!, ocultable: false)}',
              icono: Icons.account_balance_wallet_outlined,
              color: consumoPresupuesto < 0.8
                  ? Colors.green
                  : consumoPresupuesto < 1
                  ? Colors.orange
                  : Colors.red,
            ),
          ],
          if (cumplimientoMetaAhorro != null) ...[
            const SizedBox(height: 12),
            _tarjetaAnalisis(
              titulo: 'Meta de ahorro',
              valor:
                  '${(cumplimientoMetaAhorro * 100).toStringAsFixed(1)}% cumplida',
              descripcion:
                  'Objetivo: ${settings.savingsTargetPercent.toStringAsFixed(1)}%',
              icono: Icons.flag_outlined,
              color: cumplimientoMetaAhorro >= 1 ? Colors.green : Colors.orange,
            ),
          ],
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tendencia de flujo (ultimos 6 meses)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Flujo promedio: ${_textoMonto(flujoPromedio6Meses)}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: serieFlujo.map((punto) {
                      final flujo = punto['flujo'] as int;
                      final altura = ((flujo.abs() / maxAbsFlujo) * 70) + 8;
                      final color = flujo >= 0
                          ? Colors.green.shade400
                          : Colors.red.shade400;
                      return Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 16,
                              height: altura,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _mesCorto(punto['mes'] as DateTime),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaAnalisis({
    required String titulo,
    required String valor,
    required String descripcion,
    required IconData icono,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withAlpha(24),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icono, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  descripcion,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirResumen(
    String titulo,
    int monto,
    Color color,
    IconData icono,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icono, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              titulo,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _textoMonto(monto),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Future<void> _ajustarSaldoCuenta(String cuenta) async {
    try {
      final List<dynamic> response = await supabase
          .from('gastos')
          .select('monto, tipo')
          .eq('cuenta', cuenta);

      var saldoActual = 0;
      for (final mov in response) {
        final monto = (mov['monto'] as num? ?? 0).toInt();
        if (mov['tipo'] == 'Ingreso') {
          saldoActual += monto;
        } else {
          saldoActual -= monto;
        }
      }

      if (!mounted) return;

      final nuevoSaldoStr = await _pedirTexto(
        titulo: 'Ajustar saldo: $cuenta',
        etiqueta:
            'Nuevo saldo (Actual: ${_textoMonto(saldoActual, ocultable: false)})',
        inicial: saldoActual.toString(),
      );

      if (nuevoSaldoStr == null) return;

      final nuevoSaldo = _parseMonto(nuevoSaldoStr);

      if (nuevoSaldo == saldoActual) return;

      final diferencia = nuevoSaldo - saldoActual;
      final esIngreso = diferencia > 0;
      final montoAjuste = diferencia.abs();
      final fechaStr = DateTime.now().toIso8601String().split('T').first;

      await supabase.from('gastos').insert({
        'user_id': supabase.auth.currentUser!.id,
        'fecha': fechaStr,
        'item': 'Ajuste',
        'monto': montoAjuste,
        'categoria': 'Ajuste',
        'cuenta': cuenta,
        'tipo': esIngreso ? 'Ingreso' : 'Gasto',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saldo ajustado correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al ajustar saldo: $e')));
      }
    }
  }

  Widget _construirPaginaAjustes() {
    return AnimatedBuilder(
      animation: widget.settingsController,
      builder: (context, _) {
        final settings = widget.settingsController.settings;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _seccionAjustes(
              titulo: 'Apariencia',
              children: [
                DropdownButtonFormField<String>(
                  value: settings.themeMode,
                  decoration: const InputDecoration(labelText: 'Tema'),
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('Sistema')),
                    DropdownMenuItem(value: 'light', child: Text('Claro')),
                    DropdownMenuItem(value: 'dark', child: Text('Oscuro')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.settingsController.setThemeMode(value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Color principal',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children:
                      [
                        Colors.teal,
                        Colors.blue,
                        Colors.red,
                        Colors.green,
                        Colors.orange,
                        Colors.indigo,
                        Colors.pink,
                        Colors.amber,
                      ].map((color) {
                        final colorValue = color.toARGB32();
                        final selected = settings.seedColorValue == colorValue;
                        return InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => widget.settingsController.setSeedColor(
                            colorValue,
                          ),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                              border: Border.all(
                                color: selected
                                    ? Colors.black
                                    : Colors.transparent,
                                width: 2.2,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Modo compacto'),
                  subtitle: const Text('Reduce espacios y altura de tarjetas'),
                  value: settings.compactMode,
                  onChanged: widget.settingsController.setCompactMode,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ocultar montos'),
                  subtitle: const Text(
                    'Enmascara valores en Inicio y Analisis',
                  ),
                  value: settings.hideAmounts,
                  onChanged: widget.settingsController.setHideAmounts,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _seccionAjustes(
              titulo: 'Formato financiero',
              children: [
                DropdownButtonFormField<String>(
                  value: settings.currencyCode,
                  decoration: const InputDecoration(labelText: 'Moneda'),
                  items: const [
                    DropdownMenuItem(value: 'CLP', child: Text('CLP')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.settingsController.setCurrencyCode(value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: settings.localeCode,
                  decoration: const InputDecoration(labelText: 'Locale'),
                  items: const [
                    DropdownMenuItem(value: 'es_CL', child: Text('es_CL')),
                    DropdownMenuItem(value: 'es_ES', child: Text('es_ES')),
                    DropdownMenuItem(value: 'en_US', child: Text('en_US')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.settingsController.setLocaleCode(value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: settings.weekStartDay,
                  decoration: const InputDecoration(
                    labelText: 'Inicio de semana',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'monday', child: Text('Lunes')),
                    DropdownMenuItem(value: 'sunday', child: Text('Domingo')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.settingsController.setWeekStartDay(value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dia de inicio de ciclo presupuestario'),
                  subtitle: Text('Dia ${settings.budgetCycleDay}'),
                  trailing: SizedBox(
                    width: 170,
                    child: Slider(
                      value: settings.budgetCycleDay.toDouble(),
                      min: 1,
                      max: 28,
                      divisions: 27,
                      label: settings.budgetCycleDay.toString(),
                      onChanged: (value) {
                        widget.settingsController.setBudgetCycleDay(
                          value.round(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _seccionAjustes(
              titulo: 'Cuentas',
              children: [
                ...settings.activeAccounts.map((account) {
                  final isDefault = account == settings.defaultAccount;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(account),
                    subtitle: isDefault
                        ? const Text('Cuenta por defecto')
                        : null,
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Marcar por defecto',
                          icon: const Icon(Icons.check_circle_outline),
                          onPressed: () {
                            widget.settingsController.setDefaultAccount(
                              account,
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Ajustar saldo',
                          icon: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                          onPressed: () => _ajustarSaldoCuenta(account),
                        ),
                        IconButton(
                          tooltip: 'Editar',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editarCuenta(account),
                        ),
                        IconButton(
                          tooltip: 'Archivar',
                          icon: const Icon(Icons.archive_outlined),
                          onPressed: () {
                            widget.settingsController.archiveAccount(account);
                          },
                        ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _agregarCuenta,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar cuenta'),
                  ),
                ),
                if (settings.archivedAccounts.isNotEmpty) ...[
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Cuentas archivadas',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ...settings.archivedAccounts.map((account) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(account),
                      trailing: TextButton(
                        onPressed: () {
                          widget.settingsController.restoreAccount(account);
                        },
                        child: const Text('Restaurar'),
                      ),
                    );
                  }),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _seccionAjustes(
              titulo: 'Categorias',
              children: [
                ...settings.activeCategories.map((category) {
                  final budget = settings.categoryBudgets[category];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(obtenerIcono(category)),
                    title: Text(category),
                    subtitle: budget != null
                        ? Text('Presupuesto: ${formatoMoneda(budget)}')
                        : null,
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Editar',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editarCategoria(category),
                        ),
                        IconButton(
                          tooltip: 'Presupuesto',
                          icon: const Icon(Icons.payments_outlined),
                          onPressed: () =>
                              _editarPresupuestoCategoria(category),
                        ),
                        IconButton(
                          tooltip: 'Archivar',
                          icon: const Icon(Icons.archive_outlined),
                          onPressed: () {
                            widget.settingsController.archiveCategory(category);
                          },
                        ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _agregarCategoria,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar categoria'),
                  ),
                ),
                if (settings.archivedCategories.isNotEmpty) ...[
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Categorias archivadas',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ...settings.archivedCategories.map((category) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(category),
                      trailing: TextButton(
                        onPressed: () {
                          widget.settingsController.restoreCategory(category);
                        },
                        child: const Text('Restaurar'),
                      ),
                    );
                  }),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _seccionAjustes(
              titulo: 'Presupuesto y metas',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Presupuesto global mensual'),
                  subtitle: Text(
                    settings.globalMonthlyBudget == null
                        ? 'Sin definir'
                        : formatoMoneda(settings.globalMonthlyBudget!),
                  ),
                  trailing: TextButton(
                    onPressed: _editarPresupuestoGlobal,
                    child: const Text('Editar'),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Meta de ahorro'),
                  subtitle: Text(
                    '${settings.savingsTargetPercent.toStringAsFixed(1)}%',
                  ),
                ),
                Slider(
                  min: 0,
                  max: 100,
                  divisions: 50,
                  value: settings.savingsTargetPercent,
                  label: '${settings.savingsTargetPercent.toStringAsFixed(1)}%',
                  onChanged: widget.settingsController.setSavingsTargetPercent,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _seccionAjustes(
              titulo: 'Ajustes de Crédito',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Día de facturación tarjeta'),
                  subtitle: Text('Día ${settings.creditCardBillingDay}'),
                  trailing: SizedBox(
                    width: 170,
                    child: Slider(
                      value: settings.creditCardBillingDay.toDouble(),
                      min: 1,
                      max: 31,
                      divisions: 30,
                      label: settings.creditCardBillingDay.toString(),
                      onChanged: (value) {
                        widget.settingsController.setCreditCardBillingDay(
                          value.round(),
                        );
                      },
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Día de vencimiento tarjeta'),
                  subtitle: Text('Día ${settings.creditCardDueDay}'),
                  trailing: SizedBox(
                    width: 170,
                    child: Slider(
                      value: settings.creditCardDueDay.toDouble(),
                      min: 1,
                      max: 31,
                      divisions: 30,
                      label: settings.creditCardDueDay.toString(),
                      onChanged: (value) {
                        widget.settingsController.setCreditCardDueDay(
                          value.round(),
                        );
                      },
                    ),
                  ),
                ),
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Créditos de Consumo',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ...settings.consumptionCredits.map((credit) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(credit['name']),
                    subtitle: Text(
                      '${formatoMoneda(credit['amount'])} - ${credit['installments']} cuotas',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        widget.settingsController.removeConsumptionCredit(
                          credit['id'],
                        );
                      },
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _agregarCreditoConsumo,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar crédito'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _seccionAjustes(
              titulo: 'Alertas tecnicas in-app',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Alertas de presupuesto'),
                  value: settings.enableBudgetAlerts,
                  onChanged: widget.settingsController.setBudgetAlertsEnabled,
                ),
                if (settings.enableBudgetAlerts) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Umbral de alerta de presupuesto'),
                    subtitle: Text(
                      '${settings.budgetAlertThresholdPercent.toStringAsFixed(0)}%',
                    ),
                  ),
                  Slider(
                    min: 50,
                    max: 100,
                    divisions: 50,
                    value: settings.budgetAlertThresholdPercent,
                    label:
                        '${settings.budgetAlertThresholdPercent.toStringAsFixed(0)}%',
                    onChanged: widget
                        .settingsController
                        .setBudgetAlertThresholdPercent,
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Alertas de flujo negativo'),
                  value: settings.enableCashflowAlerts,
                  onChanged: widget.settingsController.setCashflowAlertsEnabled,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Alertas de gasto inusual'),
                  value: settings.enableUnusualSpendAlerts,
                  onChanged: widget.settingsController.setUnusualAlertsEnabled,
                ),
                if (settings.enableUnusualSpendAlerts) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Multiplicador de gasto inusual'),
                    subtitle: Text(
                      '${settings.unusualSpendMultiplier.toStringAsFixed(2)}x',
                    ),
                  ),
                  Slider(
                    min: 1.1,
                    max: 2.5,
                    divisions: 28,
                    value: settings.unusualSpendMultiplier,
                    label:
                        '${settings.unusualSpendMultiplier.toStringAsFixed(2)}x',
                    onChanged:
                        widget.settingsController.setUnusualSpendMultiplier,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _seccionAjustes(
              titulo: 'Seguridad',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bloqueo de app'),
                  subtitle: const Text('Protege con PIN al volver a la app'),
                  value: settings.lockEnabled,
                  onChanged: (value) {
                    unawaited(_cambiarBloqueo(value));
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.settingsController.hasPinConfigured
                        ? 'Cambiar PIN'
                        : 'Configurar PIN',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _configurarPin,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Eliminar PIN'),
                  trailing: const Icon(Icons.delete_outline),
                  onTap: widget.settingsController.hasPinConfigured
                      ? _eliminarPin
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Biometria'),
                  subtitle: Text(
                    widget.settingsController.biometricAvailable
                        ? 'Desbloqueo con huella/rostro'
                        : 'No disponible en este dispositivo',
                  ),
                  value: settings.biometricEnabled,
                  onChanged:
                      (widget.settingsController.biometricAvailable &&
                          settings.lockEnabled &&
                          widget.settingsController.hasPinConfigured)
                      ? (value) {
                          unawaited(_cambiarBiometria(value));
                        }
                      : null,
                ),
                DropdownButtonFormField<int>(
                  value: settings.autoLockMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Auto-bloqueo al volver',
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Inmediato')),
                    DropdownMenuItem(value: 1, child: Text('1 minuto')),
                    DropdownMenuItem(value: 5, child: Text('5 minutos')),
                    DropdownMenuItem(value: 15, child: Text('15 minutos')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.settingsController.setAutoLockMinutes(value);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _seccionAjustes(
              titulo: 'Datos y mantenimiento',
              children: [
                FilledButton.tonalIcon(
                  onPressed: _exportarMovimientosCsv,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Exportar movimientos a CSV'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _resetearAjustes,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Resetear solo ajustes'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await supabase.auth.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => LoginScreen(
                            settingsController: widget.settingsController,
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar Sesión'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                  onPressed: _eliminarTodosMovimientos,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Borrar todos los movimientos'),
                ),
              ],
            ),
            const SizedBox(height: 90),
          ],
        );
      },
    );
  }

  Widget _seccionAjustes({
    required String titulo,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Future<String?> _pedirTexto({
    required String titulo,
    required String etiqueta,
    String? inicial,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return _DialogoTexto(
          titulo: titulo,
          etiqueta: etiqueta,
          inicial: inicial,
        );
      },
    );
  }

  Future<int?> _pedirEntero({
    required String titulo,
    required String etiqueta,
    int? inicial,
  }) async {
    return showDialog<int>(
      context: context,
      builder: (context) {
        return _DialogoEntero(
          titulo: titulo,
          etiqueta: etiqueta,
          inicial: inicial,
        );
      },
    );
  }

  Future<void> _agregarCuenta() async {
    final value = await _pedirTexto(
      titulo: 'Agregar cuenta',
      etiqueta: 'Nombre de cuenta',
    );
    if (value == null) return;

    try {
      widget.settingsController.addAccount(value);
      if (mounted) {
        _mostrarSnack('Cuenta agregada: $value');
      }
    } catch (e) {
      if (mounted) {
        _mostrarSnack('Error al agregar cuenta: $e');
      }
    }
  }

  Future<void> _editarCuenta(String actual) async {
    final value = await _pedirTexto(
      titulo: 'Editar cuenta',
      etiqueta: 'Nombre',
      inicial: actual,
    );
    if (value == null) return;
    widget.settingsController.renameAccount(actual, value);
  }

  Future<void> _agregarCategoria() async {
    final value = await _pedirTexto(
      titulo: 'Agregar categoria',
      etiqueta: 'Nombre de categoria',
    );
    if (value == null) return;
    widget.settingsController.addCategory(value);
  }

  Future<void> _editarCategoria(String actual) async {
    final value = await _pedirTexto(
      titulo: 'Editar categoria',
      etiqueta: 'Nombre',
      inicial: actual,
    );
    if (value == null) return;
    widget.settingsController.renameCategory(actual, value);
  }

  Future<void> _editarPresupuestoGlobal() async {
    final value = await _pedirEntero(
      titulo: 'Presupuesto global',
      etiqueta: 'Monto mensual (vacío para quitar)',
      inicial: widget.settingsController.settings.globalMonthlyBudget,
    );
    widget.settingsController.setGlobalMonthlyBudget(value);
  }

  Future<void> _editarPresupuestoCategoria(String categoria) async {
    final inicial =
        widget.settingsController.settings.categoryBudgets[categoria];
    final value = await _pedirEntero(
      titulo: 'Presupuesto de $categoria',
      etiqueta: 'Monto (vacío para quitar)',
      inicial: inicial,
    );
    widget.settingsController.setCategoryBudget(categoria, value);
  }

  Future<void> _cambiarBloqueo(bool activo) async {
    if (!activo) {
      widget.settingsController.setLockEnabled(false);
      if (mounted) {
        setState(() {
          _bloqueada = false;
        });
      }
      return;
    }

    if (!widget.settingsController.hasPinConfigured) {
      final configured = await _configurarPin();
      if (!configured) {
        return;
      }
    }

    widget.settingsController.setLockEnabled(true);
    if (mounted) {
      setState(() {
        _bloqueada = true;
      });
    }
    await _intentarDesbloqueo();
  }

  Future<bool> _configurarPin() async {
    final pin1 = TextEditingController();
    final pin2 = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final success = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Configurar PIN'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: pin1,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'PIN (4-6 digitos)',
                  ),
                  validator: (value) {
                    final pin = value?.trim() ?? '';
                    if (pin.length < 4 || pin.length > 6) {
                      return 'Debe tener 4 a 6 digitos';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: pin2,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Repite el PIN'),
                  validator: (value) {
                    if ((value?.trim() ?? '') != pin1.text.trim()) {
                      return 'No coincide con el PIN';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) {
                  return;
                }
                await widget.settingsController.setPin(pin1.text.trim());
                if (!mounted) {
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    pin1.dispose();
    pin2.dispose();
    if (success == true) {
      _mostrarSnack('PIN guardado');
    }
    return success ?? false;
  }

  Future<void> _eliminarPin() async {
    final ok = await _confirmar(
      titulo: 'Eliminar PIN',
      mensaje: 'Esta accion desactiva bloqueo y biometria.',
    );
    if (!ok) {
      return;
    }
    await widget.settingsController.clearPin();
    if (mounted) {
      setState(() {
        _bloqueada = false;
      });
    }
    _mostrarSnack('PIN eliminado');
  }

  Future<void> _cambiarBiometria(bool activo) async {
    if (activo) {
      final ok = await widget.settingsController.authenticateBiometric();
      if (!ok) {
        _mostrarSnack('No se pudo validar biometria');
        return;
      }
    }
    widget.settingsController.setBiometricEnabled(activo);
  }

  Future<void> _exportarMovimientosCsv() async {
    try {
      final rows = await supabase
          .from('gastos')
          .select()
          .order('fecha', ascending: true);

      final csv = StringBuffer('fecha,item,monto,categoria,cuenta,tipo\n');
      for (final row in rows) {
        final fecha = (row['fecha'] ?? '').toString();
        final item = _csvEscape((row['item'] ?? '').toString());
        final monto = (row['monto'] ?? '').toString();
        final categoria = _csvEscape((row['categoria'] ?? '').toString());
        final cuenta = _csvEscape((row['cuenta'] ?? '').toString());
        final tipo = _csvEscape((row['tipo'] ?? '').toString());
        csv.writeln('$fecha,$item,$monto,$categoria,$cuenta,$tipo');
      }

      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/movimientos_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(csv.toString(), encoding: utf8);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Exportacion de movimientos',
        ),
      );
    } catch (e) {
      _mostrarSnack('No se pudo exportar CSV: $e');
    }
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _resetearAjustes() async {
    final ok = await _confirmar(
      titulo: 'Resetear ajustes',
      mensaje: 'Se restauraran todas las preferencias a valores por defecto.',
    );
    if (!ok) {
      return;
    }
    await widget.settingsController.resetSettings();
    _cuentaController.text = widget.settingsController.settings.defaultAccount;
    _mostrarSnack('Ajustes restaurados');
  }

  Future<void> _eliminarTodosMovimientos() async {
    final confirm1 = await _confirmar(
      titulo: 'Borrar movimientos',
      mensaje: 'Esta accion elimina todos los movimientos de forma permanente.',
    );
    if (!confirm1) {
      return;
    }
    final texto = await _pedirTexto(
      titulo: 'Confirmacion final',
      etiqueta: 'Escribe ELIMINAR para confirmar',
    );
    if (texto != 'ELIMINAR') {
      _mostrarSnack('Confirmacion invalida');
      return;
    }

    try {
      await supabase.from('gastos').delete().gte('id', 0);
      _mostrarSnack('Todos los movimientos fueron eliminados');
    } catch (e) {
      _mostrarSnack('No se pudieron borrar movimientos: $e');
    }
  }

  Future<bool> _confirmar({
    required String titulo,
    required String mensaje,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(titulo),
          content: Text(mensaje),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _mostrarSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _mostrarDialogo({Map<String, dynamic>? itemParaEditar}) {
    final settings = widget.settingsController.settings;
    final esEdicion = itemParaEditar != null;
    DateTime fechaSeleccionadaEnDialogo;

    final categoriasDisponibles = [
      ...widget.settingsController.settings.activeCategories,
    ];
    if (categoriasDisponibles.isEmpty) {
      categoriasDisponibles.add('Varios');
    }
    final cuentasDisponibles = [...settings.activeAccounts];
    if (cuentasDisponibles.isEmpty) {
      cuentasDisponibles.add(settings.defaultAccount);
    }

    String cuentaSeleccionada;
    bool esCredito = false;

    if (esEdicion) {
      _itemController.text = (itemParaEditar['item'] ?? '').toString();
      _montoController.text = (itemParaEditar['monto'] ?? '').toString();
      fechaSeleccionadaEnDialogo = DateTime.parse(itemParaEditar['fecha']);

      final cat = (itemParaEditar['categoria'] ?? 'Varios').toString();
      if (!categoriasDisponibles.contains(cat)) {
        categoriasDisponibles.add(cat);
      }
      _categoriaSeleccionada = cat;

      cuentaSeleccionada = (itemParaEditar['cuenta'] ?? settings.defaultAccount)
          .toString();
      if (!cuentasDisponibles.contains(cuentaSeleccionada)) {
        cuentasDisponibles.add(cuentaSeleccionada);
      }
      _cuentaController.text = cuentaSeleccionada;

      final metodo = (itemParaEditar['metodo_pago'] ?? 'Debito').toString();
      esCredito = metodo == 'Credito';
    } else {
      _itemController.clear();
      _montoController.clear();
      fechaSeleccionadaEnDialogo = DateTime.now();
      _categoriaSeleccionada = categoriasDisponibles.first;
      cuentaSeleccionada = settings.defaultAccount;
      _cuentaController.text = cuentaSeleccionada;
      esCredito = false;
    }

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> guardarNuevo(String tipo, DateTime fecha) async {
              final montoStr = _montoController.text.trim();
              if (montoStr.isEmpty) return;
              final monto = int.tryParse(montoStr) ?? 0;

              final item = _itemController.text.trim();
              final categoria = _categoriaSeleccionada ?? 'Varios';
              final metodo = esCredito ? 'Credito' : 'Debito';

              try {
                await supabase.from('gastos').insert({
                  'user_id': supabase.auth.currentUser!.id,
                  'fecha': fecha.toIso8601String(),
                  'item': item.isEmpty ? 'Sin nombre' : item,
                  'monto': monto,
                  'categoria': categoria,
                  'cuenta': cuentaSeleccionada,
                  'tipo': tipo,
                  'metodo_pago': metodo,
                });
                if (mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            }

            Future<void> actualizarExistente(int id, DateTime fecha) async {
              final montoStr = _montoController.text.trim();
              if (montoStr.isEmpty) return;
              final monto = int.tryParse(montoStr) ?? 0;

              final item = _itemController.text.trim();
              final categoria = _categoriaSeleccionada ?? 'Varios';
              final metodo = esCredito ? 'Credito' : 'Debito';

              try {
                await supabase
                    .from('gastos')
                    .update({
                      'fecha': fecha.toIso8601String(),
                      'item': item.isEmpty ? 'Sin nombre' : item,
                      'monto': monto,
                      'categoria': categoria,
                      'cuenta': cuentaSeleccionada,
                      'metodo_pago': metodo,
                    })
                    .eq('id', id);
                if (mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                esEdicion ? 'Editar movimiento' : 'Nuevo movimiento',
                textAlign: TextAlign.center,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _itemController,
                      decoration: InputDecoration(
                        labelText: 'Concepto',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: fechaSeleccionadaEnDialogo,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setStateDialog(() {
                            fechaSeleccionadaEnDialogo = picked;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Fecha',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: const Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          '${fechaSeleccionadaEnDialogo.day}/${fechaSeleccionadaEnDialogo.month}/${fechaSeleccionadaEnDialogo.year}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _categoriaSeleccionada,
                      decoration: InputDecoration(
                        labelText: 'Categoria',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: categoriasDisponibles
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Row(
                                children: [
                                  Icon(obtenerIcono(c), color: Colors.teal),
                                  const SizedBox(width: 8),
                                  Text(c),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setStateDialog(() {
                          _categoriaSeleccionada = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: cuentaSeleccionada,
                      decoration: InputDecoration(
                        labelText: 'Cuenta',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: cuentasDisponibles
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setStateDialog(() {
                          cuentaSeleccionada = value;
                          _cuentaController.text = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text(
                          'Método de pago:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment<bool>(
                                value: false,
                                label: Text('Débito'),
                                icon: Icon(Icons.account_balance_wallet),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                label: Text('Crédito'),
                                icon: Icon(Icons.credit_card),
                              ),
                            ],
                            selected: {esCredito},
                            onSelectionChanged: (Set<bool> newSelection) {
                              setStateDialog(() {
                                esCredito = newSelection.first;
                              });
                            },
                            style: ButtonStyle(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _montoController,
                      decoration: InputDecoration(
                        labelText: 'Monto',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceAround,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                if (esEdicion)
                  ElevatedButton(
                    onPressed: () => actualizarExistente(
                      itemParaEditar['id'] as int,
                      fechaSeleccionadaEnDialogo,
                    ),
                    child: const Text('Guardar'),
                  )
                else ...[
                  ElevatedButton(
                    onPressed: () =>
                        guardarNuevo('Gasto', fechaSeleccionadaEnDialogo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade100,
                      foregroundColor: Colors.red.shade800,
                    ),
                    child: const Text('Gasto'),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        guardarNuevo('Ingreso', fechaSeleccionadaEnDialogo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade100,
                      foregroundColor: Colors.green.shade800,
                    ),
                    child: const Text('Ingreso'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _construirPaginaCredito(List<Map<String, dynamic>> todosLosDatos) {
    final settings = widget.settingsController.settings;
    final now = DateTime.now();
    final billingDay = settings.creditCardBillingDay;
    final dueDay = settings.creditCardDueDay;

    // --- Lógica de Ciclos de Tarjeta ---
    // Calculamos el cutoff del mes actual
    final cutoffThisMonth = DateTime(now.year, now.month, billingDay);

    // Si hoy es después del corte, el ciclo actual empezó el día siguiente al corte (BillingDay + 1)
    // y termina el próximo BillingDay.
    // Si hoy es antes del corte, el ciclo actual empezó el mes pasado.

    DateTime cycleStart;
    DateTime cycleEnd;
    DateTime lastCycleStart;
    DateTime lastCycleEnd;

    if (now.isAfter(cutoffThisMonth)) {
      // Estamos en el ciclo que cierra el mes que viene
      cycleStart = cutoffThisMonth.add(const Duration(days: 1));
      cycleEnd = DateTime(now.year, now.month + 1, billingDay);

      lastCycleEnd = cutoffThisMonth;
      lastCycleStart = DateTime(
        now.year,
        now.month - 1,
        billingDay,
      ).add(const Duration(days: 1));
    } else {
      // Estamos en el ciclo que cierra este mes
      cycleEnd = cutoffThisMonth;
      cycleStart = DateTime(
        now.year,
        now.month - 1,
        billingDay,
      ).add(const Duration(days: 1));

      lastCycleEnd = cycleStart.subtract(const Duration(days: 1));
      lastCycleStart = DateTime(
        now.year,
        now.month - 2,
        billingDay,
      ).add(const Duration(days: 1));
    }

    final creditExpenses = todosLosDatos
        .where(
          (m) =>
              (m['metodo_pago'] ?? 'Debito') == 'Credito' &&
              (m['tipo'] == 'Gasto'),
        )
        .toList();

    int calcularTotal(List<dynamic> movimientos, DateTime start, DateTime end) {
      var total = 0;
      for (final m in movimientos) {
        final d = DateTime.parse(m['fecha']);
        // start <= d <= end
        // Simplificación: check year/month/day comparisons or just logic
        // Usando compareTo para asegurar
        if (!d.isBefore(start) && !d.isAfter(end)) {
          total += (m['monto'] as num).toInt();
        }
      }
      return total;
    }

    // Nota: cycleStart es inclusive, cycleEnd es inclusive (el día de corte entra)
    // Ajustar lógica de "isBefore" / "isAfter"
    // isBefore(start) falsificará si es == start? No. isBefore es estricto.
    // !isBefore(start) -> >= start
    // !isAfter(end) -> <= end

    // Ajuste fino de fechas a inicio/fin de día
    final curStart = DateTime(
      cycleStart.year,
      cycleStart.month,
      cycleStart.day,
    );
    final curEnd = DateTime(
      cycleEnd.year,
      cycleEnd.month,
      cycleEnd.day,
      23,
      59,
      59,
    );

    final lastStart = DateTime(
      lastCycleStart.year,
      lastCycleStart.month,
      lastCycleStart.day,
    );
    final lastEnd = DateTime(
      lastCycleEnd.year,
      lastCycleEnd.month,
      lastCycleEnd.day,
      23,
      59,
      59,
    );

    final porFacturar = calcularTotal(creditExpenses, curStart, curEnd);
    final facturado = calcularTotal(creditExpenses, lastStart, lastEnd);

    // --- Fin Lógica ---

    // Calcular fechas para el mes visualizado
    final firstDayOfMonth = DateTime(
      _mesVisualizado.year,
      _mesVisualizado.month,
      1,
    );
    final daysInMonth = DateUtils.getDaysInMonth(
      firstDayOfMonth.year,
      firstDayOfMonth.month,
    );

    // Offset para empezar el calendario en el día correcto de la semana (Lunes=1)
    // DateTime.weekday devuelve 1 para Lunes, 7 para Domingo.
    // Si queremos empezar en Lunes, el offset es weekday - 1.
    // Si queremos empezar en Domingo, y weekday es 7 (Dom), offset 0. Si es 1 (Lun), offset 1.
    // Asumiremos inicio Lunes por simplicidad o configurar según settings.
    final startingWeekday = firstDayOfMonth.weekday;
    final offset = startingWeekday - 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tarjetas de Resumen
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Por Facturar',
                        style: TextStyle(color: Colors.indigo),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _textoMonto(porFacturar),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      Text(
                        '${curStart.day}/${curStart.month} - ${curEnd.day}/${curEnd.month}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.indigo.shade300,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.shade100),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Facturado',
                        style: TextStyle(color: Colors.deepOrange),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _textoMonto(facturado),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                      Text(
                        '${lastStart.day}/${lastStart.month} - ${lastEnd.day}/${lastEnd.month}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.deepOrange.shade300,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _cambiarMes(-1),
                ),
                Text(
                  '${obtenerNombreMes(_mesVisualizado.month)} ${_mesVisualizado.year}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _cambiarMes(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Calendario
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                // Cabecera días semana
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: ['L', 'M', 'M', 'J', 'V', 'S', 'D']
                      .map(
                        (d) => Text(
                          d,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: daysInMonth + offset,
                  itemBuilder: (context, index) {
                    if (index < offset) {
                      return const SizedBox();
                    }
                    final day = index - offset + 1;
                    final date = DateTime(
                      _mesVisualizado.year,
                      _mesVisualizado.month,
                      day,
                    );

                    bool isBilling = day == billingDay;
                    bool isDue = day == dueDay;
                    bool isToday =
                        date.year == now.year &&
                        date.month == now.month &&
                        date.day == now.day;

                    // Chequear si hay créditos que se pagan hoy
                    final creditosHoy = settings.consumptionCredits.where((c) {
                      final paymentDay = c['paymentDay'] as int;
                      // Verificar si el crédito está activo en esta fecha
                      final start = DateTime.parse(c['startDate']);
                      final end = DateTime(
                        start.year,
                        start.month + (c['installments'] as int),
                        start.day,
                      );
                      return day == paymentDay &&
                          !date.isBefore(start) &&
                          date.isBefore(end);
                    }).toList();

                    final hasCreditPayment = creditosHoy.isNotEmpty;

                    Color? bgColor;
                    Color textColor = Colors.black87;

                    if (isToday) {
                      bgColor = Colors.blue.shade50;
                      textColor = Colors.blue.shade900;
                    }
                    if (isBilling) {
                      bgColor = Colors.indigo.shade100;
                      textColor = Colors.indigo.shade900;
                    }
                    if (isDue) {
                      bgColor = Colors.red.shade100;
                      textColor = Colors.red.shade900;
                    }
                    if (hasCreditPayment) {
                      // Si coincide con otros eventos, mostramos indicador visual extra o color mezclado
                      // Prioridad visual: Vencimiento > Facturación > Crédito
                      if (!isDue && !isBilling) {
                        bgColor = Colors.green.shade100;
                        textColor = Colors.green.shade900;
                      }
                    }

                    return Container(
                      decoration: BoxDecoration(
                        color: bgColor,
                        shape: BoxShape.circle,
                        border: isToday
                            ? Border.all(color: Colors.blue, width: 2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          if (hasCreditPayment)
                            Positioned(
                              bottom: 4,
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade700,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _leyendaCalendario(Colors.indigo.shade100, 'Facturación'),
                    _leyendaCalendario(Colors.red.shade100, 'Vencimiento'),
                    _leyendaCalendario(Colors.green.shade100, 'Crédito'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'Próximos eventos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _construirEventosDelMes(settings, daysInMonth),

          const SizedBox(height: 24),
          const Text(
            'Créditos de Consumo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (settings.consumptionCredits.isEmpty)
            const Text(
              'No hay créditos activos',
              style: TextStyle(color: Colors.grey),
            )
          else
            ...settings.consumptionCredits.map(
              (c) => _tarjetaCreditoConsumo(c),
            ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _leyendaCalendario(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _construirEventosDelMes(AppSettings settings, int daysInMonth) {
    final eventos = <Map<String, dynamic>>[];

    // Facturación
    if (settings.creditCardBillingDay <= daysInMonth) {
      eventos.add({
        'day': settings.creditCardBillingDay,
        'title': 'Cierre de facturación',
        'color': Colors.indigo,
        'icon': Icons.receipt_long,
      });
    }

    // Vencimiento
    if (settings.creditCardDueDay <= daysInMonth) {
      eventos.add({
        'day': settings.creditCardDueDay,
        'title': 'Vencimiento tarjeta',
        'color': Colors.red,
        'icon': Icons.warning_amber_rounded,
      });
    }

    // Créditos
    for (final c in settings.consumptionCredits) {
      final payDay = c['paymentDay'] as int;
      if (payDay <= daysInMonth) {
        final start = DateTime.parse(c['startDate']);
        final end = DateTime(
          start.year,
          start.month + (c['installments'] as int),
          start.day,
        );
        final current = DateTime(
          _mesVisualizado.year,
          _mesVisualizado.month,
          payDay,
        );

        if (!current.isBefore(start) && current.isBefore(end)) {
          // Calcular número de cuota
          // Aproximación simple meses
          int cuota =
              (current.year - start.year) * 12 +
              current.month -
              start.month +
              1;
          if (start.day > payDay)
            cuota--; // Ajuste si el día de pago es menor al inicio
          if (cuota < 1) cuota = 1;

          eventos.add({
            'day': payDay,
            'title': '${c['name']} (Cuota $cuota/${c['installments']})',
            'monto': c['amount'],
            'color': Colors.green,
            'icon': Icons.account_balance,
          });
        }
      }
    }

    eventos.sort((a, b) => (a['day'] as int).compareTo(b['day'] as int));

    return Column(
      children: eventos.map((e) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: (e['color'] as Color).withAlpha(30),
              child: Icon(
                e['icon'] as IconData,
                color: e['color'] as Color,
                size: 20,
              ),
            ),
            title: Text(
              e['title'] as String,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: e.containsKey('monto')
                ? Text(
                    _textoMonto(e['monto'] as int),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  )
                : Text(
                    'Día ${e['day']}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
          ),
        );
      }).toList(),
    );
  }

  Widget _tarjetaCreditoConsumo(Map<String, dynamic> credit) {
    // Calculos
    final start = DateTime.parse(credit['startDate']);
    final totalCuotas = credit['installments'] as int;
    final montoCuota = credit['amount'] as int;

    // Cuotas pagadas aprox
    final now = DateTime.now();
    int cuotasPagadas = (now.year - start.year) * 12 + now.month - start.month;
    if (now.day < (credit['paymentDay'] as int)) cuotasPagadas--;
    if (cuotasPagadas < 0) cuotasPagadas = 0;
    if (cuotasPagadas > totalCuotas) cuotasPagadas = totalCuotas;

    final progreso = cuotasPagadas / totalCuotas;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                credit['name'],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _textoMonto(montoCuota),
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Cuota $cuotasPagadas de $totalCuotas',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progreso,
              backgroundColor: Colors.grey.shade100,
              color: Colors.teal,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Próximo pago: día ${credit['paymentDay']}',
            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Future<void> _agregarCreditoConsumo() async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final installmentsCtrl = TextEditingController();
    final paymentDayCtrl = TextEditingController();
    DateTime? startDate;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: const Text('Nuevo Crédito'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre (ej. Crédito Coche)',
                      ),
                    ),
                    TextField(
                      controller: amountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Monto Cuota',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    TextField(
                      controller: installmentsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Total Cuotas',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    TextField(
                      controller: paymentDayCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Día de pago (1-31)',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: Text(
                        startDate == null
                            ? 'Seleccionar fecha inicio'
                            : 'Inicio: ${startDate!.toLocal().toString().split(' ')[0]}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setStateSB(() => startDate = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.isEmpty ||
                        amountCtrl.text.isEmpty ||
                        installmentsCtrl.text.isEmpty ||
                        paymentDayCtrl.text.isEmpty ||
                        startDate == null) {
                      return;
                    }

                    final credit = {
                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                      'name': nameCtrl.text.trim(),
                      'amount': int.parse(amountCtrl.text.trim()),
                      'installments': int.parse(installmentsCtrl.text.trim()),
                      'paymentDay': int.parse(
                        paymentDayCtrl.text.trim(),
                      ).clamp(1, 31),
                      'startDate': startDate!.toIso8601String(),
                    };

                    widget.settingsController.addConsumptionCredit(credit);
                    Navigator.pop(context);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DialogoTexto extends StatefulWidget {
  final String titulo;
  final String etiqueta;
  final String? inicial;

  const _DialogoTexto({
    required this.titulo,
    required this.etiqueta,
    this.inicial,
  });

  @override
  State<_DialogoTexto> createState() => _DialogoTextoState();
}

class _DialogoTextoState extends State<_DialogoTexto> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.inicial ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(labelText: widget.etiqueta),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isEmpty) {
              Navigator.pop(context, null);
            } else {
              Navigator.pop(context, text);
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _DialogoEntero extends StatefulWidget {
  final String titulo;
  final String etiqueta;
  final int? inicial;

  const _DialogoEntero({
    required this.titulo,
    required this.etiqueta,
    this.inicial,
  });

  @override
  State<_DialogoEntero> createState() => _DialogoEnteroState();
}

class _DialogoEnteroState extends State<_DialogoEntero> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.inicial == null ? '' : widget.inicial.toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: widget.etiqueta),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final parsed = int.tryParse(_controller.text.trim());
            Navigator.pop(context, parsed);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
