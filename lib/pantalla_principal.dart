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

  final List<String> _titulosPestanas = const [
    'Mis Finanzas Cloud',
    'Analisis',
    'Historial',
    'Ajustes',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settingsController.addListener(_onSettingsChanged);
    _cuentaController.text = widget.settingsController.settings.defaultAccount;
    _programarBloqueoInicial();
  }

  @override
  void dispose() {
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
    final settings = widget.settingsController.settings;
    if (_cuentaController.text.trim().isEmpty) {
      _cuentaController.text = settings.defaultAccount;
    }
    if (!settings.lockEnabled && _bloqueada && mounted) {
      setState(() {
        _bloqueada = false;
      });
    }
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

  List<String> get _categoriasActivas =>
      widget.settingsController.settings.activeCategories;

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
        App_Finanzas,
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
      body: _indicePestana == 0
          ? _construirPaginaInicio()
          : _indicePestana == 1
          ? _construirPaginaAnalisis()
          : _indicePestana == 2
          ? const Center(child: Text('Proximamente: Historial detallado'))
          : _construirPaginaAjustes(),
      floatingActionButton: _indicePestana == 0 && !_bloqueada
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
                _indicePestana == 2 ? Icons.history : Icons.history_outlined,
                color: _indicePestana == 2
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              onPressed: () => setState(() => _indicePestana = 2),
              tooltip: 'Historial',
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

  Widget _construirPaginaInicio() {
    final compacto = widget.settingsController.settings.compactMode;
    final margin = compacto ? 12.0 : 16.0;
    final padding = compacto ? 12.0 : 16.0;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final todosLosDatos = snapshot.data!;
        final saldoTotalGlobal = calcularSaldo(todosLosDatos);
        final alertas = _generarAlertas(todosLosDatos);

        final datosDelMes = todosLosDatos.where((mov) {
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
                  if (alertas.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(margin, 0, margin, 12),
                      child: Column(
                        children: alertas.map(_tarjetaAlerta).toList(),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      children: [
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
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 5,
                      ),
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
                      margin: EdgeInsets.symmetric(
                        horizontal: margin,
                        vertical: 8,
                      ),
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
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
                    margin: EdgeInsets.symmetric(
                      horizontal: margin,
                      vertical: 4,
                    ),
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
                        await supabase
                            .from('gastos')
                            .delete()
                            .eq('id', item['id']);
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
      },
    );
  }

  Widget _construirPaginaAnalisis() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final settings = widget.settingsController.settings;
        final todosLosDatos = snapshot.data!;
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
            hoy.year == _mesVisualizado.year &&
            hoy.month == _mesVisualizado.month;
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
                descripcion:
                    'Proyeccion mensual basada en promedio diario actual',
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
                  color: cumplimientoMetaAhorro >= 1
                      ? Colors.green
                      : Colors.orange,
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
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
      },
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
                  max: 60,
                  divisions: 60,
                  value: settings.savingsTargetPercent,
                  label: '${settings.savingsTargetPercent.toStringAsFixed(1)}%',
                  onChanged: widget.settingsController.setSavingsTargetPercent,
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
    final controller = TextEditingController(text: inicial ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(titulo),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: etiqueta),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  Future<int?> _pedirEntero({
    required String titulo,
    required String etiqueta,
    int? inicial,
  }) async {
    final controller = TextEditingController(
      text: inicial == null ? '' : inicial.toString(),
    );
    final value = await showDialog<int?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(titulo),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: etiqueta),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                Navigator.pop(context, parsed);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return value;
  }

  Future<void> _agregarCuenta() async {
    final value = await _pedirTexto(
      titulo: 'Agregar cuenta',
      etiqueta: 'Nombre de cuenta',
    );
    if (value == null) return;
    widget.settingsController.addAccount(value);
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

    final categoriasDisponibles = [..._categoriasActivas];
    if (categoriasDisponibles.isEmpty) {
      categoriasDisponibles.add('Varios');
    }
    final cuentasDisponibles = [...settings.activeAccounts];
    if (cuentasDisponibles.isEmpty) {
      cuentasDisponibles.add(settings.defaultAccount);
    }

    String cuentaSeleccionada;
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
    } else {
      _itemController.clear();
      _montoController.clear();
      fechaSeleccionadaEnDialogo = DateTime.now();
      _categoriaSeleccionada = categoriasDisponibles.first;
      cuentaSeleccionada = settings.defaultAccount;
      _cuentaController.text = cuentaSeleccionada;
    }

    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
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
}
