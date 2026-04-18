import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:ui';
import 'dart:math';
import 'package:shimmer/shimmer.dart';
// speech_to_text removed – Windows plugin (beta) breaks native build.
// Voice input gracefully disabled on unsupported platforms.

import 'app_settings.dart';
import 'push_notification_service.dart';
import 'finance_alert.dart';
import 'flujo_caja_screen.dart';
import 'login_screen.dart';
import 'pantalla_recurrentes.dart';
import 'gastos_compartidos_screen.dart';
import 'ai_insights_service.dart';
import 'app_secrets.dart';

final supabase = Supabase.instance.client;

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key, required this.settingsController});

  final SettingsController settingsController;

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal>
    with WidgetsBindingObserver {
  static const String _itemAbonoTarjeta = 'Abono TC';
  static const String _itemPagoFacturadoTarjeta = 'Pago Facturado TC';

  final _stream = supabase
      .from('gastos')
      .stream(primaryKey: ['id'])
      .order('fecha', ascending: false);

  final _porCobrarStream = supabase
      .from('gastos_compartidos')
      .stream(primaryKey: ['id'])
      .eq('pagado', false);

  final _itemController = TextEditingController();
  final _detalleController = TextEditingController();
  final _montoController = TextEditingController();
  final _cuentaController = TextEditingController();

  List<Map<String, dynamic>>? _cachedGastos;
  List<Map<String, dynamic>>? _cachedMetas;

  DateTime _mesVisualizado = DateTime.now();
  String? _categoriaSeleccionada;
  int _indicePestana = 0;

  bool _bloqueada = false;
  bool _desbloqueando = false;
  bool _editandoPresupuesto = false;
  bool _alertasExpandidas = true;
  DateTime? _pausedAt;
  List<String> _cuentasSeleccionadas = [];
  bool _mostrarPorcentaje = false;
  List<Map<String, dynamic>> _recurrentes = [];
  int _metasRefreshNonce = 0;

  // AI Insights state
  final AiInsightsService _aiService = AiInsightsService(
    apiKey: AppSecrets.openAiApiKey,
  );
  AiInsightsResult? _aiResult;
  bool _aiLoading = false;
  String? _aiError;
  bool _aiExpanded = true;

  // AI Proactive Alerts state
  List<AiProactiveAlert> _aiProactiveAlerts = [];
  bool _aiAlertsChecked = false;

  // AI Weekly Summary state
  bool _weeklySummaryChecked = false;

  // Search & sort state
  final _busquedaController = TextEditingController();
  String _textoBusqueda = '';
  String _ordenamiento =
      'fecha_desc'; // fecha_desc, fecha_asc, monto_desc, monto_asc
  bool _ordenamientoVisible = false;
  String _filtroTipo = 'Todos'; // Todos, Gasto, Ingreso
  int? _limiteMovimientos = 15;

  List<String> get _titulosPestanas {
    final hasCreditCard = widget.settingsController.settings.hasCreditCard;
    if (hasCreditCard) {
      return const [
        'Mis Finanzas Cloud',
        'Analisis',
        'Metas',
        'Presupuestos',
        'Planificación',
        'Más',
      ];
    } else {
      return const [
        'Mis Finanzas Cloud',
        'Analisis',
        'Metas',
        'Presupuestos',
        'Más',
      ];
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settingsController.addListener(_onSettingsChanged);
    _cuentaController.text = widget.settingsController.settings.defaultAccount;
    _cuentasSeleccionadas = List<String>.from(
      widget.settingsController.settings.activeAccounts,
    );
    _cargarCacheLocal();
    _programarBloqueoInicial();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chequearRecurrentes();
      _cargarRecurrentes();
      _checkAndGenerateAiAlerts();
      _checkWeeklySummary();
    });
  }

  void _cargarCacheLocal() {
    final prefs = widget.settingsController.preferences;
    try {
      final strGastos = prefs.getString('gastos_cache');
      if (strGastos != null) {
        final List decoded = jsonDecode(strGastos);
        _cachedGastos = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      final strMetas = prefs.getString('metas_cache');
      if (strMetas != null) {
        final List decoded = jsonDecode(strMetas);
        _cachedMetas = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('Error leyendo cache: $e');
    }
  }

  @override
  void dispose() {
    widget.settingsController.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    widget.settingsController.removeListener(_onSettingsChanged);
    _itemController.dispose();
    _detalleController.dispose();
    _montoController.dispose();
    _cuentaController.dispose();
    _busquedaController.dispose();
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

      // Ajustar índice de pestaña si deshabilitan la tarjeta
      if (!settings.hasCreditCard && _indicePestana > 3) {
        _indicePestana = 4; // 'Más' is now at index 4 if no credit card
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
                if (!context.mounted) {
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
    // Gastos
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
    // Ingresos
    if (value.contains('sueldo')) return Icons.work;
    if (value.contains('freelance')) return Icons.laptop;
    if (value.contains('transferencia')) return Icons.swap_horiz;
    if (value.contains('inversio')) return Icons.trending_up;
    if (value.contains('reembolso')) return Icons.replay;
    if (value.contains('arriendo')) return Icons.home;
    if (value.contains('venta')) return Icons.storefront;
    if (value.contains('mesada')) return Icons.savings;
    if (value.contains('otros ingreso')) return Icons.attach_money;
    return Icons.sell;
  }

  /// Returns a Widget for the category: emoji Text if user set one,
  /// otherwise the default Material Icon.
  Widget _iconoCategoria(String categoria, {double size = 20, Color? color}) {
    final emoji = widget.settingsController.settings.categoryEmojis[categoria];
    if (emoji != null && emoji.isNotEmpty) {
      return Text(emoji, style: TextStyle(fontSize: size));
    }
    return Icon(obtenerIcono(categoria), size: size, color: color);
  }

  static const _emojisDisponibles = [
    // Comida y bebida
    '🍔', '🍕', '🍣', '🍜', '🍩', '🥗', '🧁', '☕', '🍺', '🥤', '🍷',
    // Compras y comercio
    '🛒', '🛍️', '👗', '👟', '💄', '🎁', '💻', '📱', '🎮',
    // Transporte
    '🚗', '🚌', '✈️', '🚲', '⛽', '🚕', '🏍️',
    // Hogar y servicios
    '🏠', '💡', '🔧', '🧹', '📦', '🛋️',
    // Salud y bienestar
    '💊', '🏥', '🧘', '💆', '✂️', '🦷',
    // Entretenimiento
    '🎬', '🎵', '🎭', '⚽', '🏋️', '🎪', '🎯', '🎲',
    // Dinero y finanzas
    '💰', '💳', '🏦', '📈', '💵', '🪙', '💎',
    // Educación y trabajo
    '📚', '🎓', '💼', '✏️', '🖥️',
    // Viajes
    '🌴', '🏖️', '🗺️', '🧳', '🏔️',
    // Mascotas y naturaleza
    '🐶', '🐱', '🌿', '🌻',
    // Otros
    '❤️', '⭐', '🔥', '📌', '🎉', '🧾', '📋', '🔔',
  ];

  Future<String?> _elegirEmoji(String categoria) async {
    final emojiActual =
        widget.settingsController.settings.categoryEmojis[categoria];
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Emoji para "$categoria"'),
          content: SizedBox(
            width: 320,
            height: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (emojiActual != null && emojiActual.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Text(
                          'Actual: $emojiActual',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Quitar'),
                          onPressed: () => Navigator.pop(context, ''),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                    itemCount: _emojisDisponibles.length,
                    itemBuilder: (context, index) {
                      final emoji = _emojisDisponibles[index];
                      final isSelected = emoji == emojiActual;
                      return GestureDetector(
                        onTap: () => Navigator.pop(context, emoji),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.teal.shade100
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(
                                    color: Colors.teal.shade400,
                                    width: 2,
                                  )
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _mostrarEmojiCategoria(String categoria) async {
    final result = await _elegirEmoji(categoria);
    if (result == null) return; // cancelled
    widget.settingsController.setCategoryEmoji(
      categoria,
      result.isEmpty ? null : result,
    );
  }

  /// Animated bottom navigation icon with bounce & color transition
  Widget _navIcon({
    required IconData filled,
    required IconData outlined,
    required int index,
    required String tooltip,
  }) {
    final isSelected = _indicePestana == index;
    return Expanded(
      child: IconButton(
        icon: AnimatedScale(
          scale: isSelected ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Icon(
              isSelected ? filled : outlined,
              key: ValueKey<bool>(isSelected),
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
          ),
        ),
        onPressed: () {
          HapticFeedback.lightImpact();
          setState(() => _indicePestana = index);
        },
        tooltip: tooltip,
      ),
    );
  }

  Widget _chipOrden({
    required String label,
    required IconData icono,
    required String valor,
    required String descripcion,
  }) {
    final seleccionado = _ordenamiento == valor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: Tooltip(
        message: descripcion,
        child: ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icono,
                size: 14,
                color: seleccionado
                    ? (isDark ? Colors.black87 : Colors.white)
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: seleccionado
                        ? (isDark ? Colors.black87 : Colors.white)
                        : (isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade800),
                  ),
                ),
              ),
            ],
          ),
          selected: seleccionado,
          selectedColor: Colors.teal.shade400,
          backgroundColor: Theme.of(context).cardColor,
          side: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.transparent,
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          onSelected: (_) => setState(() => _ordenamiento = valor),
        ),
      ),
    );
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
      // Excluir movimientos fantasma del saldo real
      if ((mov['estado'] ?? 'real') == 'fantasma') continue;

      final monto = (mov['monto'] as num? ?? 0).toInt();
      if (mov['tipo'] == 'Ingreso') {
        saldo += monto;
      } else {
        saldo -= monto;
      }
    }
    return saldo;
  }

  DateTime _inicioDelDia(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _finDelDia(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59);

  DateTime _fechaMesSegura(
    int year,
    int month,
    int preferredDay, {
    bool finDeDia = false,
  }) {
    final diasDelMes = DateUtils.getDaysInMonth(year, month);
    final diaSeguro = preferredDay.clamp(1, diasDelMes);
    return finDeDia
        ? DateTime(year, month, diaSeguro, 23, 59, 59)
        : DateTime(year, month, diaSeguro);
  }

  bool _esCuentaCreditoPorNombre(String cuenta) {
    final lower = cuenta.toLowerCase();
    return lower.contains('credito') ||
        lower.contains('crédito') ||
        lower.contains('tc') ||
        lower.contains('visa') ||
        lower.contains('master');
  }

  DateTime _proximoVencimientoTarjeta(DateTime referencia, int dueDay) {
    final hoy = _inicioDelDia(referencia);
    final venceEsteMes = _fechaMesSegura(hoy.year, hoy.month, dueDay);
    if (!hoy.isAfter(venceEsteMes)) {
      return venceEsteMes;
    }
    return _fechaMesSegura(hoy.year, hoy.month + 1, dueDay);
  }

  /// Devuelve la fecha de corte efectiva para el mes actual.
  /// Si el usuario cerró el ciclo manualmente este mes, usa esa fecha.
  /// De lo contrario, usa el billingDay configurado.
  DateTime _getEffectiveCutoff(AppSettings settings, DateTime referenceDate) {
    final manualClose = settings.lastManualBillingClose;
    if (manualClose != null && manualClose.isNotEmpty) {
      final parsed = DateTime.tryParse(manualClose);
      if (parsed != null &&
          parsed.year == referenceDate.year &&
          parsed.month == referenceDate.month) {
        return _inicioDelDia(parsed);
      }
    }
    return _fechaMesSegura(
      referenceDate.year,
      referenceDate.month,
      settings.creditCardBillingDay,
    );
  }

  Map<String, DateTime> _obtenerRangosCicloCredito(
    AppSettings settings, {
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final billingDay = settings.creditCardBillingDay;
    final cutoffThisMonth = _getEffectiveCutoff(settings, now);

    late DateTime cycleStart;
    late DateTime cycleEnd;
    if (now.isAfter(cutoffThisMonth)) {
      cycleStart = _inicioDelDia(cutoffThisMonth.add(const Duration(days: 1)));
      cycleEnd = _fechaMesSegura(
        now.year,
        now.month + 1,
        billingDay,
        finDeDia: true,
      );
    } else {
      cycleEnd = _finDelDia(cutoffThisMonth);
      final previousCutoff = _fechaMesSegura(
        now.year,
        now.month - 1,
        billingDay,
      );
      cycleStart = _inicioDelDia(previousCutoff.add(const Duration(days: 1)));
    }

    return {
      'curStart': cycleStart,
      'curEnd': cycleEnd,
      'nowEnd': _finDelDia(now),
    };
  }

  Map<String, List<Map<String, dynamic>>> _agruparMovimientosCreditoPorCuenta(
    List<Map<String, dynamic>> movimientos,
  ) {
    final agrupado = <String, List<Map<String, dynamic>>>{};
    for (final mov in movimientos) {
      if ((mov['metodo_pago'] ?? 'Debito') != 'Credito') continue;
      final cuenta = (mov['cuenta'] ?? '').toString().trim();
      if (cuenta.isEmpty) continue;
      agrupado.putIfAbsent(cuenta, () => []).add(mov);
    }
    return agrupado;
  }

  Map<String, int> _calcularResumenDeudaCreditoCuenta({
    required List<Map<String, dynamic>> movimientosCuenta,
    required DateTime cycleStart,
    required DateTime nowEnd,
  }) {
    var gastosFacturadosBruto = 0;
    var gastosPorFacturarBruto = 0;
    var pagosAcumulados = 0;

    for (final mov in movimientosCuenta) {
      final fecha = DateTime.tryParse((mov['fecha'] ?? '').toString());
      if (fecha == null || fecha.isAfter(nowEnd)) continue;

      final monto = (mov['monto'] as num? ?? 0).toInt();
      final tipo = (mov['tipo'] ?? '').toString();
      if (tipo == 'Gasto') {
        if (fecha.isBefore(cycleStart)) {
          gastosFacturadosBruto += monto;
        } else {
          gastosPorFacturarBruto += monto;
        }
      } else if (tipo == 'Ingreso') {
        pagosAcumulados += monto;
      }
    }

    final pagoAFacturado = pagosAcumulados > gastosFacturadosBruto
        ? gastosFacturadosBruto
        : pagosAcumulados;
    final pagoRestante = pagosAcumulados - pagoAFacturado;
    final facturadoPendiente = gastosFacturadosBruto - pagoAFacturado;
    final porFacturarPendiente = (gastosPorFacturarBruto - pagoRestante).clamp(
      0,
      1 << 31,
    );
    final deudaTotal = (facturadoPendiente + porFacturarPendiente)
        .clamp(0, 1 << 31)
        .toInt();

    return {
      'facturadoPendiente': facturadoPendiente,
      'porFacturarPendiente': porFacturarPendiente.toInt(),
      'pagos': pagosAcumulados,
      'deudaTotal': deudaTotal,
    };
  }

  int _parseMonto(String value) {
    final onlyNumbers = value.replaceAll(RegExp(r'[^0-9-]'), '');
    return int.tryParse(onlyNumbers) ?? 0;
  }

  Stream<List<Map<String, dynamic>>> _streamMetasUsuario() {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return supabase
        .from('metas_ahorro')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
  }

  void _forzarRefrescoMetas() {
    if (!mounted) return;
    setState(() => _metasRefreshNonce++);
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
    HapticFeedback.lightImpact();
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
    HapticFeedback.lightImpact();
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
    _detalleController.clear();
    _montoController.clear();
    _categoriaSeleccionada = null;
    _cuentaController.text = widget.settingsController.settings.defaultAccount;
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _mostrarDetalleCategoria(
    BuildContext context,
    String categoria,
    List<Map<String, dynamic>> movimientosMes,
  ) {
    final gastos = movimientosMes.where((mov) {
      if (mov['tipo'] != 'Gasto') return false;
      return (mov['categoria'] ?? 'Varios').toString() == categoria;
    }).toList();

    gastos.sort((a, b) =>
        ((b['monto'] as num).abs()).compareTo((a['monto'] as num).abs()));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: _iconoCategoria(
                        categoria,
                        size: 26,
                        color: Colors.teal.shade400,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Detalle de categoría',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            categoria,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: gastos.isEmpty
                    ? Center(
                        child: Text(
                          'No hay gastos registrados en esta categoría.',
                          style: TextStyle(
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: gastos.length,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        separatorBuilder: (_, _) => Divider(
                          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                          indent: 72,
                          endIndent: 16,
                          height: 1,
                        ),
                        itemBuilder: (ctx, i) {
                          final mov = gastos[i];
                          final item = (mov['item'] ?? '').toString();
                          final cuenta = (mov['cuenta'] ?? '').toString();
                          final detalle = (mov['detalle'] ?? '').toString();
                          final monto = (mov['monto'] as num? ?? 0).toInt();
                          final fechaStr = (mov['fecha'] ?? '').toString();
                          final fecha = DateTime.tryParse(fechaStr) ?? DateTime.now();
                          
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                            onTap: () {
                              Navigator.pop(ctx);
                              _mostrarDialogo(itemParaEditar: mov);
                            },
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${fecha.day}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              item.isNotEmpty ? item : 'Gasto sin título',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cuenta.isNotEmpty ? cuenta : 'Efectivo',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                  ),
                                ),
                                if (detalle.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    detalle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Text(
                              _textoMonto(monto),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> calcularGastosPorCategoria(
    List<Map<String, dynamic>> movimientosDelMes,
  ) {
    final agrupado = <String, int>{};
    var total = 0;
    for (final mov in movimientosDelMes) {
      if (mov['tipo'] != 'Gasto' ||
          mov['categoria'] == 'Transferencia' ||
          mov['categoria'] == 'Ajuste' ||
          mov['categoria'] == 'Cuentas por Cobrar') {
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
      if (mov['categoria'] == 'Transferencia' ||
          mov['categoria'] == 'Ajuste' ||
          mov['categoria'] == 'Cuentas por Cobrar') {
        continue;
      }
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
    final excluidas = {'Créditos', 'Crédito Consumo'};
    final filtrado = desglose
        .where((d) => !excluidas.contains(d['categoria']))
        .toList();
    if (filtrado.isEmpty) {
      return {'categoria': 'Sin datos', 'monto': 0, 'porcentaje': 0.0};
    }
    return filtrado.first;
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
      final cat = (mov['categoria'] ?? '').toString();
      if (cat == 'Transferencia' ||
          cat == 'Ajuste' ||
          cat == 'Cuentas por Cobrar') {
        continue;
      }
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
      final cat = (mov['categoria'] ?? '').toString();
      if (cat == 'Transferencia' ||
          cat == 'Ajuste' ||
          cat == 'Cuentas por Cobrar') {
        continue;
      }
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

    // Alerta de vencimiento de tarjeta de crédito
    if (settings.enableCreditDueAlerts) {
      final dueDay = settings.creditCardDueDay;
      final daysBefore = settings.creditDueAlertDaysBefore;

      // Calcular la próxima fecha de vencimiento
      final nextDue = _proximoVencimientoTarjeta(ahora, dueDay);
      final diasRestantes = nextDue
          .difference(DateTime(ahora.year, ahora.month, ahora.day))
          .inDays;

      if (diasRestantes <= daysBefore && diasRestantes >= 0) {
        // Calcular monto facturado pendiente consolidado.
        final rangosCredito = _obtenerRangosCicloCredito(
          settings,
          referenceDate: ahora,
        );
        final curStart = rangosCredito['curStart']!;
        final nowEnd = rangosCredito['nowEnd']!;
        final movimientosCreditoPorCuenta = _agruparMovimientosCreditoPorCuenta(
          movimientos,
        );
        var facturado = 0;
        for (final movimientosCuenta in movimientosCreditoPorCuenta.values) {
          final resumen = _calcularResumenDeudaCreditoCuenta(
            movimientosCuenta: movimientosCuenta,
            cycleStart: curStart,
            nowEnd: nowEnd,
          );
          facturado += resumen['facturadoPendiente'] ?? 0;
        }

        final diasTexto = diasRestantes == 0
            ? 'Hoy vence'
            : diasRestantes == 1
            ? 'Vence mañana'
            : 'Vence en $diasRestantes días';
        alerts.add(
          FinanceAlert(
            id: 'credit_due_soon',
            title: '⚠️ $diasTexto tu tarjeta',
            message:
                'Monto facturado pendiente: ${_textoMonto(facturado, ocultable: false)}. Día de vencimiento: $dueDay.',
            icon: Icons.credit_score,
            color: diasRestantes <= 1
                ? Colors.red.shade700
                : Colors.orange.shade700,
          ),
        );
      }
    }
    // Alertas proactivas IA
    for (final aiAlert in _aiProactiveAlerts) {
      final alertColor = aiAlert.tipo == 'negativo'
          ? Colors.red.shade600
          : aiAlert.tipo == 'tip'
          ? Colors.teal.shade600
          : Colors.purple.shade600;
      final alertIcon = aiAlert.tipo == 'negativo'
          ? Icons.error_outline
          : aiAlert.tipo == 'tip'
          ? Icons.lightbulb_outline
          : Icons.auto_awesome;
      alerts.add(
        FinanceAlert(
          id: 'ai_alert_${aiAlert.titulo.hashCode}',
          title: aiAlert.titulo,
          message: aiAlert.mensaje,
          icon: alertIcon,
          color: alertColor,
          isAi: true,
        ),
      );
    }

    return alerts;
  }

  Widget _tarjetaAlerta(FinanceAlert alert) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? alert.color.withAlpha(0x26) : alert.color.withAlpha(24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: alert.color.withAlpha(isDark ? 0x4D : 0x1A)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: alert.color.withAlpha(0x33),
              shape: BoxShape.circle,
            ),
            child: Icon(alert.icon, color: alert.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        alert.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isDark
                              ? alert.color.withAlpha(0xE6)
                              : alert.color,
                        ),
                      ),
                    ),
                    if (alert.isAi)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.purple.shade900.withAlpha(80)
                              : Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 10,
                              color: isDark
                                  ? Colors.purpleAccent.shade100
                                  : Colors.purple.shade700,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'IA',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.purpleAccent.shade100
                                    : Colors.purple.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  alert.message,
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade300 : Colors.black87,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Alertas Proactivas IA ──

  static const String _aiAlertsLastCheckKey = 'ai_proactive_alerts_last_check';
  static const String _aiAlertsCacheKey = 'ai_proactive_alerts_cache';

  Future<void> _checkAndGenerateAiAlerts() async {
    if (_aiAlertsChecked) return;
    _aiAlertsChecked = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckMs = prefs.getInt(_aiAlertsLastCheckKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final twelveHours = 12 * 60 * 60 * 1000;

      // Intentar cargar cache primero
      final cachedJson = prefs.getString(_aiAlertsCacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final cached = jsonDecode(cachedJson) as List;
          if (mounted) {
            setState(() {
              _aiProactiveAlerts = cached
                  .map(
                    (e) => AiProactiveAlert.fromJson(e as Map<String, dynamic>),
                  )
                  .toList();
            });
          }
        } catch (_) {}
      }

      // Si pasaron menos de 12 horas, usar solo cache
      if (now - lastCheckMs < twelveHours) return;

      // Esperar a que el stream tenga datos
      final movimientos = await _stream.first;
      if (movimientos.isEmpty) {
        return;
      }

      // Preparar datos de últimos 7 días
      final datos = _prepararDatosAlertasIA(movimientos);
      if (datos.isEmpty) {
        return;
      }

      final alerts = await _aiService.generateProactiveAlerts(datos);

      // Guardar en cache y timestamp
      await prefs.setInt(_aiAlertsLastCheckKey, now);
      final alertsJson = jsonEncode(
        alerts
            .map(
              (a) => {'titulo': a.titulo, 'mensaje': a.mensaje, 'tipo': a.tipo},
            )
            .toList(),
      );
      await prefs.setString(_aiAlertsCacheKey, alertsJson);

      if (mounted) {
        setState(() {
          _aiProactiveAlerts = alerts;
        });
      }
    } catch (e) {
      debugPrint('Error AI proactive alerts: $e');
    }
  }

  Map<String, dynamic> _prepararDatosAlertasIA(
    List<Map<String, dynamic>> movimientos,
  ) {
    final settings = widget.settingsController.settings;
    final ahora = DateTime.now();
    final hace7Dias = ahora.subtract(const Duration(days: 7));
    final hace14Dias = ahora.subtract(const Duration(days: 14));

    // Últimos 7 días
    final recientes = movimientos.where((m) {
      final fecha = DateTime.parse(m['fecha']);
      final cat = (m['categoria'] ?? '').toString();
      return fecha.isAfter(hace7Dias) &&
          cat != 'Transferencia' &&
          cat != 'Ajuste' &&
          cat != 'Cuentas por Cobrar';
    }).toList();

    // Semana anterior (7-14 días atrás)
    final semanaAnterior = movimientos.where((m) {
      final fecha = DateTime.parse(m['fecha']);
      final cat = (m['categoria'] ?? '').toString();
      return fecha.isAfter(hace14Dias) &&
          fecha.isBefore(hace7Dias) &&
          cat != 'Transferencia' &&
          cat != 'Ajuste' &&
          cat != 'Cuentas por Cobrar';
    }).toList();

    if (recientes.isEmpty) return {};

    // Desglosar por categoría
    final gastosPorCategoria = <String, int>{};
    var totalGastos7d = 0;
    var totalIngresos7d = 0;
    final gastosPorDia = <String, int>{};

    for (final m in recientes) {
      final monto = (m['monto'] as num? ?? 0).toInt();
      final cat = (m['categoria'] ?? 'Varios').toString();
      final fecha = m['fecha'].toString().substring(0, 10);
      if (m['tipo'] == 'Gasto') {
        totalGastos7d += monto;
        gastosPorCategoria[cat] = (gastosPorCategoria[cat] ?? 0) + monto;
        gastosPorDia[fecha] = (gastosPorDia[fecha] ?? 0) + monto;
      } else {
        totalIngresos7d += monto;
      }
    }

    var totalGastosSemanaAnterior = 0;
    for (final m in semanaAnterior) {
      if (m['tipo'] == 'Gasto') {
        totalGastosSemanaAnterior += (m['monto'] as num? ?? 0).toInt();
      }
    }

    // Categorías ordenadas por monto
    final categoriasOrdenadas = gastosPorCategoria.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCategorias = categoriasOrdenadas
        .take(5)
        .map((e) => {'nombre': e.key, 'monto': e.value})
        .toList();

    return {
      'periodo': 'últimos 7 días',
      'total_gastos_7d': totalGastos7d,
      'total_ingresos_7d': totalIngresos7d,
      'total_gastos_semana_anterior': totalGastosSemanaAnterior,
      'gasto_diario_promedio': (totalGastos7d / 7).round(),
      'top_categorias': topCategorias,
      'gastos_por_dia': gastosPorDia,
      'moneda': settings.currencyCode,
      if (settings.globalMonthlyBudget != null)
        'presupuesto_mensual': settings.globalMonthlyBudget,
    };
  }

  // ── Resumen Semanal IA ──

  static const String _weeklySummaryLastDateKey = 'ai_weekly_summary_last_date';

  Future<void> _checkWeeklySummary() async {
    if (_weeklySummaryChecked) return;
    _weeklySummaryChecked = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastDateStr = prefs.getString(_weeklySummaryLastDateKey);
      final now = DateTime.now();

      if (lastDateStr != null) {
        final lastDate = DateTime.tryParse(lastDateStr);
        if (lastDate != null && now.difference(lastDate).inDays < 7) {
          return; // Aún no han pasado 7 días
        }
      }

      // Esperar a que el stream tenga datos
      final movimientos = await _stream.first;
      if (movimientos.isEmpty) return;

      final datosSemana = _prepararDatosResumenSemanal(movimientos);
      if (datosSemana.isEmpty) return;

      final summary = await _aiService.generateWeeklySummary(datosSemana);
      if (summary == null) return;

      // Guardar fecha
      await prefs.setString(_weeklySummaryLastDateKey, now.toIso8601String());

      // Mostrar bottom sheet
      if (mounted) {
        _mostrarResumenSemanal(summary, datosSemana);
      }
    } catch (e) {
      debugPrint('Error weekly summary: $e');
    }
  }

  Map<String, dynamic> _prepararDatosResumenSemanal(
    List<Map<String, dynamic>> movimientos,
  ) {
    final settings = widget.settingsController.settings;
    final ahora = DateTime.now();

    // Semana pasada: lunes a domingo
    final diaSemana = ahora.weekday; // 1=lunes
    final inicioSemanaActual = ahora.subtract(Duration(days: diaSemana - 1));
    final finSemanaPasada = DateTime(
      inicioSemanaActual.year,
      inicioSemanaActual.month,
      inicioSemanaActual.day,
    );
    final inicioSemanaPasada = finSemanaPasada.subtract(
      const Duration(days: 7),
    );
    final inicioSemanaAnterior = inicioSemanaPasada.subtract(
      const Duration(days: 7),
    );

    // Filtrar movimientos de la semana pasada
    var gastosSemana = 0;
    var ingresosSemana = 0;
    final gastosPorCategoria = <String, int>{};

    for (final m in movimientos) {
      final fecha = DateTime.parse(m['fecha']);
      final cat = (m['categoria'] ?? '').toString();
      if (cat == 'Transferencia' ||
          cat == 'Ajuste' ||
          cat == 'Cuentas por Cobrar') {
        continue;
      }
      if (fecha.isAfter(inicioSemanaPasada) &&
          fecha.isBefore(finSemanaPasada)) {
        final monto = (m['monto'] as num? ?? 0).toInt();
        if (m['tipo'] == 'Gasto') {
          gastosSemana += monto;
          gastosPorCategoria[cat] = (gastosPorCategoria[cat] ?? 0) + monto;
        } else {
          ingresosSemana += monto;
        }
      }
    }

    if (gastosSemana == 0 && ingresosSemana == 0) return {};

    // Semana anterior a la pasada
    var gastosSemanAnterior = 0;
    for (final m in movimientos) {
      final fecha = DateTime.parse(m['fecha']);
      final cat = (m['categoria'] ?? '').toString();
      if (cat == 'Transferencia' ||
          cat == 'Ajuste' ||
          cat == 'Cuentas por Cobrar') {
        continue;
      }
      if (fecha.isAfter(inicioSemanaAnterior) &&
          fecha.isBefore(inicioSemanaPasada)) {
        if (m['tipo'] == 'Gasto') {
          gastosSemanAnterior += (m['monto'] as num? ?? 0).toInt();
        }
      }
    }

    final categoriasOrdenadas = gastosPorCategoria.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'semana':
          '${inicioSemanaPasada.day}/${inicioSemanaPasada.month} - ${finSemanaPasada.subtract(const Duration(days: 1)).day}/${finSemanaPasada.subtract(const Duration(days: 1)).month}',
      'gastos_semana': gastosSemana,
      'ingresos_semana': ingresosSemana,
      'gastos_semana_anterior': gastosSemanAnterior,
      'categorias': categoriasOrdenadas
          .take(5)
          .map((e) => {'nombre': e.key, 'monto': e.value})
          .toList(),
      'moneda': settings.currencyCode,
    };
  }

  void _mostrarResumenSemanal(
    AiWeeklySummary summary,
    Map<String, dynamic> datos,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gastoSemana = (datos['gastos_semana'] as num? ?? 0).toInt();
    final gastoAnterior = (datos['gastos_semana_anterior'] as num? ?? 0)
        .toInt();
    final variacion = summary.variacionPorcentual;
    final subio = variacion > 0;
    final catTopNombre = (summary.categoriaTop['nombre'] ?? 'N/A').toString();
    final catTopMonto = (summary.categoriaTop['monto'] as num? ?? 0).toInt();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header con gradiente
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [Colors.purple.shade900, Colors.indigo.shade900]
                        : [Colors.purple.shade400, Colors.indigo.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(40),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Resumen Semanal IA',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      summary.resumen,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // KPIsRow
              Row(
                children: [
                  Expanded(
                    child: _weeklySummaryKpi(
                      label: 'Gastos semana',
                      value: formatoMoneda(gastoSemana),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _weeklySummaryKpi(
                      label: 'Semana anterior',
                      value: formatoMoneda(gastoAnterior),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _weeklySummaryKpi(
                      label: 'Variación',
                      value:
                          '${subio ? '+' : ''}${variacion.toStringAsFixed(1)}%',
                      isDark: isDark,
                      valueColor: subio
                          ? Colors.red.shade400
                          : Colors.green.shade400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Categoría top
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withAlpha(8)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      color: Colors.orange.shade400,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Top: $catTopNombre',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: isDark
                            ? Colors.grey.shade200
                            : Colors.grey.shade800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      formatoMoneda(catTopMonto),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.orange.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Recomendación
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.teal.shade900.withAlpha(50)
                      : Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.teal.shade700.withAlpha(60)
                        : Colors.teal.shade200,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: Colors.teal.shade400,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        summary.recomendacion,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: isDark
                              ? Colors.teal.shade200
                              : Colors.teal.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Botón cerrar
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Entendido'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _weeklySummaryKpi({
    required String label,
    required String value,
    required bool isDark,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color:
                  valueColor ??
                  (isDark ? Colors.grey.shade200 : Colors.grey.shade800),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffold = Scaffold(
      extendBody:
          true, // Allows body to scroll under the floating bottom app bar
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _titulosPestanas[_indicePestana],
            key: ValueKey<int>(_indicePestana),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        initialData: _cachedGastos,
        stream: _stream.map((datos) {
          try {
            widget.settingsController.preferences.setString('gastos_cache', jsonEncode(datos));
          } catch (_) {}
          return datos;
        }),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('Realtime Stream Error: ${snapshot.error}');
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.cloud_sync_rounded,
                        size: 36,
                        color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                      ),
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: isDark ? Colors.indigo.shade300 : Colors.indigo.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Sincronizando nube...',
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return _construirSkeletonPrincipal(isDark);
          }
          final todosLosDatos = snapshot.data!;

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: KeyedSubtree(
              key: ValueKey<int>(_indicePestana),
              child: () {
                final hasCreditCard =
                    widget.settingsController.settings.hasCreditCard;
                if (_indicePestana == 0) {
                  return _construirPaginaInicio(todosLosDatos);
                }
                if (_indicePestana == 1) {
                  return _construirPaginaAnalisis(todosLosDatos);
                }
                if (_indicePestana == 2) return _construirPaginaMetas();
                if (_indicePestana == 3) {
                  return _construirPaginaPresupuestos(todosLosDatos);
                }
                if (hasCreditCard) {
                  if (_indicePestana == 4) {
                    return _construirPaginaCredito(todosLosDatos);
                  }
                  if (_indicePestana == 5) {
                    return _construirPaginaMas(todosLosDatos);
                  }
                  return const SizedBox.shrink();
                } else {
                  if (_indicePestana == 4) {
                    return _construirPaginaMas(todosLosDatos);
                  }
                  return const SizedBox.shrink();
                }
              }(),
            ),
          );
        },
      ),
      floatingActionButton: !_bloqueada
          ? AnimatedScale(
              scale: 1.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.elasticOut,
              child: FloatingActionButton(
                heroTag: 'fab_agregar',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _mostrarDialogo();
                },
                child: const Icon(Icons.add),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: BottomAppBar(
            shape: const CircularNotchedRectangle(),
            notchMargin: 8.0,
            color: isDark
                ? const Color(0xFF1E293B).withAlpha(150)
                : Colors.white.withAlpha(200),
            elevation: 0,
            child: Row(
              children: <Widget>[
                // Lado izquierdo: 3 iconos
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _navIcon(
                        filled: Icons.home,
                        outlined: Icons.home_outlined,
                        index: 0,
                        tooltip: 'Inicio',
                      ),
                      _navIcon(
                        filled: Icons.pie_chart,
                        outlined: Icons.pie_chart_outline,
                        index: 1,
                        tooltip: 'Análisis',
                      ),
                      _navIcon(
                        filled: Icons.flag,
                        outlined: Icons.flag_outlined,
                        index: 2,
                        tooltip: 'Metas',
                      ),
                    ],
                  ),
                ),
                // Espacio central para el FAB
                const SizedBox(width: 72),
                // Lado derecho: 3 iconos
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _navIcon(
                        filled: Icons.calculate,
                        outlined: Icons.calculate_outlined,
                        index: 3,
                        tooltip: 'Presupuestos',
                      ),
                      if (widget.settingsController.settings.hasCreditCard)
                        _navIcon(
                          filled: Icons.calendar_month,
                          outlined: Icons.calendar_today_outlined,
                          index: 4,
                          tooltip: 'Planificación',
                        ),
                      _navIcon(
                        filled: Icons.menu,
                        outlined: Icons.menu_open,
                        index: widget.settingsController.settings.hasCreditCard
                            ? 5
                            : 4,
                        tooltip: 'Más',
                      ),
                    ],
                  ),
                ),
              ],
            ), // BottomAppBar child Row
          ), // BottomAppBar
        ), // BackdropFilter
      ), // ClipRRect
    ); // Scaffold

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

  Widget _bannerGastosARevisar(List<Map<String, dynamic>> gastos) {
    return Card(
      color: Colors.orange.shade50,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.shade300, width: 1.5),
      ),
      margin: EdgeInsets.symmetric(horizontal: widget.settingsController.settings.compactMode ? 12.0 : 16.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          _mostrarModalGastosARevisar(gastos);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pagos por revisar',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tienes ${gastos.length} movimiento(s) sin categorizar.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.orange.shade800),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarModalGastosARevisar(List<Map<String, dynamic>> gastos) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Text('Gastos a Revisar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: gastos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final gasto = gastos[index];
                    final date = DateTime.tryParse(gasto['fecha'] ?? '');
                    final dateStr = date != null ? DateFormat('dd MMM').format(date) : '';
                    final esIngreso = (gasto['tipo'] ?? 'Gasto') == 'Ingreso';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: esIngreso ? Colors.green.shade100 : Colors.orange.shade100,
                        child: Icon(
                          esIngreso ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          color: esIngreso ? Colors.green.shade800 : Colors.orange.shade800,
                        ),
                      ),
                      title: Text(gasto['item']?.toString() ?? 'Sin Detalles', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('$dateStr · ${esIngreso ? "Ingreso" : "Gasto"}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatoMoneda(gasto['monto'] ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              final id = gasto['id'];
                              if (id != null) {
                                await supabase.from('gastos').delete().eq('id', id);
                                if (context.mounted) Navigator.pop(context); // Cerrar hoja modal para refrescar
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context); // Cerrar hoja modal
                        _mostrarDialogo(itemParaEditar: gasto); // Abrir editor de gasto
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _construirPaginaInicio(List<Map<String, dynamic>> todosLosDatos) {
    final settings = widget.settingsController.settings;
    final compacto = settings.compactMode;
    final margin = compacto ? 12.0 : 16.0;
    final padding = compacto ? 12.0 : 16.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filtrar por cuentas seleccionadas
    final datosFiltrados = todosLosDatos.where((mov) {
      final cuenta = (mov['cuenta'] ?? '').toString();
      return _cuentasSeleccionadas.contains(cuenta);
    }).toList();

    // 4. Calcular Saldo de Cuenta Corriente (Liquidez total - Solo Débito/Efectivo)
    // Se calcula explícitamente para asegurar que EXCLUYE Crédito y EXCLUYE Fantasmas
    var saldoCuentaCorriente = 0;
    var saldoProyectado = 0;
    DateTime? ultimoFantasmaFecha;
    for (final mov in datosFiltrados) {
      // Ignorar transacciones de Crédito
      if ((mov['metodo_pago'] ?? 'Debito') == 'Credito') continue;
      final esFantasmaMov = (mov['estado'] ?? 'real') == 'fantasma';
      final m = (mov['monto'] as num? ?? 0).toInt();

      if (!esFantasmaMov) {
        // Solo movimientos reales afectan el saldo corriente
        if (mov['tipo'] == 'Ingreso') {
          saldoCuentaCorriente += m;
        } else {
          saldoCuentaCorriente -= m;
        }
      } else {
        // Rastrear fecha del último fantasma
        final fechaFant = DateTime.tryParse(mov['fecha'] ?? '');
        if (fechaFant != null) {
          if (ultimoFantasmaFecha == null ||
              fechaFant.isAfter(ultimoFantasmaFecha)) {
            ultimoFantasmaFecha = fechaFant;
          }
        }
      }
    }
    // Saldo proyectado = saldo real + todos los fantasmas
    saldoProyectado = saldoCuentaCorriente;
    for (final mov in datosFiltrados) {
      if ((mov['metodo_pago'] ?? 'Debito') == 'Credito') continue;
      if ((mov['estado'] ?? 'real') != 'fantasma') continue;
      final m = (mov['monto'] as num? ?? 0).toInt();
      if (mov['tipo'] == 'Ingreso') {
        saldoProyectado += m;
      } else {
        saldoProyectado -= m;
      }
    }
    final hayFantasmas = ultimoFantasmaFecha != null;

    final datosDelMes = datosFiltrados.where((mov) {
      final fechaMov = DateTime.parse(mov['fecha']);
      return fechaMov.year == _mesVisualizado.year &&
          fechaMov.month == _mesVisualizado.month;
    }).toList();

    // Para análisis y gráficos: excluye fantasmas
    final datosDelMesSoloReales = datosDelMes
        .where((mov) => (mov['estado'] ?? 'real') != 'fantasma')
        .toList();

    var ingresoMes = 0;
    var gastoMes = 0;
    for (final mov in datosDelMesSoloReales) {
      final cat = (mov['categoria'] ?? '').toString();
      if (cat == 'Transferencia' ||
          cat == 'Ajuste' ||
          cat == 'Cuentas por Cobrar') {
        continue;
      }
      final monto = (mov['monto'] as num? ?? 0).toInt();
      if (mov['tipo'] == 'Ingreso') {
        ingresoMes += monto;
      } else {
        gastoMes += monto;
      }
    }
    final totalNetoMes = ingresoMes - gastoMes;
    final desgloseCategorias = calcularGastosPorCategoria(
      datosDelMesSoloReales,
    );

    // 5. TC Utilizado total pendiente (considera todo el histórico).
    final rangosCredito = _obtenerRangosCicloCredito(settings);
    final curStart = rangosCredito['curStart']!;
    final nowEnd = rangosCredito['nowEnd']!;
    final movimientosCreditoPorCuenta = _agruparMovimientosCreditoPorCuenta(
      datosFiltrados,
    );

    var saldoCreditoUtilizado = 0;
    for (final movimientosCuenta in movimientosCreditoPorCuenta.values) {
      final resumen = _calcularResumenDeudaCreditoCuenta(
        movimientosCuenta: movimientosCuenta,
        cycleStart: curStart,
        nowEnd: nowEnd,
      );
      saldoCreditoUtilizado += resumen['deudaTotal'] ?? 0;
    }

    // Apply search & sort
    final query = _textoBusqueda.toLowerCase();
    final movimientosFiltrados = datosDelMes.where((mov) {
      // Type filter
      if (_filtroTipo != 'Todos' && mov['tipo'] != _filtroTipo) return false;
      // Text search
      if (query.isEmpty) return true;
      final item = (mov['item'] ?? '').toString().toLowerCase();
      final cat = (mov['categoria'] ?? '').toString().toLowerCase();
      final cuenta = (mov['cuenta'] ?? '').toString().toLowerCase();
      return item.contains(query) ||
          cat.contains(query) ||
          cuenta.contains(query);
    }).toList();

    // Apply sort
    switch (_ordenamiento) {
      case 'fecha_asc':
        movimientosFiltrados.sort(
          (a, b) => (a['fecha'] as String).compareTo(b['fecha'] as String),
        );
      case 'monto_desc':
        movimientosFiltrados.sort(
          (a, b) =>
              ((b['monto'] as num).abs()).compareTo((a['monto'] as num).abs()),
        );
      case 'monto_asc':
        movimientosFiltrados.sort(
          (a, b) =>
              ((a['monto'] as num).abs()).compareTo((b['monto'] as num).abs()),
        );
      default: // fecha_desc
        movimientosFiltrados.sort(
          (a, b) => (b['fecha'] as String).compareTo(a['fecha'] as String),
        );
    }

    final totalFiltrados = movimientosFiltrados.length;
    final int itemCount = _limiteMovimientos == null
        ? totalFiltrados
        : (totalFiltrados > _limiteMovimientos!
              ? _limiteMovimientos!
              : totalFiltrados);

    final gastosARevisar = todosLosDatos.where((mov) {
      final cat = (mov['categoria'] ?? '').toString();
      final noBorrado = (mov['estado'] ?? 'real') != 'eliminado';
      return cat == 'A revisar' && noBorrado;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              _selectorCuentas(),
              const SizedBox(height: 12),
              if (gastosARevisar.isNotEmpty) ...[
                _bannerGastosARevisar(gastosARevisar),
                const SizedBox(height: 12),
              ],
              // ── Tarjeta Liquidez Neta ──
              Builder(
                builder: (context) {
                  final saldoNeto =
                      saldoCuentaCorriente - saldoCreditoUtilizado;
                  final totalBarra =
                      saldoCuentaCorriente + saldoCreditoUtilizado;
                  final double fraccionCuenta = totalBarra == 0
                      ? 0.5
                      : saldoCuentaCorriente / totalBarra;
                  final double fraccionCredito = 1.0 - fraccionCuenta;
                  final bool esNegativo = saldoNeto < 0;

                  final Color colorNeto = esNegativo
                      ? (isDark
                            ? Colors.redAccent.shade100
                            : Colors.red.shade700)
                      : (isDark
                            ? Colors.tealAccent.shade400
                            : Colors.teal.shade700);

                  return Container(
                    margin: EdgeInsets.symmetric(horizontal: margin),
                    padding: EdgeInsets.all(padding),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(isDark ? 60 : 18),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // ── Título ──
                        Text(
                          'Liquidez Neta',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // ── Monto Neto ──
                        Text(
                          _textoMonto(saldoNeto),
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            color: colorNeto,
                            height: 1.1,
                          ),
                        ),
                        // ── Saldo Proyectado (visible solo si hay fantasmas) ──
                        if (hayFantasmas) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.purple.shade900.withAlpha(80)
                                  : Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark
                                    ? Colors.purple.shade700.withAlpha(100)
                                    : Colors.purple.shade200,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 12,
                                  color: isDark
                                      ? Colors.purpleAccent.shade100
                                      : Colors.purple.shade700,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Proyectado al ${ultimoFantasmaFecha!.day}/${ultimoFantasmaFecha.month}: ${formatoMoneda(saldoProyectado - saldoCreditoUtilizado)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.purpleAccent.shade100
                                        : Colors.purple.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        // ── Barra de Composición ──
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            height: 10,
                            child: Row(
                              children: [
                                Flexible(
                                  flex: (fraccionCuenta * 1000).round().clamp(
                                    1,
                                    999,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isDark
                                            ? [
                                                Colors.tealAccent.shade700,
                                                Colors.tealAccent.shade400,
                                              ]
                                            : [
                                                Colors.teal.shade600,
                                                Colors.teal.shade400,
                                              ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Flexible(
                                  flex: (fraccionCredito * 1000).round().clamp(
                                    1,
                                    999,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isDark
                                            ? [
                                                Colors.redAccent.shade100,
                                                Colors.red.shade300,
                                              ]
                                            : [
                                                Colors.red.shade300,
                                                Colors.red.shade400,
                                              ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // ── Desglose Inferior ──
                        Row(
                          children: [
                            // Cuenta Corriente
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color:
                                          (isDark
                                                  ? Colors.tealAccent.shade700
                                                  : Colors.teal.shade600)
                                              .withAlpha(30),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.account_balance,
                                      size: 18,
                                      color: isDark
                                          ? Colors.tealAccent.shade400
                                          : Colors.teal.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Cta. Corriente',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Colors.grey.shade400
                                                : Colors.grey.shade600,
                                          ),
                                        ),
                                        Text(
                                          _textoMonto(saldoCuentaCorriente),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? Colors.tealAccent.shade400
                                                : Colors.teal.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (settings.hasCreditCard) ...[
                              // Separador vertical
                              Container(
                                height: 32,
                                width: 1,
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                              // TC Utilizado
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'TC Utilizado',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.grey.shade400
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                          Text(
                                            saldoCreditoUtilizado == 0
                                                ? _textoMonto(0)
                                                : '- ${_textoMonto(saldoCreditoUtilizado)}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.redAccent.shade100
                                                  : Colors.red.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color:
                                            (isDark
                                                    ? Colors.redAccent.shade100
                                                    : Colors.red.shade400)
                                                .withAlpha(30),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.credit_card,
                                        size: 18,
                                        color: isDark
                                            ? Colors.redAccent.shade100
                                            : Colors.red.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Container(
                margin: EdgeInsets.symmetric(horizontal: margin),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2433) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
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
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 50 : 12),
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
                      color: Theme.of(context).dividerColor,
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
                      color: Theme.of(context).dividerColor,
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Gastos por Categoria',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).highlightColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _toggleBoton(
                              icono: Icons.attach_money,
                              activo: !_mostrarPorcentaje,
                              onTap: () =>
                                  setState(() => _mostrarPorcentaje = false),
                            ),
                            _toggleBoton(
                              icono: Icons.percent,
                              activo: _mostrarPorcentaje,
                              onTap: () =>
                                  setState(() => _mostrarPorcentaje = true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: margin, vertical: 8),
                  padding: EdgeInsets.all(padding),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: desgloseCategorias.map((catData) {
                      return InkWell(
                        onTap: () => _mostrarDetalleCategoria(
                          context,
                          catData['categoria'] as String,
                          datosDelMesSoloReales,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12, top: 4, left: 4, right: 4),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                Row(
                                  children: [
                                    _iconoCategoria(
                                      catData['categoria'] as String,
                                      size: 18,
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade700,
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
                                  _mostrarPorcentaje
                                      ? '${((catData['porcentaje'] as double) * 100).toStringAsFixed(1)}%'
                                      : _textoMonto(catData['monto'] as int),
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
                                backgroundColor: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade100,
                                color: Colors.teal.shade300,
                                minHeight: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  ),
                ),
              ],
              // ── Search & Sort Bar ──
              Padding(
                padding: EdgeInsets.fromLTRB(margin, 8, margin, 0),
                child: TextField(
                  controller: _busquedaController,
                  decoration: InputDecoration(
                    hintText: 'Buscar movimiento...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _busquedaController.clear();
                            setState(() {
                              _textoBusqueda = '';
                              _limiteMovimientos = 15;
                            });
                          },
                        ),
                        IconButton(
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              _ordenamientoVisible
                                  ? Icons.sort
                                  : Icons.sort_outlined,
                              key: ValueKey(_ordenamientoVisible),
                              size: 20,
                            ),
                          ),
                          onPressed: () => setState(
                            () => _ordenamientoVisible = !_ordenamientoVisible,
                          ),
                          tooltip: 'Ordenar',
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (v) => setState(() {
                    _textoBusqueda = v;
                    _limiteMovimientos = 15;
                  }),
                ),
              ),
              // ── Type Filter ──
              Padding(
                padding: EdgeInsets.fromLTRB(margin, 10, margin, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'Todos',
                        label: Text('Todos', style: TextStyle(fontSize: 13)),
                        icon: Icon(Icons.list, size: 16),
                      ),
                      ButtonSegment(
                        value: 'Gasto',
                        label: Text('Gastos', style: TextStyle(fontSize: 13)),
                        icon: Icon(Icons.arrow_downward, size: 16),
                      ),
                      ButtonSegment(
                        value: 'Ingreso',
                        label: Text('Ingresos', style: TextStyle(fontSize: 13)),
                        icon: Icon(Icons.arrow_upward, size: 16),
                      ),
                    ],
                    selected: {_filtroTipo},
                    onSelectionChanged: (sel) => setState(() {
                      _filtroTipo = sel.first;
                      _limiteMovimientos = 15;
                    }),
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // ── Sort Chips ──
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: EdgeInsets.fromLTRB(margin, 10, margin, 0),
                  child: Row(
                    children: [
                      _chipOrden(
                        label: 'Fecha',
                        icono: Icons.arrow_downward,
                        valor: 'fecha_desc',
                        descripcion: 'Más reciente',
                      ),
                      const SizedBox(width: 6),
                      _chipOrden(
                        label: 'Fecha',
                        icono: Icons.arrow_upward,
                        valor: 'fecha_asc',
                        descripcion: 'Más antiguo',
                      ),
                      const SizedBox(width: 6),
                      _chipOrden(
                        label: 'Monto',
                        icono: Icons.arrow_downward,
                        valor: 'monto_desc',
                        descripcion: 'Mayor',
                      ),
                      const SizedBox(width: 6),
                      _chipOrden(
                        label: 'Monto',
                        icono: Icons.arrow_upward,
                        valor: 'monto_asc',
                        descripcion: 'Menor',
                      ),
                    ],
                  ),
                ),
                crossFadeState: _ordenamientoVisible
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 250),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Movimientos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (movimientosFiltrados.length != datosDelMes.length)
                      Text(
                        '${movimientosFiltrados.length} de ${datosDelMes.length}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (movimientosFiltrados.isEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      _textoBusqueda.isNotEmpty
                          ? Icons.search_off
                          : Icons.inbox_outlined,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _textoBusqueda.isNotEmpty
                          ? 'Sin resultados para "$_textoBusqueda"'
                          : 'Sin movimientos',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                    if (_textoBusqueda.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton(
                          onPressed: () {
                            _busquedaController.clear();
                            setState(() {
                              _textoBusqueda = '';
                              _limiteMovimientos = 15;
                            });
                          },
                          child: const Text('Limpiar búsqueda'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = movimientosFiltrados[index];
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(
                  milliseconds: 350 + (index.clamp(0, 8) * 50),
                ),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: _tarjetaTransaccion(
                  item: item,
                  margin: margin,
                  isDark: isDark,
                ),
              );
            }, childCount: itemCount),
          ),
        if (_limiteMovimientos != null && totalFiltrados > _limiteMovimientos!)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: FilledButton.tonalIcon(
                  onPressed: () => setState(() => _limiteMovimientos = null),
                  icon: const Icon(Icons.expand_more),
                  label: Text('Ver más ($totalFiltrados)'),
                ),
              ),
            ),
          ),
        if (_limiteMovimientos == null && totalFiltrados > 15)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _limiteMovimientos = 15),
                  icon: const Icon(Icons.expand_less),
                  label: const Text('Ver menos'),
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }

  Widget _tarjetaTransaccion({
    required Map<String, dynamic> item,
    required double margin,
    required bool isDark,
  }) {
    final esIngreso = item['tipo'] == 'Ingreso';
    final categoria = (item['categoria'] ?? 'Varios').toString();
    final fechaItem = DateTime.parse(item['fecha']);
    final colorBase = esIngreso ? Colors.teal : Colors.red;
    final esFantasma = (item['estado'] ?? 'real') == 'fantasma';

    Widget card = InkWell(
      onTap: () => _mostrarDialogo(itemParaEditar: item),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: esFantasma
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 30 : 8),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Hero(
              tag: 'mov_${item['id']}',
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: esFantasma
                      ? Colors.grey.withAlpha(isDark ? 40 : 25)
                      : colorBase.withAlpha(isDark ? 40 : 25),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: esIngreso
                      ? Icon(
                          Icons.add_chart_rounded,
                          color: esFantasma
                              ? (isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade500)
                              : (isDark
                                    ? Colors.tealAccent.shade400
                                    : Colors.teal.shade700),
                          size: 24,
                        )
                      : _iconoCategoria(
                          categoria,
                          color: esFantasma
                              ? (isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade500)
                              : (isDark
                                    ? Colors.redAccent.shade100
                                    : Colors.red.shade700),
                          size: 24,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          (item['item'] ?? 'Sin nombre').toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (esFantasma) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.purple.shade900.withAlpha(100)
                                : Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isDark
                                  ? Colors.purple.shade700.withAlpha(120)
                                  : Colors.purple.shade200,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'PROYECTADO',
                            style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: isDark
                                  ? Colors.purpleAccent.shade100
                                  : Colors.purple.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${fechaItem.day} ${obtenerNombreMes(fechaItem.month).substring(0, 3)} · ${(item['cuenta'] ?? '-').toString()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _textoMonto(item['monto'] as num),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: esFantasma
                        ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
                        : (esIngreso
                              ? (isDark
                                    ? Colors.tealAccent.shade400
                                    : Colors.teal.shade700)
                              : (isDark
                                    ? Colors.redAccent.shade100
                                    : Colors.red.shade700)),
                  ),
                ),
                if ((item['metodo_pago'] ?? 'Debito') == 'Credito')
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.orangeAccent.withAlpha(40)
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CREDITO',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? Colors.orangeAccent
                            : Colors.orange.shade800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (esFantasma) {
      card = RepaintBoundary(
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: isDark
                ? Colors.purple.shade700.withAlpha(160)
                : Colors.purple.shade300,
            borderRadius: 16,
            dashWidth: 6,
            dashSpace: 4,
            strokeWidth: 1.2,
          ),
          child: card,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin, vertical: 6),
      child: Opacity(
        opacity: esFantasma ? 0.72 : 1.0,
        child: Dismissible(
          key: Key('dismiss_${item['id']}'),
          direction: esFantasma
              ? DismissDirection.horizontal
              : DismissDirection.endToStart,
          secondaryBackground: Container(
            decoration: BoxDecoration(
              color: Colors.red.shade400,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          background: esFantasma
              ? Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.teal.shade500],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Confirmar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd && esFantasma) {
              await supabase
                  .from('gastos')
                  .update({'estado': 'real'})
                  .eq('id', item['id']);
              if (mounted) _mostrarSnack('Movimiento confirmado âœ“');
              return false;
            }
            return true;
          },
          onDismissed: (_) async {
            await supabase.from('gastos').delete().eq('id', item['id']);
          },
          child: card,
        ),
      ),
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

  Widget _construirSeccionAlertas(List<FinanceAlert> alertas) {
    if (alertas.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2433) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 0x4D : 0x0C),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: isDark ? Border.all(color: Colors.grey.shade800) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () =>
                setState(() => _alertasExpandidas = !_alertasExpandidas),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(16),
              bottom: Radius.circular(_alertasExpandidas ? 0 : 16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.orange.withAlpha(0x33)
                          : Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_active_outlined,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${alertas.length} Alertas detectadas',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.grey.shade200
                          : Colors.grey.shade800,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _alertasExpandidas
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Body Collapsible (Carousel)
          AnimatedCrossFade(
            firstChild: Container(
              height: 140, // Altura fija para el carrusel
              margin: const EdgeInsets.only(bottom: 16),
              child: PageView.builder(
                controller: PageController(viewportFraction: 0.92),
                padEnds: false,
                itemCount: alertas.length,
                itemBuilder: (context, index) {
                  final alert = alertas[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _tarjetaAlerta(alert),
                  );
                },
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
            crossFadeState: _alertasExpandidas
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _construirPaginaAnalisis(List<Map<String, dynamic>> todosLosDatos) {
    // StreamBuilder removed
    final settings = widget.settingsController.settings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

    // Calcular Dinero Libre Hoy solo si es el mes actual
    Widget? tarjetaSupervivencia;
    if (esMesActual) {
      final datosFiltradosSupervivencia = todosLosDatos.where((mov) {
        final cuenta = (mov['cuenta'] ?? '').toString();
        return _cuentasSeleccionadas.contains(cuenta);
      }).toList();

      var saldoDebito = 0;
      var deudaCredito = 0;
      for (final mov in datosFiltradosSupervivencia) {
        final m = (mov['monto'] as num? ?? 0).toInt();
        if ((mov['metodo_pago'] ?? 'Debito') == 'Credito') {
          if (mov['tipo'] == 'Gasto') {
            deudaCredito += m;
          } else {
            deudaCredito -= m;
          }
        } else {
          if (mov['tipo'] == 'Ingreso') {
            saldoDebito += m;
          } else {
            saldoDebito -= m;
          }
        }
      }

      final dineroLibreHoy = saldoDebito - deudaCredito;
      final diasRestantes = diasDelMes - hoy.day + 1; // +1 to include today
      final presupuestoDiarioSugerido = diasRestantes > 0
          ? (dineroLibreHoy / diasRestantes).round()
          : 0;

      tarjetaSupervivencia = Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1E3C72), const Color(0xFF2A5298)]
                : [Colors.blue.shade50, Colors.blue.shade100.withAlpha(150)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.blue.shade700.withAlpha(100)
                : Colors.blue.shade300,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : Colors.blue.shade200).withAlpha(
                100,
              ),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: isDark ? Colors.blueAccent : Colors.blue.shade700,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Dinero Libre Hoy',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.blue.shade100 : Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _textoMonto(dineroLibreHoy),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.blue.shade900,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withAlpha(150),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Presupuesto Sugerido',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '${_textoMonto(presupuestoDiarioSugerido)} / día',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.greenAccent.shade400
                              : Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Restante',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '$diasRestantes días',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              // Explicacion sutil
              '(Calculado como Cuentas Débito - Pagos pendientes Tarjeta)',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.blue.shade200 : Colors.blue.shade800,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Seccion de Alertas (Carousel)
          _construirSeccionAlertas(alertas),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2433) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              ),
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
          // Widget Por Cobrar
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _porCobrarStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }
              final data = snapshot.data!;
              final total = data.fold<int>(
                0,
                (sum, item) => sum + (item['monto'] as num).toInt(),
              );
              if (total == 0) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.shade900.withAlpha(50)
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.people_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Por Cobrar (Amigos)',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.orange.shade200
                                  : Colors.orange.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Te deben un total de ${_textoMonto(total)}',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.orange.shade100
                                  : Colors.orange.shade800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          ?tarjetaSupervivencia,
          // ── Sección Análisis IA ──
          _construirSeccionIA(
            todosLosDatos: todosLosDatos,
            datosDelMes: datosDelMes,
            resumenMes: resumenMes,
            serieFlujo: serieFlujo,
            settings: settings,
            isDark: isDark,
            diasTranscurridos: diasTranscurridos,
            diasDelMes: diasDelMes,
            tasaAhorro: tasaAhorro,
            gastoDiarioPromedio: gastoDiarioPromedio,
            categoriaTop: categoriaTop,
          ),
          const SizedBox(height: 16),
          Text(
            'Rendimiento del Mes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          _tarjetaAnalisis(
            titulo: 'Flujo de caja del mes',
            valor: _textoMonto(flujoMes),
            descripcion:
                'Ingresos ${_textoMonto(ingresoMes)} | Gastos ${_textoMonto(gastoMes)}',
            icono: Icons.waterfall_chart,
            color: flujoMes >= 0
                ? (isDark ? Colors.tealAccent : Colors.teal)
                : (isDark ? Colors.redAccent : Colors.red),
          ),
          const SizedBox(height: 12),
          _tarjetaAnalisis(
            titulo: 'Tasa de ahorro',
            valor: '${(tasaAhorro * 100).toStringAsFixed(1)}%',
            descripcion: ingresoMes > 0
                ? 'Porcentaje de ingreso que queda como ahorro'
                : 'Sin ingresos para calcular tasa',
            icono: Icons.savings_outlined,
            color: tasaAhorro >= 0
                ? (isDark ? Colors.greenAccent : Colors.green)
                : (isDark ? Colors.redAccent : Colors.red),
          ),
          const SizedBox(height: 12),
          _tarjetaAnalisis(
            titulo: 'Proyeccion de cierre',
            valor: _textoMonto(proyeccionFlujo),
            descripcion: 'Proyeccion mensual basada en promedio diario actual',
            icono: Icons.trending_up,
            color: proyeccionFlujo >= 0
                ? (isDark ? Colors.tealAccent : Colors.teal)
                : (isDark ? Colors.redAccent : Colors.red),
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
          // ── Presupuesto diario disponible ──
          Builder(
            builder: (_) {
              final diasRestantes = esMesActual
                  ? (diasDelMes - hoy.day + 1) // incluye hoy
                  : diasDelMes;
              final flujoRestante = ingresoMes - gastoMes;
              final presupuestoDiario = diasRestantes > 0
                  ? (flujoRestante / diasRestantes).round()
                  : flujoRestante;
              final colorPresupuesto = presupuestoDiario > 0
                  ? (isDark ? Colors.cyanAccent : Colors.cyan.shade700)
                  : presupuestoDiario == 0
                  ? Colors.orange
                  : (isDark ? Colors.redAccent : Colors.red);
              final descripcionDiario = esMesActual
                  ? '$diasRestantes dia(s) restantes · Disponible ${_textoMonto(flujoRestante)}'
                  : 'Resultado final del mes';
              return _tarjetaAnalisis(
                titulo: 'Presupuesto diario disponible',
                valor: _textoMonto(presupuestoDiario),
                descripcion: descripcionDiario,
                icono: Icons.today_outlined,
                color: colorPresupuesto,
              );
            },
          ),
          const SizedBox(height: 12),
          _tarjetaAnalisis(
            titulo: 'Categoria con mayor gasto',
            valor: nombreCategoriaTop,
            descripcion:
                '${_textoMonto(montoCategoriaTop)} (${(porcentajeCategoriaTop * 100).toStringAsFixed(1)}% del gasto)',
            icono: Icons.label_important_outline,
            color: isDark ? Colors.indigoAccent : Colors.indigo,
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
                  ? (isDark ? Colors.greenAccent : Colors.green)
                  : consumoPresupuesto < 1
                  ? Colors.orange
                  : (isDark ? Colors.redAccent : Colors.red),
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
                  ? (isDark ? Colors.greenAccent : Colors.green)
                  : Colors.orange,
            ),
          ],
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 50 : 10),
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
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: serieFlujo.map((punto) {
                      final flujo = punto['flujo'] as int;
                      final ingresos = punto['ingresos'] as int;
                      final gastos = punto['ingresos'] as int;
                      final mes = punto['mes'] as DateTime;
                      final altura = ((flujo.abs() / maxAbsFlujo) * 70) + 8;
                      final color = flujo >= 0
                          ? Colors.green.shade400
                          : Colors.red.shade400;
                      final esSeleccionado =
                          mes.year == _mesVisualizado.year &&
                          mes.month == _mesVisualizado.month;

                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;

                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              builder: (_) => Container(
                                margin: const EdgeInsets.all(16),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.bar_chart,
                                          color: color,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${obtenerNombreMes(mes.month)} ${mes.year}',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 24),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _filaDetalleBarra(
                                            'Ingresos',
                                            ingresos,
                                            Colors.green.shade600,
                                            Icons.arrow_upward,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _filaDetalleBarra(
                                            'Gastos',
                                            gastos,
                                            Colors.red.shade600,
                                            Icons.arrow_downward,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _filaDetalleBarra(
                                            'Flujo neto',
                                            flujo,
                                            flujo >= 0
                                                ? Colors.teal
                                                : Colors.red.shade700,
                                            Icons.waterfall_chart,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          setState(() {
                                            _mesVisualizado = DateTime(
                                              mes.year,
                                              mes.month,
                                            );
                                          });
                                        },
                                        icon: const Icon(
                                          Icons.calendar_month,
                                          size: 18,
                                        ),
                                        label: const Text('Ver este mes'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: esSeleccionado ? 22 : 16,
                                height: altura,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(8),
                                  border: esSeleccionado
                                      ? Border.all(
                                          color: isDark
                                              ? Colors.white30
                                              : Colors.black26,
                                          width: 2,
                                        )
                                      : null,
                                  boxShadow: esSeleccionado
                                      ? [
                                          BoxShadow(
                                            color: color.withAlpha(80),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _mesCorto(mes),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: esSeleccionado
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: esSeleccionado
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : (isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade700),
                                ),
                              ),
                            ],
                          ),
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

  // ═══════════════════════════════════════════════════════
  //  ANÁLISIS IA
  // ═══════════════════════════════════════════════════════

  Future<void> _requestAiAnalysis({
    required List<Map<String, dynamic>> todosLosDatos,
    required List<Map<String, dynamic>> datosDelMes,
    required Map<String, int> resumenMes,
    required List<Map<String, dynamic>> serieFlujo,
    required AppSettings settings,
    required int diasTranscurridos,
    required int diasDelMes,
    required double tasaAhorro,
    required double gastoDiarioPromedio,
    required Map<String, dynamic> categoriaTop,
  }) async {
    if (_aiLoading) return;
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });

    try {
      // Construir categorías desglosadas
      final categorias = calcularGastosPorCategoria(datosDelMes);
      final categoriasResumen = categorias
          .map(
            (c) => {
              'nombre': c['categoria'],
              'monto': c['monto'],
              'porcentaje': ((c['porcentaje'] as double) * 100).toStringAsFixed(
                1,
              ),
            },
          )
          .toList();

      // Construir tendencia de 6 meses
      final tendencia = serieFlujo.map((p) {
        final mes = p['mes'] as DateTime;
        return {
          'mes': '${obtenerNombreMes(mes.month)} ${mes.year}',
          'ingresos': p['ingresos'],
          'gastos': p['gastos'],
          'flujo': p['flujo'],
        };
      }).toList();

      final resumen = {
        'mes':
            '${obtenerNombreMes(_mesVisualizado.month)} ${_mesVisualizado.year}',
        'ingresos': resumenMes['ingresos'] ?? 0,
        'gastos': resumenMes['gastos'] ?? 0,
        'flujo': resumenMes['flujo'] ?? 0,
        'tasa_ahorro': double.parse((tasaAhorro * 100).toStringAsFixed(1)),
        'gasto_diario_promedio': gastoDiarioPromedio.round(),
        'dias_transcurridos': diasTranscurridos,
        'dias_del_mes': diasDelMes,
        'categoria_top': {
          'nombre': categoriaTop['categoria'],
          'monto': categoriaTop['monto'],
          'porcentaje': ((categoriaTop['porcentaje'] as double) * 100)
              .toStringAsFixed(1),
        },
        'categorias': categoriasResumen,
        'tendencia_6_meses': tendencia,
        'moneda': settings.currencyCode,
        if (settings.globalMonthlyBudget != null)
          'presupuesto_global': settings.globalMonthlyBudget,
      };

      final result = await _aiService.analyzeFinances(resumen);
      if (mounted) {
        setState(() {
          _aiResult = result;
          _aiLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiError = e.toString();
          _aiLoading = false;
        });
      }
    }
  }

  IconData _insightIcon(String tipo) {
    switch (tipo) {
      case 'positivo':
        return Icons.trending_up_rounded;
      case 'negativo':
        return Icons.trending_down_rounded;
      case 'alerta':
        return Icons.warning_amber_rounded;
      default:
        return Icons.lightbulb_outline;
    }
  }

  Color _insightColor(String tipo, bool isDark) {
    switch (tipo) {
      case 'positivo':
        return isDark ? Colors.greenAccent.shade400 : Colors.green.shade700;
      case 'negativo':
        return isDark ? Colors.redAccent.shade100 : Colors.red.shade700;
      case 'alerta':
        return isDark ? Colors.orangeAccent : Colors.orange.shade800;
      default:
        return isDark ? Colors.blueAccent : Colors.blue.shade700;
    }
  }

  Widget _construirSeccionIA({
    required List<Map<String, dynamic>> todosLosDatos,
    required List<Map<String, dynamic>> datosDelMes,
    required Map<String, int> resumenMes,
    required List<Map<String, dynamic>> serieFlujo,
    required AppSettings settings,
    required bool isDark,
    required int diasTranscurridos,
    required int diasDelMes,
    required double tasaAhorro,
    required double gastoDiarioPromedio,
    required Map<String, dynamic> categoriaTop,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF312E81), const Color(0xFF1E1B4B)]
              : [const Color(0xFFEDE9FE), const Color(0xFFE0E7FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.purple.shade700.withAlpha(80)
              : Colors.purple.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.purple.shade900 : Colors.purple.shade100)
                .withAlpha(isDark ? 120 : 180),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _aiExpanded = !_aiExpanded),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(20),
              bottom: Radius.circular(
                _aiExpanded &&
                        (_aiResult != null || _aiLoading || _aiError != null)
                    ? 0
                    : 20,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.purple.shade700.withAlpha(60)
                          : Colors.purple.shade100.withAlpha(180),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: isDark
                          ? Colors.purpleAccent.shade100
                          : Colors.purple.shade700,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Análisis IA',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.purple.shade100
                                : Colors.purple.shade900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _aiResult != null
                              ? 'Toca para ver el análisis'
                              : 'Analiza tus finanzas con inteligencia artificial',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.purple.shade200
                                : Colors.purple.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_aiResult != null || _aiLoading || _aiError != null)
                    Icon(
                      _aiExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: isDark
                          ? Colors.purple.shade200
                          : Colors.purple.shade700,
                    )
                  else
                    FilledButton.icon(
                      onPressed: _aiLoading
                          ? null
                          : () => _requestAiAnalysis(
                              todosLosDatos: todosLosDatos,
                              datosDelMes: datosDelMes,
                              resumenMes: resumenMes,
                              serieFlujo: serieFlujo,
                              settings: settings,
                              diasTranscurridos: diasTranscurridos,
                              diasDelMes: diasDelMes,
                              tasaAhorro: tasaAhorro,
                              gastoDiarioPromedio: gastoDiarioPromedio,
                              categoriaTop: categoriaTop,
                            ),
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('Analizar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.purpleAccent.shade700
                            : Colors.purple.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Body – Loading
          if (_aiLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  Shimmer.fromColors(
                    baseColor: isDark
                        ? Colors.purple.shade800
                        : Colors.purple.shade100,
                    highlightColor: isDark
                        ? Colors.purple.shade600
                        : Colors.purple.shade50,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: 240,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: 180,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Analizando tus datos financieros…',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: isDark
                          ? Colors.purple.shade200
                          : Colors.purple.shade600,
                    ),
                  ),
                ],
              ),
            ),

          // Body – Error
          if (_aiError != null && _aiExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.red.shade900.withAlpha(60)
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red.shade400,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No se pudo completar el análisis. Verifica tu conexión o intenta más tarde.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.red.shade200
                                  : Colors.red.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: () => _requestAiAnalysis(
                      todosLosDatos: todosLosDatos,
                      datosDelMes: datosDelMes,
                      resumenMes: resumenMes,
                      serieFlujo: serieFlujo,
                      settings: settings,
                      diasTranscurridos: diasTranscurridos,
                      diasDelMes: diasDelMes,
                      tasaAhorro: tasaAhorro,
                      gastoDiarioPromedio: gastoDiarioPromedio,
                      categoriaTop: categoriaTop,
                    ),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),

          // Body – Result
          if (_aiResult != null && _aiExpanded)
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Resumen
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.black : Colors.white).withAlpha(
                          isDark ? 40 : 160,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _aiResult!.resumen,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: isDark
                              ? Colors.grey.shade200
                              : Colors.grey.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Insights
                    if (_aiResult!.insights.isNotEmpty) ...[
                      Text(
                        'Hallazgos',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.purple.shade100
                              : Colors.purple.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...(_aiResult!.insights.map((insight) {
                        final color = _insightColor(insight.tipo, isDark);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.black : Colors.white)
                                .withAlpha(isDark ? 30 : 120),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: color.withAlpha(isDark ? 60 : 40),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: color.withAlpha(isDark ? 40 : 25),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _insightIcon(insight.tipo),
                                  size: 16,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      insight.titulo,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.grey.shade100
                                            : Colors.grey.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      insight.descripcion,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.4,
                                        color: isDark
                                            ? Colors.grey.shade300
                                            : Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      })),
                    ],

                    // Recomendaciones
                    if (_aiResult!.recomendaciones.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Recomendaciones',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.purple.shade100
                              : Colors.purple.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...(_aiResult!.recomendaciones.asMap().entries.map((e) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.tealAccent.withAlpha(30)
                                      : Colors.teal.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${e.key + 1}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.tealAccent
                                          : Colors.teal.shade700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  e.value,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: isDark
                                        ? Colors.grey.shade200
                                        : Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      })),
                    ],

                    // Boton analizar de nuevo
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          _aiService.invalidateCache();
                          _requestAiAnalysis(
                            todosLosDatos: todosLosDatos,
                            datosDelMes: datosDelMes,
                            resumenMes: resumenMes,
                            serieFlujo: serieFlujo,
                            settings: settings,
                            diasTranscurridos: diasTranscurridos,
                            diasDelMes: diasDelMes,
                            tasaAhorro: tasaAhorro,
                            gastoDiarioPromedio: gastoDiarioPromedio,
                            categoriaTop: categoriaTop,
                          );
                        },
                        icon: Icon(
                          Icons.refresh,
                          size: 16,
                          color: isDark
                              ? Colors.purple.shade200
                              : Colors.purple.shade700,
                        ),
                        label: Text(
                          'Analizar de nuevo',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.purple.shade200
                                : Colors.purple.shade700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SIMULADOR DE COMPRAS
  // ═══════════════════════════════════════════════════════

  Future<void> _mostrarSimuladorCompra() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Show a loading indicator while fetching data
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await supabase
          .from('gastos')
          .select()
          .eq('user_id', user.id)
          .order('fecha', ascending: false);

      final todosLosDatos = List<Map<String, dynamic>>.from(response);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Calcular promedio de ingresos y gastos de los últimos 3 meses
      final now = DateTime.now();
      var sumaIngresos = 0;
      var sumaGastos = 0;
      var mesesConDatos = 0;
      for (var i = 1; i <= 3; i++) {
        final mes = DateTime(now.year, now.month - i, 1);
        final resumen = _calcularResumenMes(todosLosDatos, mes);
        final ing = resumen['ingresos'] ?? 0;
        final gas = resumen['gastos'] ?? 0;
        if (ing > 0 || gas > 0) {
          sumaIngresos += ing;
          sumaGastos += gas;
          mesesConDatos++;
        }
      }
      final ingresoPromedio = mesesConDatos > 0
          ? sumaIngresos ~/ mesesConDatos
          : 0;
      final gastoPromedio = mesesConDatos > 0 ? sumaGastos ~/ mesesConDatos : 0;
      final flujoBasePromedio = ingresoPromedio - gastoPromedio;

      // Calcular patrimonio actual (Liquidez Neta)
      final datosFiltrados = todosLosDatos.where((mov) {
        final cuenta = (mov['cuenta'] ?? '').toString();
        return _cuentasSeleccionadas.contains(cuenta);
      }).toList();
      var saldoCuentaCorriente = 0;
      for (final mov in datosFiltrados) {
        if ((mov['metodo_pago'] ?? 'Debito') == 'Credito') continue;
        final m = (mov['monto'] as num? ?? 0).toInt();
        if (mov['tipo'] == 'Ingreso') {
          saldoCuentaCorriente += m;
        } else {
          saldoCuentaCorriente -= m;
        }
      }
      // Calcular crédito utilizado (simplificado)
      var saldoCreditoUtilizado = 0;
      for (final mov in datosFiltrados) {
        if ((mov['metodo_pago'] ?? 'Debito') != 'Credito') continue;
        final m = (mov['monto'] as num? ?? 0).toInt();
        if (mov['tipo'] == 'Gasto') {
          saldoCreditoUtilizado += m;
        } else {
          saldoCreditoUtilizado -= m;
        }
      }
      final patrimonioActual = saldoCuentaCorriente - saldoCreditoUtilizado;

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return _SimuladorCompraSheet(
            ingresoPromedio: ingresoPromedio,
            gastoPromedio: gastoPromedio,
            flujoBasePromedio: flujoBasePromedio,
            patrimonioActual: patrimonioActual,
            formatoMoneda: (num n) => _textoMonto(n.toInt(), ocultable: false),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        _mostrarSnack('No se pudieron cargar los datos para simular: $e');
      }
    }
  }

  Widget _filaDetalleBarra(
    String titulo,
    int monto,
    Color color,
    IconData icono,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icono, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            titulo,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
            ),
          ),
          const Spacer(),
          Text(
            _textoMonto(monto),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2433) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 50 : 10),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: isDark ? Border.all(color: Colors.grey.shade800) : null,
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
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
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
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
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
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final List<dynamic> response = await supabase
          .from('gastos')
          .select('monto, tipo, categoria, metodo_pago, fecha, item, estado')
          .eq('user_id', user.id)
          .eq('cuenta', cuenta);

      final movimientos = List<Map<String, dynamic>>.from(response);
      
      final esNombreCredito = _esCuentaCreditoPorNombre(cuenta);
      final hasCredit = movimientos.any((mov) => (mov['metodo_pago'] ?? 'Debito') == 'Credito');
      final hasDebit = movimientos.any((mov) => (mov['metodo_pago'] ?? 'Debito') != 'Credito');

      bool ajustarCredito = false;

      if (esNombreCredito && !hasDebit) {
        ajustarCredito = true;
      } else if (!esNombreCredito && !hasCredit) {
        ajustarCredito = false;
      } else {
        if (!mounted) return;
        final bool? choice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Ajustar Saldo: $cuenta'),
            content: const Text('¿Qué saldo deseas ajustar?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cuenta Corriente (Débito)'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Tarjeta de Crédito'),
              ),
            ],
          ),
        );
        if (choice == null) return;
        ajustarCredito = choice;
      }

      if (ajustarCredito) {
        await _ajustarDeudaTarjetaCuenta(cuenta, movimientosCuenta: movimientos);
        return; // Solo ajusta credito aqui. Si quisiera ambas, tendria que repetir la operacion.
      }

      var saldoVisual = 0;
      var saldoRealSinAjustes = 0;

      for (final mov in movimientos) {
        if ((mov['metodo_pago'] ?? 'Debito') == 'Credito') {
          continue;
        }
        if ((mov['estado'] ?? 'real') == 'fantasma') {
          continue;
        }

        final monto = (mov['monto'] as num? ?? 0).toInt();
        final esIngreso = mov['tipo'] == 'Ingreso';

        if (esIngreso) {
          saldoVisual += monto;
        } else {
          saldoVisual -= monto;
        }

        // Calculamos el saldo "puro" sin ajustes previos
        if (mov['categoria'] != 'Ajuste') {
          if (esIngreso) {
            saldoRealSinAjustes += monto;
          } else {
            saldoRealSinAjustes -= monto;
          }
        }
      }

      if (!mounted) return;

      final nuevoSaldoStr = await _pedirTexto(
        titulo: 'Ajustar saldo: $cuenta',
        etiqueta:
            'Nuevo saldo (Actual: ${_textoMonto(saldoVisual, ocultable: false)})',
        inicial: saldoVisual.toString(),
      );

      if (nuevoSaldoStr == null) return;

      final nuevoSaldo = _parseMonto(nuevoSaldoStr);

      // 2. ELIMINAR ajustes previos para evitar acumulación
      await supabase.from('gastos').delete().match({
        'user_id': user.id,
        'cuenta': cuenta,
        'categoria': 'Ajuste',
        'metodo_pago': 'Debito',
      });

      // 3. Calcular diferencia necesaria desde el saldo REAL
      final diferencia = nuevoSaldo - saldoRealSinAjustes;

      if (diferencia != 0) {
        final esIngreso = diferencia > 0;
        final montoAjuste = diferencia.abs();
        final fechaStr = DateTime.now().toIso8601String().split('T').first;

        await supabase.from('gastos').insert({
          'user_id': user.id,
          'fecha': fechaStr,
          'item': 'Ajuste de Saldo',
          'monto': montoAjuste,
          'categoria': 'Ajuste',
          'cuenta': cuenta,
          'tipo': esIngreso ? 'Ingreso' : 'Gasto',
          'metodo_pago': 'Debito',
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saldo ajustado (ajustes previos reemplazados)'),
          ),
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

  Future<void> _ajustarDeudaTarjetaCuenta(
    String cuenta, {
    List<Map<String, dynamic>>? movimientosCuenta,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final movimientos = movimientosCuenta ??
          List<Map<String, dynamic>>.from(
            await supabase
                .from('gastos')
                .select('monto, tipo, categoria, metodo_pago, fecha, item, estado')
                .eq('user_id', user.id)
                .eq('cuenta', cuenta),
          );

      final settings = widget.settingsController.settings;
      final now = DateTime.now();
      final rangosCredito = _obtenerRangosCicloCredito(settings, referenceDate: now);
      final curStart = rangosCredito['curStart']!;
      
      var gastosFacturadosBruto = 0;
      var gastosPorFacturarBruto = 0;
      var pagosAcumulados = 0;

      var gastosFacturadosReal = 0;
      var gastosPorFacturarReal = 0;
      var pagosAcumuladosReal = 0;

      for (final mov in movimientos) {
        if ((mov['metodo_pago'] ?? 'Debito') != 'Credito') continue;
        if ((mov['estado'] ?? 'real') == 'fantasma') continue;
        
        final monto = (mov['monto'] as num? ?? 0).toInt();
        final tipo = (mov['tipo'] ?? '').toString();
        
        DateTime? movDate;
        try {
          movDate = DateTime.parse(mov['fecha']);
        } catch (_) {}
        if (movDate == null) continue;
        
        final esPorFacturar = !movDate.isBefore(curStart);
        final esAjuste = mov['categoria'] == 'Ajuste';
        
        if (tipo == 'Gasto') {
          if (esPorFacturar) {
            gastosPorFacturarBruto += monto;
            if (!esAjuste) gastosPorFacturarReal += monto;
          } else {
            gastosFacturadosBruto += monto;
            if (!esAjuste) gastosFacturadosReal += monto;
          }
        } else if (tipo == 'Ingreso') {
          pagosAcumulados += monto;
          if (!esAjuste) pagosAcumuladosReal += monto;
        }
      }

      final pagoAFacturadoV = pagosAcumulados > gastosFacturadosBruto ? gastosFacturadosBruto : pagosAcumulados;
      final pagoRestanteV = pagosAcumulados - pagoAFacturadoV;
      final facturadoVisual = (gastosFacturadosBruto - pagoAFacturadoV).clamp(0, 1 << 31).toInt();
      final porFacturarVisual = (gastosPorFacturarBruto - pagoRestanteV).clamp(0, 1 << 31).toInt();

      final pagoAFacturadoR = pagosAcumuladosReal > gastosFacturadosReal ? gastosFacturadosReal : pagosAcumuladosReal;
      final pagoRestanteR = pagosAcumuladosReal - pagoAFacturadoR;
      final facturadoRealSinAjustes = (gastosFacturadosReal - pagoAFacturadoR).clamp(0, 1 << 31).toInt();
      final porFacturarRealSinAjustes = (gastosPorFacturarReal - pagoRestanteR).clamp(0, 1 << 31).toInt();

      if (!mounted) return;

      final result = await _mostrarDialogoAjusteCredito(
        cuenta: cuenta,
        facturadoActual: facturadoVisual,
        porFacturarActual: porFacturarVisual,
      );

      if (result == null) return;

      final nuevoFacturado = result['facturado'] as int;
      final nuevoPorFacturar = result['porFacturar'] as int;

      await supabase.from('gastos').delete().match({
        'user_id': user.id,
        'cuenta': cuenta,
        'categoria': 'Ajuste',
        'metodo_pago': 'Credito',
      });

      final diferenciaFacturado = nuevoFacturado - facturadoRealSinAjustes;
      final diferenciaPorFacturar = nuevoPorFacturar - porFacturarRealSinAjustes;

      if (diferenciaFacturado != 0) {
        final fechaAjusteFacturado = curStart.subtract(const Duration(days: 1));
        final fechaStr = fechaAjusteFacturado.toIso8601String().split('T').first;
        await supabase.from('gastos').insert({
          'user_id': user.id,
          'fecha': fechaStr,
          'item': 'Ajuste Facturado TC',
          'monto': diferenciaFacturado.abs(),
          'categoria': 'Ajuste',
          'cuenta': cuenta,
          'tipo': diferenciaFacturado > 0 ? 'Gasto' : 'Ingreso',
          'metodo_pago': 'Credito',
        });
      }

      if (diferenciaPorFacturar != 0) {
        final fechaStr = DateTime.now().toIso8601String().split('T').first;
        await supabase.from('gastos').insert({
          'user_id': user.id,
          'fecha': fechaStr,
          'item': 'Ajuste Por Facturar TC',
          'monto': diferenciaPorFacturar.abs(),
          'categoria': 'Ajuste',
          'cuenta': cuenta,
          'tipo': diferenciaPorFacturar > 0 ? 'Gasto' : 'Ingreso',
          'metodo_pago': 'Credito',
        });
      }

      if (mounted) _mostrarSnack('Deuda de tarjeta ajustada correctamente');
      
      // Invalidar cache
      _aiService.invalidateCache();
    } catch (e) {
      if (mounted) _mostrarSnack('Error al ajustar deuda de tarjeta: $e');
    }
  }

  Future<Map<String, int>?> _mostrarDialogoAjusteCredito({
    required String cuenta,
    required int facturadoActual,
    required int porFacturarActual,
  }) async {
    final facturadoController = TextEditingController(text: facturadoActual.toString());
    final porFacturarController = TextEditingController(text: porFacturarActual.toString());

    return showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ajustar Tarjeta: $cuenta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ajusta la deuda de tu ciclo cerrado (Facturado) y tu ciclo actual (Por Facturar).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: facturadoController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Monto Facturado',
                helperText: 'Actual: ${_textoMonto(facturadoActual, ocultable: false)}',
                border: const OutlineInputBorder(),
                prefixText: '\$ ',
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: porFacturarController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Monto Por Facturar',
                helperText: 'Actual: ${_textoMonto(porFacturarActual, ocultable: false)}',
                border: const OutlineInputBorder(),
                prefixText: '\$ ',
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final facturado = int.tryParse(facturadoController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              final porFacturar = int.tryParse(porFacturarController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              Navigator.pop(ctx, {'facturado': facturado, 'porFacturar': porFacturar});
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // Skeleton Loader Base
  Widget _construirSkeletonPrincipal(bool isDark) {
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
      highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Tarjeta principal skeleton
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 24),
          // Píldoras horizontales
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              4,
              (index) => Container(
                width: 70,
                height: 35,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Items de lista
          ...List.generate(
            5,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 150, height: 14, color: Colors.white),
                        const SizedBox(height: 8),
                        Container(width: 80, height: 12, color: Colors.white),
                      ],
                    ),
                  ),
                  Container(width: 60, height: 14, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirPaginaMas(List<Map<String, dynamic>> todosLosDatos) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _tarjetaNavegacionMas(
          titulo: 'Flujo de Caja',
          subtitulo: 'Proyección futura de liquidez',
          icono: Icons.insights_rounded,
          color: Colors.blue,
          isDark: isDark,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FlujoCajaScreen(
                  settingsController: widget.settingsController,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _tarjetaNavegacionMas(
          titulo: 'Gastos Compartidos',
          subtitulo: 'Cuentas por cobrar y pagos divididos',
          icono: Icons.people_outline,
          color: Colors.purple,
          isDark: isDark,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    GastosCompartidosScreen(movimientos: todosLosDatos),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _tarjetaNavegacionMas(
          titulo: 'Ajustes',
          subtitulo: 'Configuración de cuentas, categorías y seguridad',
          icono: Icons.settings_outlined,
          color: Colors.grey,
          isDark: isDark,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => _construirPaginaAjustesParaRoute(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _tarjetaNavegacionMas({
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required MaterialColor color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF1E2433) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withAlpha(isDark ? 50 : 30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icono,
                  color: isDark ? color.shade200 : color.shade700,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Wrapper para la página de ajustes que ahora funciona como una ruta normal
  Widget _construirPaginaAjustesParaRoute() {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes'), centerTitle: true),
      body: _construirPaginaAjustes(),
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
              icono: Icons.palette_outlined,

              children: [
                DropdownButtonFormField<String>(
                  initialValue: settings.themeMode,
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
                  onChanged: (val) {
                    HapticFeedback.lightImpact();
                    widget.settingsController.setCompactMode(val);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ocultar montos'),
                  subtitle: const Text(
                    'Enmascara valores en Inicio y Analisis',
                  ),
                  value: settings.hideAmounts,
                  onChanged: (val) {
                    HapticFeedback.lightImpact();
                    widget.settingsController.setHideAmounts(val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _seccionAjustes(
              titulo: 'Notificaciones',
              icono: Icons.notifications_active_outlined,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'Activa esta opción si deseas recibir avisos en tu dispositivo (iOS Safari / Web o Android).',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
                StatefulBuilder(
                  builder: (context, setSectionState) {
                    return FutureBuilder<bool>(
                      future: PushNotificationService.tienePermiso(),
                      builder: (context, snapshot) {
                        final tienePermiso = snapshot.data ?? false;
                        return SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Notificaciones Push'),
                          subtitle: Text(
                            tienePermiso 
                                ? 'Habilitadas en este dispositivo' 
                                : 'Deshabilitadas',
                            style: TextStyle(
                              color: tienePermiso ? Colors.green.shade700 : Colors.grey,
                            ),
                          ),
                          value: tienePermiso,
                          activeColor: Colors.teal.shade400,
                          onChanged: (val) async {
                            HapticFeedback.lightImpact();
                            if (val) {
                              final exito = await PushNotificationService.solicitarPermiso(context);
                              if (exito) {
                                setSectionState(() {});
                              } else {
                                // Forzar reverso de switch si no dio permiso real
                                setSectionState(() {});
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Para desactivarlas, debes ir a Configuración de tu iPhone > Safari > Notificaciones.'),
                                  backgroundColor: Colors.orange,
                                  duration: Duration(seconds: 4),
                                )
                              );
                              setSectionState(() {});
                            }
                          },
                        );
                      }
                    );
                  }
                ),
              ],
            ),
            const SizedBox(height: 12),
            _seccionAjustes(
              titulo: 'Formato financiero',
              icono: Icons.currency_exchange_outlined,

              children: [
                DropdownButtonFormField<String>(
                  initialValue: settings.currencyCode,
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
                  initialValue: settings.localeCode,
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
                  initialValue: settings.weekStartDay,
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
              icono: Icons.account_balance_wallet_outlined,

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
              icono: Icons.category_outlined,

              children: [
                ...settings.activeCategories.map((category) {
                  final budget = settings.categoryBudgets[category];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: GestureDetector(
                      onTap: () => _mostrarEmojiCategoria(category),
                      child: _iconoCategoria(category, size: 24),
                    ),
                    title: Text(category),
                    subtitle: budget != null
                        ? Text('Presupuesto: ${formatoMoneda(budget)}')
                        : null,
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Emoji',
                          icon: const Icon(Icons.emoji_emotions_outlined),
                          onPressed: () => _mostrarEmojiCategoria(category),
                        ),
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
              icono: Icons.pie_chart_outline,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.repeat, color: Colors.purple.shade700),
                  ),
                  title: const Text('Gastos Recurrentes'),
                  subtitle: const Text('Netflix, Alquiler, Seguros...'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GestionarRecurrentesScreen(
                          settingsController: widget.settingsController,
                        ),
                      ),
                    ).then((_) => _cargarRecurrentes());
                  },
                ),
                const Divider(),
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
              icono: Icons.credit_card_outlined,

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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Alertas de vencimiento'),
                  subtitle: const Text(
                    'Notificar antes del vencimiento de la tarjeta',
                  ),
                  value: settings.enableCreditDueAlerts,
                  onChanged: widget.settingsController.setEnableCreditDueAlerts,
                ),
                if (settings.enableCreditDueAlerts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Días de anticipación'),
                    subtitle: Text(
                      '${settings.creditDueAlertDaysBefore} día(s) antes',
                    ),
                    trailing: SizedBox(
                      width: 170,
                      child: Slider(
                        value: settings.creditDueAlertDaysBefore.toDouble(),
                        min: 1,
                        max: 7,
                        divisions: 6,
                        label: settings.creditDueAlertDaysBefore.toString(),
                        onChanged: (value) {
                          widget.settingsController.setCreditDueAlertDaysBefore(
                            value.round(),
                          );
                        },
                      ),
                    ),
                  ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.move_to_inbox_outlined),
                  title: const Text('Establecer Saldo Inicial TC'),
                  subtitle: const Text(
                    'Migrar deuda facturada y consumo actual',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _mostrarDialogoMigracionCredito,
                ),
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
              icono: Icons.notifications_active_outlined,

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
              icono: Icons.security_outlined,

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
                  initialValue: settings.autoLockMinutes,
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
              titulo: 'Integraciones Automáticas',
              icono: Icons.extension_outlined,
              children: [
                const Text(
                  'Automatiza tus finanzas conectando servicios externos a Mis Finanzas.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.apple, size: 36),
                  title: const Text('Apple Pay (Atajos)'),
                  subtitle: const Text('Registra gastos al pagar con tu iPhone'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _mostrarConfiguracionApplePay,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _seccionAjustes(
              titulo: 'Datos y mantenimiento',
              icono: Icons.storage_rounded,

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
                const SizedBox(height: 16),
                const Divider(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade900,
                    side: BorderSide(color: Colors.red.shade900),
                  ),
                  onPressed: _eliminarCuentaUsuario,
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('Eliminar cuenta permanentemente'),
                ),
              ],
            ),
            const SizedBox(height: 90),
          ],
        );
      },
    );
  }

  // ─── METAS DE AHORRO ─────────────────────────────────────────────────

  static const _coloresMeta = [
    Color(0xFF009688), // teal
    Color(0xFF4CAF50), // green
    Color(0xFF2196F3), // blue
    Color(0xFF9C27B0), // purple
    Color(0xFFFF9800), // orange
    Color(0xFFE91E63), // pink
    Color(0xFFF44336), // red
    Color(0xFFFFC107), // amber
  ];

  static const _emojisMeta = [
    '✈️',
    '🏖️',
    '🏠',
    '🚗',
    '💻',
    '📱',
    '🎮',
    '🎓',
    '💍',
    '👶',
    '🐶',
    '🏋️',
    '🎸',
    '📸',
    '🧳',
    '🏔️',
    '💰',
    '🏦',
    '🛡️',
    '🎯',
    '⭐',
    '🚀',
    '🌟',
    '🎁',
  ];

  Widget _construirPaginaMetas() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<List<Map<String, dynamic>>>(
      initialData: _cachedMetas,
      key: ValueKey(_metasRefreshNonce),
      stream: _streamMetasUsuario().map((datos) {
        try {
          widget.settingsController.preferences.setString('metas_cache', jsonEncode(datos));
        } catch (_) {}
        return datos;
      }),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Metas Stream Error: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.cloud_sync_rounded,
                      size: 36,
                      color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                    ),
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: isDark ? Colors.indigo.shade300 : Colors.indigo.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Sincronizando metas...',
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final todasLasMetas = snapshot.data!;
        final metasActivas = todasLasMetas
            .where((m) => m['completada'] != true)
            .toList();
        final metasCompletadas = todasLasMetas
            .where((m) => m['completada'] == true)
            .toList();

        // Calculate totals for summary
        var totalAhorrado = 0;
        var totalObjetivo = 0;
        for (final meta in todasLasMetas) {
          totalAhorrado += (meta['monto_actual'] as num? ?? 0).toInt();
          totalObjetivo += (meta['monto_meta'] as num? ?? 0).toInt();
        }
        final progresoTotal = totalObjetivo > 0
            ? totalAhorrado / totalObjetivo
            : 0.0;

        if (todasLasMetas.isEmpty) {
          return _construirMetasVacio();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Summary Header ──
              _construirResumenMetas(
                totalAhorrado,
                totalObjetivo,
                progresoTotal,
                metasActivas.length,
                metasCompletadas.length,
                isDark,
              ),
              const SizedBox(height: 24),

              // ── Active Goals ──
              if (metasActivas.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(
                      Icons.flag_outlined,
                      size: 18,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Metas activas',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...metasActivas.map(
                  (meta) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _construirTarjetaMeta(meta, isDark),
                  ),
                ),
              ],

              // ── Completed Goals (collapsible) ──
              if (metasCompletadas.isNotEmpty) ...[
                const SizedBox(height: 8),
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: isDark ? Colors.greenAccent : Colors.green,
                    ),
                    title: Text(
                      'Completadas (${metasCompletadas.length})',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    children: metasCompletadas
                        .map(
                          (meta) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _construirTarjetaMeta(
                              meta,
                              isDark,
                              completada: true,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],

              // ── Add button at the bottom ──
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _mostrarDialogoMeta(),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva meta'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 90),
            ],
          ),
        );
      },
    );
  }

  Widget _construirMetasVacio() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flag_circle_outlined,
              size: 80,
              color: isDark
                  ? Colors.tealAccent.withAlpha(100)
                  : Colors.teal.shade200,
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Empieza a ahorrar\ncon propósito!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Crea metas como "Viaje a Japón" o\n"Fondo de emergencia" y ve tu progreso.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => _mostrarDialogoMeta(),
              icon: const Icon(Icons.add),
              label: const Text('Crear primera meta'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirResumenMetas(
    int totalAhorrado,
    int totalObjetivo,
    double progresoTotal,
    int activas,
    int completadas,
    bool isDark,
  ) {
    final colorBarra = progresoTotal >= 1.0
        ? Colors.greenAccent
        : Colors.tealAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A2E2A), const Color(0xFF1E2433)]
              : [Colors.teal.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.teal.shade800 : Colors.teal.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.savings,
                color: isDark ? Colors.tealAccent : Colors.teal,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Resumen de metas',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _textoMonto(totalAhorrado),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.tealAccent : Colors.teal.shade700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'de ${_textoMonto(totalObjetivo)} objetivo total',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progresoTotal.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: isDark
                    ? Colors.grey.shade800
                    : Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(colorBarra),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(progresoTotal * 100).clamp(0, 9999).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? colorBarra : Colors.teal.shade700,
                ),
              ),
              Text(
                '$activas activa${activas != 1 ? 's' : ''} · $completadas completada${completadas != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _construirTarjetaMeta(
    Map<String, dynamic> meta,
    bool isDark, {
    bool completada = false,
  }) {
    final nombre = meta['nombre'] ?? 'Meta';
    final emoji = meta['emoji'] as String?;
    final montoMeta = (meta['monto_meta'] as num? ?? 1).toInt();
    final montoActual = (meta['monto_actual'] as num? ?? 0).toInt();
    final colorHex = meta['color'] as String? ?? '#009688';
    final fechaLimite = meta['fecha_limite'] as String?;

    final progreso = montoMeta > 0
        ? (montoActual / montoMeta).clamp(0.0, 1.0)
        : 0.0;

    // Parse color
    final color = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));

    // Days remaining
    String? diasRestantes;
    if (fechaLimite != null && !completada) {
      final limite = DateTime.parse(fechaLimite);
      final hoy = DateTime.now();
      final diff = limite.difference(hoy).inDays;
      if (diff > 0) {
        diasRestantes = '$diff días restantes';
      } else if (diff == 0) {
        diasRestantes = '¡Hoy vence!';
      } else {
        diasRestantes = 'Venció hace ${diff.abs()} días';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2433) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: completada
              ? (isDark ? Colors.green.shade900 : Colors.green.shade100)
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 40 : 6),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _mostrarOpcionesMeta(meta),
          onLongPress: () => _mostrarOpcionesMeta(meta),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: emoji + name + menu
                Row(
                  children: [
                    // Circular progress
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: progreso),
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) =>
                                CircularProgressIndicator(
                                  value: value,
                                  strokeWidth: 4,
                                  backgroundColor: isDark
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade200,
                                  valueColor: AlwaysStoppedAnimation(
                                    completada ? Colors.green : color,
                                  ),
                                ),
                          ),
                          if (emoji != null && emoji.isNotEmpty)
                            Text(emoji, style: const TextStyle(fontSize: 18))
                          else if (completada)
                            Icon(Icons.check, size: 20, color: Colors.green)
                          else
                            Text(
                              '${(progreso * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              decoration: completada
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_textoMonto(montoActual)} / ${_textoMonto(montoMeta)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!completada)
                      FilledButton.tonal(
                        onPressed: () => _mostrarDialogoAbonar(meta),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          backgroundColor: color.withAlpha(isDark ? 50 : 30),
                        ),
                        child: Text(
                          'Abonar',
                          style: TextStyle(
                            color: isDark ? color.withAlpha(220) : color,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    // ── Menú de 3 puntos ──
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _mostrarDialogoMeta(metaExistente: meta);
                          case 'complete':
                            supabase
                                .from('metas_ahorro')
                                .update({
                                  'completada': true,
                                  'updated_at': DateTime.now()
                                      .toIso8601String(),
                                })
                                .eq('id', meta['id'])
                                .then((_) {
                                  _forzarRefrescoMetas();
                                  _mostrarSnack('¡Meta completada! 🎉');
                                });
                          case 'reactivate':
                            supabase
                                .from('metas_ahorro')
                                .update({
                                  'completada': false,
                                  'updated_at': DateTime.now()
                                      .toIso8601String(),
                                })
                                .eq('id', meta['id'])
                                .then((_) => _forzarRefrescoMetas());
                          case 'delete':
                            _confirmarEliminarMeta(meta);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 10),
                              Text('Editar'),
                            ],
                          ),
                        ),
                        if (!completada)
                          const PopupMenuItem(
                            value: 'complete',
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline, size: 18),
                                SizedBox(width: 10),
                                Text('Completar'),
                              ],
                            ),
                          ),
                        if (completada)
                          const PopupMenuItem(
                            value: 'reactivate',
                            child: Row(
                              children: [
                                Icon(Icons.undo, size: 18),
                                SizedBox(width: 10),
                                Text('Reactivar'),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Eliminar',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progreso),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      backgroundColor: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        completada ? Colors.green : color,
                      ),
                    ),
                  ),
                ),

                // Footer: deadline + percentage
                if (diasRestantes != null || completada) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (diasRestantes != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              diasRestantes,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      if (completada)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.celebration,
                              size: 14,
                              color: isDark ? Colors.greenAccent : Colors.green,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '¡Meta cumplida!',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.greenAccent
                                    : Colors.green,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarOpcionesMeta(Map<String, dynamic> meta) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Editar meta'),
                onTap: () {
                  Navigator.pop(context);
                  _mostrarDialogoMeta(metaExistente: meta);
                },
              ),
              if (meta['completada'] != true)
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Marcar como completada'),
                  onTap: () async {
                    Navigator.pop(context);
                    await supabase
                        .from('metas_ahorro')
                        .update({
                          'completada': true,
                          'updated_at': DateTime.now().toIso8601String(),
                        })
                        .eq('id', meta['id']);
                    _forzarRefrescoMetas();
                    _mostrarSnack('¡Meta completada! 🎉');
                  },
                ),
              if (meta['completada'] == true)
                ListTile(
                  leading: const Icon(Icons.undo),
                  title: const Text('Reactivar meta'),
                  onTap: () async {
                    Navigator.pop(context);
                    await supabase
                        .from('metas_ahorro')
                        .update({
                          'completada': false,
                          'updated_at': DateTime.now().toIso8601String(),
                        })
                        .eq('id', meta['id']);
                    _forzarRefrescoMetas();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Eliminar',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmarEliminarMeta(meta);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmarEliminarMeta(Map<String, dynamic> meta) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar meta'),
        content: Text(
          '¿Seguro que deseas eliminar "${meta['nombre']}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await supabase.from('metas_ahorro').delete().eq('id', meta['id']);
      _forzarRefrescoMetas();
      _mostrarSnack('Meta eliminada');
    }
  }

  void _mostrarDialogoMeta({Map<String, dynamic>? metaExistente}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FormularioMeta(
        metaExistente: metaExistente,
        formatoMoneda: formatoMoneda,
        onGuardar: (data) async {
          if (metaExistente != null) {
            await supabase
                .from('metas_ahorro')
                .update({
                  ...data,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', metaExistente['id']);
          } else {
            await supabase.from('metas_ahorro').insert({
              ...data,
              'user_id': supabase.auth.currentUser!.id,
            });
          }
          _forzarRefrescoMetas();
        },
      ),
    );
  }

  void _mostrarDialogoAbonar(Map<String, dynamic> meta) {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final montoActual = (meta['monto_actual'] as num? ?? 0).toInt();
    final montoMeta = (meta['monto_meta'] as num? ?? 1).toInt();
    final restante = montoMeta - montoActual;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (meta['emoji'] != null &&
                      (meta['emoji'] as String).isNotEmpty)
                    Text(meta['emoji'], style: const TextStyle(fontSize: 22))
                  else
                    const Icon(Icons.savings_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Abonar a "${meta['nombre']}"',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Faltan ${_textoMonto(restante > 0 ? restante : 0)} para completar',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Monto a abonar',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Quick amount chips
              if (restante > 0)
                Wrap(
                  spacing: 8,
                  children: [
                    if (restante >= 10000) _chipAbonoRapido(controller, 10000),
                    if (restante >= 50000) _chipAbonoRapido(controller, 50000),
                    if (restante >= 100000)
                      _chipAbonoRapido(controller, 100000),
                    ActionChip(
                      label: Text('Todo (${_textoMonto(restante)})'),
                      onPressed: () => controller.text = restante.toString(),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () async {
                    final monto = int.tryParse(controller.text.trim()) ?? 0;
                    if (monto <= 0) return;
                    final user = supabase.auth.currentUser;
                    if (user == null) {
                      _mostrarSnack('No hay sesión activa');
                      return;
                    }
                    final montoAplicado = monto > restante && restante > 0
                        ? restante
                        : monto;
                    final nuevoMonto = montoActual + montoAplicado;
                    final completada = nuevoMonto >= montoMeta;
                    try {
                      await supabase
                          .from('metas_ahorro')
                          .update({
                            'monto_actual': nuevoMonto,
                            'completada': completada,
                            'updated_at': DateTime.now().toIso8601String(),
                          })
                          .eq('id', meta['id']);

                      // El abono impacta la liquidez como salida de débito.
                      await supabase.from('gastos').insert({
                        'user_id': user.id,
                        'fecha': DateTime.now().toIso8601String(),
                        'item': 'Abono meta: ${meta['nombre']}',
                        'detalle': 'Aporte a meta de ahorro',
                        'monto': montoAplicado,
                        'categoria': 'Transferencia',
                        'cuenta':
                            widget.settingsController.settings.defaultAccount,
                        'tipo': 'Gasto',
                        'metodo_pago': 'Debito',
                      });

                      _forzarRefrescoMetas();
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (completada) {
                        _mostrarSnack(
                          '🎉 ¡Meta "${meta['nombre']}" completada!',
                        );
                      } else {
                        _mostrarSnack(
                          'Abono de ${_textoMonto(montoAplicado)} registrado ✓',
                        );
                      }
                    } catch (e) {
                      _mostrarSnack('No se pudo registrar el abono: $e');
                    } finally {
                      controller.dispose();
                    }
                  },
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Abonar', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipAbonoRapido(TextEditingController controller, int monto) {
    return ActionChip(
      label: Text(_textoMonto(monto, ocultable: false)),
      onPressed: () => controller.text = monto.toString(),
    );
  }

  Widget _construirPaginaPresupuestos(
    List<Map<String, dynamic>> todosLosDatos,
  ) {
    return AnimatedBuilder(
      animation: widget.settingsController,
      builder: (context, _) {
        final settings = widget.settingsController.settings;
        final globalBudget = settings.globalMonthlyBudget ?? 0;
        var totalPresupuestoCategorias = 0;
        for (final cat in settings.activeCategories) {
          totalPresupuestoCategorias += settings.categoryBudgets[cat] ?? 0;
        }
        final presupuestoBase = globalBudget > 0
            ? globalBudget
            : totalPresupuestoCategorias;
        final usaPresupuestoCategorias =
            globalBudget <= 0 && totalPresupuestoCategorias > 0;
        final tienePresupuestoDefinido = presupuestoBase > 0;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        // Modo Edicion: Logica de distribucion (Slider/Inputs)
        if (_editandoPresupuesto) {
          var totalAsignado = 0;
          for (final cat in settings.activeCategories) {
            totalAsignado += settings.categoryBudgets[cat] ?? 0;
          }

          final restante = globalBudget - totalAsignado;
          final excedido = restante < 0;
          final porcentajeAsignado = globalBudget > 0
              ? (totalAsignado / globalBudget).clamp(0.0, 1.0)
              : 0.0;

          Color colorBarra = Colors.teal;
          if (excedido) {
            colorBarra = Colors.red;
          } else if (restante > 0) {
            colorBarra = Colors.blue;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Edicion
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Ajustando Presupuesto',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.check_circle,
                        size: 28,
                        color: Colors.teal,
                      ),
                      onPressed: () =>
                          setState(() => _editandoPresupuesto = false),
                      tooltip: 'Guardar y Salir',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // UI Distribucion
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2433) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(isDark ? 50 : 12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: isDark
                        ? Border.all(color: Colors.grey.shade800)
                        : null,
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Mensual',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: _editarPresupuestoGlobal,
                            color: Theme.of(context).primaryColor,
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: _editarPresupuestoGlobal,
                        child: Text(
                          _textoMonto(globalBudget, ocultable: false),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: excedido ? 1.0 : porcentajeAsignado,
                          minHeight: 12,
                          backgroundColor: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade100,
                          color: colorBarra,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Asignado: ${_textoMonto(totalAsignado, ocultable: false)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: excedido ? Colors.red : Colors.teal,
                            ),
                          ),
                          Text(
                            excedido
                                ? 'Excede: ${_textoMonto(restante.abs(), ocultable: false)}'
                                : 'Libre: ${_textoMonto(restante, ocultable: false)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: excedido ? Colors.red : Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                const Text(
                  'Asignar por Categoría',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),

                ...settings.activeCategories.map((categoria) {
                  final asignado = settings.categoryBudgets[categoria] ?? 0;
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _iconoCategoria(categoria, size: 20),
                      ),
                      title: Text(
                        categoria,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _textoMonto(asignado, ocultable: false),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      onTap: () => _editarPresupuestoCategoria(categoria),
                    ),
                  );
                }),
              ],
            ),
          );
        }

        // Modo Visualizacion: Progreso Real (Gastado vs Presupuesto)
        // 1. Filtrar datos del mes
        final datosDelMes = todosLosDatos.where((mov) {
          final fechaMov = DateTime.parse(mov['fecha']);
          return fechaMov.year == _mesVisualizado.year &&
              fechaMov.month == _mesVisualizado.month;
        }).toList();

        // 2. Calcular gasto total y por categoria
        var gastoTotalMes = 0;
        final gastoPorCategoria = <String, int>{};

        for (final mov in datosDelMes) {
          if (mov['tipo'] != 'Gasto') continue;
          final categoria = (mov['categoria'] ?? '').toString();
          if (categoria == 'Transferencia' ||
              categoria == 'Ajuste' ||
              categoria == 'Cuentas por Cobrar') {
            continue;
          }
          final monto = (mov['monto'] as num? ?? 0).toInt();
          gastoTotalMes += monto;
          final cat = categoria.isEmpty ? 'Varios' : categoria;
          gastoPorCategoria[cat] = (gastoPorCategoria[cat] ?? 0) + monto;
        }

        final porcentajeGlobalEjecutado = presupuestoBase > 0
            ? (gastoTotalMes / presupuestoBase).clamp(0.0, 1.0)
            : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Presupuesto',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${obtenerNombreMes(_mesVisualizado.month)} ${_mesVisualizado.year}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 24),
                    onPressed: () =>
                        setState(() => _editandoPresupuesto = true),
                    tooltip: 'Ajustar Presupuestos',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Card Resumen Ejecucion Global
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade700, Colors.teal.shade500],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.teal.withAlpha(80),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tienePresupuestoDefinido
                          ? (usaPresupuestoCategorias
                                ? 'Gasto Total vs Presupuesto por categorias'
                                : 'Gasto Total vs Presupuesto')
                          : 'Gasto Total del mes',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _textoMonto(gastoTotalMes, ocultable: false),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (tienePresupuestoDefinido)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4, left: 6),
                            child: Text(
                              '/ ${_textoMonto(presupuestoBase, ocultable: false)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!tienePresupuestoDefinido)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Sin presupuesto asignado (global ni por categoria)',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: porcentajeGlobalEjecutado,
                        minHeight: 8,
                        backgroundColor: Colors.black12,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        tienePresupuestoDefinido
                            ? '${(porcentajeGlobalEjecutado * 100).toStringAsFixed(1)}% gastado'
                            : 'Configura presupuestos para ver avance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'Progreso por Categoría',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Lista Progreso Categorias
              ...settings.activeCategories.map((categoria) {
                final presupuestoCat = settings.categoryBudgets[categoria] ?? 0;
                if (presupuestoCat == 0) {
                  return const SizedBox.shrink();
                }

                final gastado = gastoPorCategoria[categoria] ?? 0;
                final progress = (gastado / presupuestoCat).clamp(0.0, 1.0);
                final saldoRestante = presupuestoCat - gastado;

                Color colorStatus = Colors.green;
                if (progress > 1.0 || saldoRestante < 0) {
                  colorStatus = Colors.red;
                } else if (progress > 0.8) {
                  colorStatus = Colors.orange;
                }

                final isDark = Theme.of(context).brightness == Brightness.dark;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2433) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(isDark ? 50 : 8),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: isDark
                        ? Border.all(color: Colors.grey.shade800)
                        : null,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _iconoCategoria(
                            categoria,
                            size: 20,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              categoria,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Text(
                            _textoMonto(gastado, ocultable: false),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: saldoRestante < 0
                                  ? Colors.red
                                  : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          Text(
                            ' / ${_textoMonto(presupuestoCat, ocultable: false)}',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade100,
                          color: colorStatus,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          saldoRestante >= 0
                              ? 'Quedan ${_textoMonto(saldoRestante, ocultable: false)}'
                              : 'Excedido por ${_textoMonto(saldoRestante.abs(), ocultable: false)}',
                          style: TextStyle(
                            color: saldoRestante >= 0
                                ? (isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600)
                                : Colors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 24),
              if (settings.activeCategories.any(
                (c) => (settings.categoryBudgets[c] ?? 0) == 0,
              ))
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.info_outline, size: 16),
                    label: const Text(
                      'Hay categorías sin presupuesto asignado',
                    ),
                    onPressed: () =>
                        setState(() => _editandoPresupuesto = true),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _seccionAjustes({
    required String titulo,
    required List<Widget> children,
    IconData? icono,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // En modo oscuro usamos un gris oscuro (surface) y en claro blanco
    final bgColor = isDark
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Colors.white;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: icono != null
              ? Icon(icono, color: Theme.of(context).colorScheme.primary)
              : null,
          title: Text(
            titulo,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          backgroundColor: bgColor,
          collapsedBackgroundColor: bgColor,
          shape: const Border(),
          collapsedShape: const Border(),
          children: children,
        ),
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
    if (value == null || value.trim() == actual) return;

    // 1. Rename in settings (local + cloud sync)
    widget.settingsController.renameAccount(actual, value);

    // 2. Update all existing transactions in Supabase
    try {
      await supabase
          .from('gastos')
          .update({'cuenta': value.trim()})
          .eq('cuenta', actual);
      if (mounted) {
        _mostrarSnack('Cuenta renombrada: $actual → ${value.trim()}');
      }
    } catch (e) {
      if (mounted) {
        _mostrarSnack(
          'Cuenta renombrada en ajustes, pero error al actualizar movimientos: $e',
        );
      }
    }
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
                if (!context.mounted) {
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

  String _generarTokenAleatorio() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        32, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  Future<void> _mostrarConfiguracionApplePay() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Primero intentamos recuperar el token existente para no hacer múltiples
    String token = '';
    try {
      final res = await supabase
          .from('webhook_tokens')
          .select('token')
          .eq('user_id', user.id)
          .maybeSingle();

      if (res != null) {
        token = res['token'] as String;
      } else {
        token = _generarTokenAleatorio();
        await supabase.from('webhook_tokens').insert({
          'user_id': user.id,
          'token': token,
        });
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: const Text(
                'Asegúrate de haber corrido el script SQL en Supabase para crear la tabla webhook_tokens antes de configurar esto.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final endpointUrl =
        'https://xycshsxqcfypgffnqmxb.supabase.co/rest/v1/rpc/registrar_gasto_webhook';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Atajo de Apple Pay'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sigue estas instrucciones en tu iPhone:\n'
                '1. Abre la app "Atajos" (Shortcuts) y ve a la pestaña "Automatización".\n'
                '2. Presiona "+" y elige "Transacción". Selecciona tu tarjeta y elige "Cuando el pago se realice".\n'
                '3. Agrega la acción "Obtener contenido de URL".\n'
                '4. Pega esta URL en el campo URL:',
              ),
              const SizedBox(height: 8),
              SelectableText(
                endpointUrl,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 12),
              const Text(
                '5. Expande las opciones de la acción y cambia el Método a "POST".\n'
                '6. Define la Cabecera (Header):\n'
                '   - Clave: apikey\n'
                '   - Texto: (tu clave anon pública de Supabase)\n'
                '7. En "Cuerpo de la solicitud" selecciona JSON y agrega 3 valores:\n'
                '   - p_token (Texto) : Tu Token Secreto\n'
                '   - p_monto (Número) : Selecciona la variable "Importe"\n'
                '   - p_comercio (Texto) : Selecciona la variable "Comerciante"\n'
                '\n8. Agrega una acción final "Mostrar Notificación" y escribe: "¡Gasto en Apple Pay guardado en A revisar!"\n\n'
                'Tu Token Secreto es:',
              ),
              const SizedBox(height: 8),
              SelectableText(
                token,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportarMovimientosCsv() async {
    try {
      final rows = await supabase
          .from('gastos')
          .select()
          .order('fecha', ascending: true);

      final csv = StringBuffer(
        'fecha,item,monto,categoria,cuenta,tipo,metodo_pago\n',
      );
      for (final row in rows) {
        final fecha = (row['fecha'] ?? '').toString();
        final item = _csvEscape((row['item'] ?? '').toString());
        final monto = (row['monto'] as num? ?? 0)
            .toString(); // Ensure monto is num before toString
        final categoria = _csvEscape((row['categoria'] ?? '').toString());
        final cuenta = _csvEscape((row['cuenta'] ?? '').toString());
        final tipo = _csvEscape((row['tipo'] ?? '').toString());
        final metodoPago = _csvEscape((row['metodo_pago'] ?? '').toString());
        csv.writeln('$fecha,$item,$monto,$categoria,$cuenta,$tipo,$metodoPago');
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

  Future<void> _eliminarCuentaUsuario() async {
    final ok = await _confirmar(
      titulo: 'Eliminar Cuenta Permanentemente',
      mensaje:
          'Esta accion eliminara tu usuario, todos tus datos financieros de forma permanente. Es irreversible.',
    );
    if (!ok) return;

    final texto = await _pedirTexto(
      titulo: 'Confirmacion final',
      etiqueta: 'Escribe ELIMINAR para confirmar',
    );
    if (texto != 'ELIMINAR') {
      _mostrarSnack('Cancelado');
      return;
    }

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Intentar borrar todos los datos vinculados (si RLS lo permite, normalmente el user_id está en RLS)
      await supabase.from('gastos').delete().eq('user_id', userId);
      try {
        await supabase.from('recurrentes').delete().eq('user_id', userId);
        await supabase.from('metas_ahorro').delete().eq('user_id', userId);
      } catch (_) {
        // ignora si estas tablas no existen
      }

      // Resetear configuraciones locales
      await widget.settingsController.resetSettings();

      // Llamar al backend para eliminar el auth user si está configurado
      try {
        await supabase.rpc('delete_user');
      } catch (_) {
        // En algunos setups no hay un call delete_user definido.
      }

      await supabase.auth.signOut();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                LoginScreen(settingsController: widget.settingsController),
          ),
        );
      }
    } catch (e) {
      _mostrarSnack('Error al eliminar cuenta: $e');
    }
  }

  Future<void> _mostrarDialogoMigracionCredito() async {
    final accounts = widget.settingsController.settings.activeAccounts;
    // Intentar preseleccionar una cuenta que parezca ser de crédito
    String selectedAccount = accounts.firstWhere(
      (acc) =>
          acc.toLowerCase().contains('credito') ||
          acc.toLowerCase().contains('crédito') ||
          acc.toLowerCase().contains('tc') ||
          acc.toLowerCase().contains('visa') ||
          acc.toLowerCase().contains('master'),
      orElse: () => widget.settingsController.settings.defaultAccount,
    );

    // Asegurarse de que la cuenta seleccionada sea válida
    if (!accounts.contains(selectedAccount) && accounts.isNotEmpty) {
      selectedAccount = accounts.first;
    }

    final facturadoController = TextEditingController();
    final noFacturadoController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Migrar Deuda Tarjeta'),
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ingresa los montos pendientes. Se usará la suma para fijar la deuda total actual de la tarjeta y se reemplazarán ajustes previos.',
                    style: TextStyle(fontSize: 13, color: Colors.orange),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedAccount,
                    decoration: const InputDecoration(
                      labelText: 'Cuenta (T. Crédito)',
                      border: OutlineInputBorder(),
                    ),
                    items: accounts.map((acc) {
                      return DropdownMenuItem(value: acc, child: Text(acc));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setStateDialog(() => selectedAccount = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: facturadoController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Monto Facturado',
                      helperText: 'Deuda cerrada pendiente de pago',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noFacturadoController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Monto NO Facturado',
                      helperText: 'Consumo del ciclo actual',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
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
                    _guardarMigracionCredito(
                      selectedAccount,
                      facturadoController.text,
                      noFacturadoController.text,
                    );
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

  Future<void> _guardarMigracionCredito(
    String cuenta,
    String facturadoStr,
    String noFacturadoStr,
  ) async {
    final mFacturado =
        int.tryParse(facturadoStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final mNoFacturado =
        int.tryParse(noFacturadoStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final deudaObjetivo = mFacturado + mNoFacturado;

      final movimientosCuenta = List<Map<String, dynamic>>.from(
        await supabase
            .from('gastos')
            .select('monto, tipo, categoria, metodo_pago')
            .eq('user_id', user.id)
            .eq('cuenta', cuenta),
      );

      var deudaBaseSinAjustes = 0;
      for (final mov in movimientosCuenta) {
        if ((mov['metodo_pago'] ?? 'Debito') != 'Credito') continue;
        if (mov['categoria'] == 'Ajuste') continue;
        final monto = (mov['monto'] as num? ?? 0).toInt();
        if ((mov['tipo'] ?? '') == 'Gasto') {
          deudaBaseSinAjustes += monto;
        } else if ((mov['tipo'] ?? '') == 'Ingreso') {
          deudaBaseSinAjustes -= monto;
        }
      }

      await supabase.from('gastos').delete().match({
        'user_id': user.id,
        'cuenta': cuenta,
        'categoria': 'Ajuste',
        'metodo_pago': 'Credito',
      });

      final diferencia = deudaObjetivo - deudaBaseSinAjustes;
      if (diferencia != 0) {
        final fechaStr = DateTime.now().toIso8601String().split('T').first;
        await supabase.from('gastos').insert({
          'user_id': user.id,
          'fecha': fechaStr,
          'item': 'Ajuste de Deuda TC',
          'monto': diferencia.abs(),
          'categoria': 'Ajuste',
          'cuenta': cuenta,
          'tipo': diferencia > 0 ? 'Gasto' : 'Ingreso',
          'metodo_pago': 'Credito',
        });
      }

      _mostrarSnack(
        'Deuda de tarjeta actualizada (ajustes previos reemplazados)',
      );
    } catch (e) {
      _mostrarSnack('Error al actualizar deuda de tarjeta: $e');
    }
  }

  void _confirmarCierreCiclo(int montoPorFacturar) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.event_available, color: Colors.amber.shade700, size: 24),
            const SizedBox(width: 10),
            const Text('Cerrar ciclo ahora'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Los gastos de "Por Facturar" pasarán a "Facturado".',
              style: TextStyle(
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(isDark ? 25 : 12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withAlpha(40)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Monto a facturar: ${_textoMonto(montoPorFacturar, ocultable: false)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Colors.amber.shade200
                            : Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Usa esto cuando el banco te facturó antes del día configurado.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              final hoy = DateTime.now().toIso8601String().split('T').first;
              widget.settingsController.setLastManualBillingClose(hoy);
              Navigator.pop(ctx);
              _mostrarSnack('Ciclo cerrado. Los montos se recalcularán.');
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Confirmar cierre'),
          ),
        ],
      ),
    );
  }

  void _mostrarConfiguracionFechas() {
    int diaCierre = widget.settingsController.settings.creditCardBillingDay;
    int diaVencimiento = widget.settingsController.settings.creditCardDueDay;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: const Text('Configurar Fechas de TC'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Día Cierre',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        initialValue: diaCierre,
                        items: List.generate(31, (i) => i + 1)
                            .map((day) => DropdownMenuItem(value: day, child: Text(day.toString())))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setStateDialog(() => diaCierre = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Día Pago',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        initialValue: diaVencimiento,
                        items: List.generate(31, (i) => i + 1)
                            .map((day) => DropdownMenuItem(value: day, child: Text(day.toString())))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setStateDialog(() => diaVencimiento = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Si tu banco cambió tus días del mes, actualízalos aquí.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  widget.settingsController.setCreditCardBillingDay(diaCierre);
                  widget.settingsController.setCreditCardDueDay(diaVencimiento);
                  Navigator.pop(ctx);
                  _mostrarSnack('Fechas de tarjeta actualizadas.');
                },
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _mostrarDialogoAbonoTarjeta({
    required List<String> cuentasCredito,
    required String itemAbono,
    int? montoInicial,
    String titulo = 'Registrar abono',
  }) async {
    if (cuentasCredito.isEmpty) {
      _mostrarSnack('No hay cuentas de credito disponibles');
      return;
    }

    final allAccounts = widget.settingsController.settings.activeAccounts;
    var cuentasDebito = allAccounts
        .where((a) => !cuentasCredito.contains(a))
        .toList();
    if (cuentasDebito.isEmpty) {
      cuentasDebito = allAccounts.isNotEmpty ? allAccounts : ['Efectivo'];
    }

    var cuentaCreditoSeleccionada = cuentasCredito.first;
    var cuentaDebitoSeleccionada =
        widget.settingsController.settings.defaultAccount;
    if (!cuentasDebito.contains(cuentaDebitoSeleccionada)) {
      cuentaDebitoSeleccionada = cuentasDebito.first;
    }

    final montoController = TextEditingController(
      text: montoInicial != null && montoInicial > 0
          ? montoInicial.toString()
          : '',
    );

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(titulo),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: cuentaDebitoSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Cta. Origen (Débito)',
                      border: OutlineInputBorder(),
                    ),
                    items: cuentasDebito
                        .map(
                          (acc) =>
                              DropdownMenuItem(value: acc, child: Text(acc)),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setStateDialog(() => cuentaDebitoSeleccionada = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: cuentaCreditoSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Cta. Destino (Tarjeta)',
                      border: OutlineInputBorder(),
                    ),
                    items: cuentasCredito
                        .map(
                          (acc) =>
                              DropdownMenuItem(value: acc, child: Text(acc)),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setStateDialog(() => cuentaCreditoSeleccionada = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: montoController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Monto',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
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
                    final monto = _parseMonto(montoController.text);
                    if (monto <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ingresa un monto valido'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(context);
                    _registrarAbonoTarjeta(
                      cuentaCredito: cuentaCreditoSeleccionada,
                      cuentaDebito: cuentaDebitoSeleccionada,
                      monto: monto,
                      itemAbono: itemAbono,
                    );
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

  Future<void> _registrarAbonoTarjeta({
    required String cuentaCredito,
    required String cuentaDebito,
    required int monto,
    required String itemAbono,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final fechaIso = DateTime.now().toIso8601String();

      final abonoCredito = {
        'user_id': user.id,
        'fecha': fechaIso,
        'item': itemAbono,
        'monto': monto,
        'categoria': 'Transferencia',
        'cuenta': cuentaCredito,
        'tipo': 'Ingreso',
        'metodo_pago': 'Credito',
      };

      final pagoDebito = {
        'user_id': user.id,
        'fecha': fechaIso,
        'item': itemAbono,
        'monto': monto,
        'categoria': 'Transferencia',
        'cuenta': cuentaDebito,
        'tipo': 'Gasto',
        'metodo_pago': 'Debito',
      };

      await supabase.from('gastos').insert([abonoCredito, pagoDebito]);

      _mostrarSnack('Pago registrado: ${_textoMonto(monto, ocultable: false)}');
    } catch (e) {
      _mostrarSnack('No se pudo registrar el pago: $e');
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

  Widget _toggleBoton({
    required IconData icono,
    required bool activo,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: activo ? Colors.teal.shade400 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icono,
          size: 18,
          color: activo ? Colors.white : Colors.grey.shade600,
        ),
      ),
    );
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
    final esEdicion = itemParaEditar != null;

    if (esEdicion) {
      final tipo = (itemParaEditar['tipo'] ?? 'Gasto').toString();
      _mostrarFormulario(tipo: tipo, itemParaEditar: itemParaEditar);
    } else {
      // Paso 1: Elegir tipo
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return Container(
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              MediaQuery.of(context).padding.bottom > 0
                  ? MediaQuery.of(context).padding.bottom
                  : 32,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1E2433)
                  : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle más prominente
                  Container(
                  width: 50,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(80),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                Text(
                  '¿Qué deseas registrar?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _tarjetaTipo(
                        icono: Icons.arrow_downward_rounded,
                        titulo: 'Gasto',
                        color: Colors.red,
                        onTap: () {
                          Navigator.pop(context);
                          _mostrarFormulario(tipo: 'Gasto');
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _tarjetaTipo(
                        icono: Icons.arrow_upward_rounded,
                        titulo: 'Ingreso',
                        color: Colors.green,
                        onTap: () {
                          Navigator.pop(context);
                          _mostrarFormulario(tipo: 'Ingreso');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _tarjetaTipo(
                        icono: Icons.swap_horiz_rounded,
                        titulo: 'Transferencia',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.pop(context);
                          _mostrarFormulario(tipo: 'Transferencia');
                        },
                      ),
                    ),
                    if (widget.settingsController.settings.hasCreditCard) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: _tarjetaTipo(
                          icono: Icons.auto_awesome,
                          titulo: 'Simular Compra',
                          color: Colors.deepPurple,
                          onTap: () {
                            Navigator.pop(context);
                            _mostrarSimuladorCompra();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                // Entrada rápida IA – ocupa toda la fila
                SizedBox(
                  width: double.infinity,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.pop(context);
                      _mostrarEntradaRapida();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors:
                              Theme.of(context).brightness == Brightness.dark
                              ? [
                                  const Color(0xFF312E81),
                                  const Color(0xFF1E1B4B),
                                ]
                              : [
                                  const Color(0xFFEDE9FE),
                                  const Color(0xFFE0E7FF),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.purple.shade700.withAlpha(80)
                              : Colors.purple.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.purpleAccent.shade100
                                : Colors.purple.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Entrada Rápida IA',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.purple.shade100
                                        : Colors.purple.shade900,
                                  ),
                                ),
                                Text(
                                  'Escribe o dicta tu gasto en lenguaje natural',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.purple.shade200
                                        : Colors.purple.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.mic,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.purple.shade200
                                : Colors.purple.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ),
          );
        },
      );
    }
  }

  Widget _tarjetaTipo({
    required IconData icono,
    required String titulo,
    required MaterialColor color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _ScaleTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        decoration: BoxDecoration(
          color: isDark
              ? color.shade900.withAlpha(60)
              : color.shade50.withAlpha(150),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? color.shade700.withAlpha(100)
                : color.shade200.withAlpha(150),
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? color.shade800.withAlpha(100) : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withAlpha(isDark ? 0 : 20),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                icono,
                size: 28,
                color: isDark ? color.shade200 : color.shade700,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isDark ? color.shade100 : color.shade900,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  ENTRADA RÁPIDA IA (Texto + Voz)
  // ═══════════════════════════════════════════════════════

  void _mostrarEntradaRapida() {
    final settings = widget.settingsController.settings;
    final quickController = TextEditingController();
    bool isProcessing = false;
    String? errorMsg;
    bool hasParsed = false;

    // Editable fields (populated after AI parse)
    final editItemCtrl = TextEditingController();
    final editMontoCtrl = TextEditingController();
    String editTipo = 'Gasto';
    String editCategoria = '';
    DateTime editFecha = DateTime.now();
    String editCuenta = settings.defaultAccount;
    String editMetodo = 'Debito';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final esGasto = editTipo == 'Gasto';
            final categoriasDisponibles = esGasto
                ? [...settings.activeCategories]
                : [...settings.activeIncomeCategories];
            if (categoriasDisponibles.isEmpty) {
              categoriasDisponibles.add(esGasto ? 'Varios' : 'Otros Ingresos');
            }
            if (editCategoria.isNotEmpty &&
                !categoriasDisponibles.contains(editCategoria)) {
              categoriasDisponibles.add(editCategoria);
            }
            final cuentasDisponibles = [...settings.activeAccounts];
            if (cuentasDisponibles.isEmpty) {
              cuentasDisponibles.add(settings.defaultAccount);
            }

            Future<void> procesarTexto(String texto) async {
              if (texto.trim().isEmpty) return;
              setStateSB(() {
                isProcessing = true;
                errorMsg = null;
                hasParsed = false;
              });

              final result = await _aiService.parseNaturalLanguage(
                texto,
                categoriasGasto: settings.activeCategories,
                categoriasIngreso: settings.activeIncomeCategories,
                cuentas: settings.activeAccounts,
                fechaHoy: DateTime.now().toIso8601String().split('T').first,
              );

              if (context.mounted) {
                if (result != null) {
                  editItemCtrl.text = result.item;
                  editMontoCtrl.text = result.monto.toString();
                  editTipo = result.tipo;
                  editCategoria = result.categoria;
                  editCuenta = result.cuenta ?? settings.defaultAccount;
                  editMetodo = result.metodoPago;
                  try {
                    editFecha = DateTime.parse(result.fecha);
                  } catch (_) {
                    editFecha = DateTime.now();
                  }
                  setStateSB(() {
                    isProcessing = false;
                    hasParsed = true;
                  });
                } else {
                  setStateSB(() {
                    isProcessing = false;
                    errorMsg =
                        'No pude entender. Intenta ser más específico, ej: "gasté 10 lucas en uber ayer"';
                  });
                }
              }
            }

            Future<void> toggleListening() async {
              // Voice input not available on desktop platforms
              if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
                setStateSB(
                  () => errorMsg =
                      'Entrada por voz no disponible en escritorio. Usa el campo de texto.',
                );
                return;
              }
              // On mobile, show not-available message (speech_to_text removed)
              setStateSB(
                () => errorMsg = 'Micrófono no disponible en este dispositivo',
              );
            }

            Future<void> guardar() async {
              final monto = int.tryParse(editMontoCtrl.text.trim()) ?? 0;
              if (monto <= 0) {
                setStateSB(() => errorMsg = 'El monto debe ser mayor a 0');
                return;
              }
              try {
                await supabase.from('gastos').insert({
                  'user_id': supabase.auth.currentUser!.id,
                  'fecha': editFecha.toIso8601String(),
                  'item': editItemCtrl.text.trim().isEmpty
                      ? 'Sin nombre'
                      : editItemCtrl.text.trim(),
                  'monto': monto,
                  'categoria': editCategoria,
                  'cuenta': editCuenta,
                  'tipo': editTipo,
                  'metodo_pago': editMetodo,
                });
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '✅ $editTipo registrado: ${editItemCtrl.text.trim()}',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  setStateSB(() => errorMsg = 'Error al guardar: $e');
                }
              }
            }

            final colorTipo = esGasto ? Colors.red : Colors.green;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.purple.shade900.withAlpha(80)
                                  : Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.auto_awesome,
                              color: isDark
                                  ? Colors.purpleAccent.shade100
                                  : Colors.purple.shade700,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Entrada Rápida IA',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Escribe o dicta tu gasto. Ej: "15 lucas en uber ayer"',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Input row
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: quickController,
                              autofocus: !hasParsed,
                              style: const TextStyle(fontSize: 16),
                              decoration: InputDecoration(
                                hintText: 'Escribe aquí…',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.white.withAlpha(15)
                                    : Colors.grey.shade100,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                              onSubmitted: procesarTexto,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: toggleListening,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.purple.shade700
                                    : Colors.purple.shade500,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.mic,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: isProcessing
                                ? null
                                : () => procesarTexto(quickController.text),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.tealAccent.shade700
                                    : Colors.teal,
                                shape: BoxShape.circle,
                              ),
                              child: isProcessing
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                            ),
                          ),
                        ],
                      ),

                      // Error
                      if (errorMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.red.shade900.withAlpha(50)
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            errorMsg!,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.red.shade200
                                  : Colors.red.shade800,
                            ),
                          ),
                        ),
                      ],

                      // Shimmer loading
                      if (isProcessing) ...[
                        const SizedBox(height: 16),
                        Shimmer.fromColors(
                          baseColor: isDark
                              ? Colors.purple.shade800
                              : Colors.purple.shade100,
                          highlightColor: isDark
                              ? Colors.purple.shade600
                              : Colors.purple.shade50,
                          child: Container(
                            width: double.infinity,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],

                      // ── Editable parsed result ──
                      if (hasParsed) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? Colors.purple.shade700.withAlpha(80)
                                  : Colors.purple.shade200,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Tipo toggle
                              Row(
                                children: [
                                  _toggleChip(
                                    label: 'Gasto',
                                    selected: editTipo == 'Gasto',
                                    color: Colors.red,
                                    isDark: isDark,
                                    onTap: () => setStateSB(() {
                                      editTipo = 'Gasto';
                                      editCategoria =
                                          settings.activeCategories.isNotEmpty
                                          ? settings.activeCategories.first
                                          : 'Varios';
                                    }),
                                  ),
                                  const SizedBox(width: 8),
                                  _toggleChip(
                                    label: 'Ingreso',
                                    selected: editTipo == 'Ingreso',
                                    color: Colors.green,
                                    isDark: isDark,
                                    onTap: () => setStateSB(() {
                                      editTipo = 'Ingreso';
                                      editCategoria =
                                          settings
                                              .activeIncomeCategories
                                              .isNotEmpty
                                          ? settings
                                                .activeIncomeCategories
                                                .first
                                          : 'Otros Ingresos';
                                    }),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Item
                              TextField(
                                controller: editItemCtrl,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Concepto',
                                  prefixIcon: Icon(
                                    Icons.edit_note,
                                    color: colorTipo.shade400,
                                    size: 20,
                                  ),
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? Colors.white.withAlpha(10)
                                      : Colors.grey.shade50,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Monto
                              TextField(
                                controller: editMontoCtrl,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  color: colorTipo.shade400,
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Monto',
                                  prefixIcon: Icon(
                                    Icons.attach_money,
                                    color: colorTipo.shade400,
                                    size: 20,
                                  ),
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: colorTipo.withAlpha(
                                    isDark ? 15 : 8,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Categoría dropdown
                              DropdownButtonFormField<String>(
                                initialValue:
                                    categoriasDisponibles.contains(
                                      editCategoria,
                                    )
                                    ? editCategoria
                                    : categoriasDisponibles.first,
                                decoration: InputDecoration(
                                  labelText: 'Categoría',
                                  prefixIcon: Icon(
                                    Icons.label_outline,
                                    color: colorTipo.shade400,
                                    size: 20,
                                  ),
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? Colors.white.withAlpha(10)
                                      : Colors.grey.shade50,
                                ),
                                items: categoriasDisponibles
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setStateSB(() => editCategoria = v);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),

                              // Fecha
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: editFecha,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                  );
                                  if (picked != null) {
                                    setStateSB(() => editFecha = picked);
                                  }
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withAlpha(10)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: 18,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '${editFecha.day.toString().padLeft(2, '0')}/${editFecha.month.toString().padLeft(2, '0')}/${editFecha.year}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.grey.shade200
                                              : Colors.grey.shade800,
                                        ),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        color: Colors.grey.shade500,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Cuenta dropdown
                              DropdownButtonFormField<String>(
                                initialValue:
                                    cuentasDisponibles.contains(editCuenta)
                                    ? editCuenta
                                    : cuentasDisponibles.first,
                                decoration: InputDecoration(
                                  labelText: 'Cuenta',
                                  prefixIcon: Icon(
                                    Icons.account_balance,
                                    color: Colors.grey.shade500,
                                    size: 20,
                                  ),
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? Colors.white.withAlpha(10)
                                      : Colors.grey.shade50,
                                ),
                                items: cuentasDisponibles
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setStateSB(() => editCuenta = v);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),

                              // Método de pago toggle
                              if (settings.hasCreditCard) ...[
                                Row(
                                  children: [
                                    _toggleChip(
                                      label: 'Débito',
                                      selected: editMetodo == 'Debito',
                                      color: Colors.blue,
                                      isDark: isDark,
                                      icon: Icons.account_balance_wallet,
                                      onTap: () => setStateSB(
                                        () => editMetodo = 'Debito',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _toggleChip(
                                      label: 'Crédito',
                                      selected: editMetodo == 'Credito',
                                      color: Colors.orange,
                                      isDark: isDark,
                                      icon: Icons.credit_card,
                                      onTap: () => setStateSB(
                                        () => editMetodo = 'Credito',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ] else
                                const SizedBox(height: 4),

                              // Guardar
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: guardar,
                                  icon: const Icon(
                                    Icons.check_circle_outline,
                                    size: 18,
                                  ),
                                  label: const Text('Guardar'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: esGasto
                                        ? Colors.red.shade500
                                        : Colors.green.shade600,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _toggleChip({
    required String label,
    required bool selected,
    required MaterialColor color,
    required bool isDark,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withAlpha(isDark ? 50 : 30)
              : (isDark ? Colors.white.withAlpha(8) : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? color.withAlpha(isDark ? 120 : 80)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected
                    ? (isDark ? color.shade200 : color.shade700)
                    : Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected
                    ? (isDark ? color.shade200 : color.shade700)
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarFormulario({
    required String tipo,
    Map<String, dynamic>? itemParaEditar,
  }) {
    final settings = widget.settingsController.settings;
    final esEdicion = itemParaEditar != null;
    final esGasto = tipo == 'Gasto';
    final esTransferencia = tipo == 'Transferencia';

    DateTime fechaSeleccionada;

    final categoriasDisponibles = esGasto
        ? [...settings.activeCategories]
        : [...settings.activeIncomeCategories];
    if (categoriasDisponibles.isEmpty) {
      categoriasDisponibles.add(esGasto ? 'Varios' : 'Otros Ingresos');
    }

    final cuentasDisponibles = [...settings.activeAccounts];
    if (cuentasDisponibles.isEmpty) {
      cuentasDisponibles.add(settings.defaultAccount);
    }

    String cuentaSeleccionada;
    String? cuentaDestinoSeleccionada;
    String? categoriaSeleccionada;
    bool esCredito = false;
    bool esFantasmaForm = false;
    bool esCompartido = false;
    final amigosCompartidos = <Map<String, dynamic>>[];
    final nombreControllers = <TextEditingController>[];
    final montoControllers = <TextEditingController>[];

    if (esEdicion) {
      _itemController.text = (itemParaEditar['item'] ?? '').toString();
      _detalleController.text = (itemParaEditar['detalle'] ?? '').toString();
      _montoController.text = (itemParaEditar['monto'] ?? '').toString();
      fechaSeleccionada = DateTime.parse(itemParaEditar['fecha']);

      final cat = (itemParaEditar['categoria'] ?? '').toString();
      if (cat.isNotEmpty && !categoriasDisponibles.contains(cat)) {
        categoriasDisponibles.add(cat);
      }
      categoriaSeleccionada = cat.isNotEmpty
          ? cat
          : categoriasDisponibles.first;

      cuentaSeleccionada = (itemParaEditar['cuenta'] ?? settings.defaultAccount)
          .toString();
      if (!cuentasDisponibles.contains(cuentaSeleccionada)) {
        cuentasDisponibles.add(cuentaSeleccionada);
      }

      final metodo = (itemParaEditar['metodo_pago'] ?? 'Debito').toString();
      esCredito = metodo == 'Credito';
      esFantasmaForm = (itemParaEditar['estado'] ?? 'real') == 'fantasma';
    } else {
      _itemController.clear();
      _detalleController.clear();
      _montoController.clear();
      fechaSeleccionada = DateTime.now();
      categoriaSeleccionada = categoriasDisponibles.first;
      cuentaSeleccionada = settings.defaultAccount;
      if (esTransferencia && cuentasDisponibles.length > 1) {
        cuentaDestinoSeleccionada = cuentasDisponibles.firstWhere(
          (c) => c != cuentaSeleccionada,
          orElse: () => cuentasDisponibles.last,
        );
      } else if (esTransferencia) {
        cuentaDestinoSeleccionada = cuentaSeleccionada;
      }
      esCredito = false;
    }

    final colorTipo = esTransferencia
        ? Colors.blue
        : (esGasto ? Colors.red : Colors.green);

    // ── AI Auto-Categorization ──
    Timer? aiDebounce;
    bool aiSuggesting = false;
    bool aiSuggested = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            Future<void> guardar() async {
              final montoStr = _montoController.text.trim();
              if (montoStr.isEmpty) return;
              final monto = int.tryParse(montoStr) ?? 0;

              final item = _itemController.text.trim();
              final detalle = _detalleController.text.trim();

              if (esTransferencia) {
                if (cuentaDestinoSeleccionada == cuentaSeleccionada) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Las cuentas deben ser diferentes'),
                      ),
                    );
                  }
                  return;
                }

                try {
                  // 1. Salida de Origen
                  await supabase.from('gastos').insert({
                    'user_id': supabase.auth.currentUser!.id,
                    'fecha': fechaSeleccionada.toIso8601String(),
                    'item':
                        'Transf. a $cuentaDestinoSeleccionada', // Mejor descripción automática
                    'detalle': detalle,
                    'monto': monto,
                    'categoria': 'Transferencia',
                    'cuenta': cuentaSeleccionada,
                    'tipo': 'Gasto', // Para que reste saldo
                    'metodo_pago': 'Debito',
                  });

                  // 2. Entrada a Destino
                  await supabase.from('gastos').insert({
                    'user_id': supabase.auth.currentUser!.id,
                    'fecha': fechaSeleccionada.toIso8601String(),
                    'item': 'Transf. desde $cuentaSeleccionada',
                    'detalle': detalle,
                    'monto': monto,
                    'categoria': 'Transferencia',
                    'cuenta': cuentaDestinoSeleccionada, // Cuenta destino
                    'tipo': 'Ingreso', // Para que sume saldo
                    'metodo_pago': 'Debito',
                  });

                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al transferir: $e')),
                    );
                  }
                }
                return;
              }

              final categoria =
                  categoriaSeleccionada ??
                  (esGasto ? 'Varios' : 'Otros Ingresos');
              final metodo = esCredito ? 'Credito' : 'Debito';

              try {
                if (esEdicion) {
                  await supabase
                      .from('gastos')
                      .update({
                        'fecha': fechaSeleccionada.toIso8601String(),
                        'item': item.isEmpty ? 'Sin nombre' : item,
                        'detalle': detalle,
                        'monto': monto,
                        'categoria': categoria,
                        'cuenta': cuentaSeleccionada,
                        'metodo_pago': metodo,
                        'estado': esFantasmaForm ? 'fantasma' : 'real',
                      })
                      .eq('id', itemParaEditar['id'] as int);
                } else {
                  int montoReal = monto;
                  int montoAmigos = 0;
                  List<Map<String, dynamic>> amigosData = [];

                  if (esGasto && esCompartido && amigosCompartidos.isNotEmpty) {
                    for (int i = 0; i < amigosCompartidos.length; i++) {
                      final n = nombreControllers[i].text.trim();
                      final m =
                          int.tryParse(montoControllers[i].text.trim()) ?? 0;
                      if (n.isNotEmpty && m > 0) {
                        montoAmigos += m;
                        amigosData.add({
                          'persona': n,
                          'monto': m,
                          'pagado': false,
                        });
                      }
                    }
                    if (montoAmigos > 0) {
                      montoReal = monto - montoAmigos;
                      if (montoReal < 0) montoReal = 0;
                    }
                  }

                  final result = await supabase
                      .from('gastos')
                      .insert({
                        'user_id': supabase.auth.currentUser!.id,
                        'fecha': fechaSeleccionada.toIso8601String(),
                        'item': item.isEmpty ? 'Sin nombre' : item,
                        'detalle': detalle,
                        // Guardamos SOLO el gasto real del usuario (Opción C)
                        'monto': montoReal,
                        'categoria': categoria,
                        'cuenta': cuentaSeleccionada,
                        'tipo': tipo,
                        'metodo_pago': metodo,
                        'estado': esFantasmaForm ? 'fantasma' : 'real',
                      })
                      .select()
                      .single();

                  if (montoAmigos > 0 && amigosData.isNotEmpty) {
                    final gastoId = result['id'];

                    // 1. Insertar transacción "espejo/préstamo" en gastos para balancear la cuenta bancaria
                    await supabase.from('gastos').insert({
                      'user_id': supabase.auth.currentUser!.id,
                      'fecha': fechaSeleccionada.toIso8601String(),
                      'item':
                          'Por Cobrar: ${item.isEmpty ? 'Gasto Compartido' : item}',
                      'detalle': 'Deuda de amigos',
                      'monto': montoAmigos,
                      'categoria': 'Cuentas por Cobrar',
                      'cuenta': cuentaSeleccionada,
                      'tipo': 'Gasto',
                      'metodo_pago': metodo,
                    });

                    // 2. Insertar los detalles de los amigos en gastos_compartidos
                    for (final a in amigosData) {
                      a['user_id'] = supabase.auth.currentUser!.id;
                      a['gasto_id'] = gastoId;
                    }
                    await supabase
                        .from('gastos_compartidos')
                        .insert(amigosData);
                  }
                }
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? colorTipo.shade900.withAlpha(80)
                                  : colorTipo.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              esGasto
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? colorTipo.shade200
                                  : colorTipo.shade700,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            esEdicion ? 'Editar $tipo' : 'Nuevo $tipo',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Concepto
                      TextField(
                        controller: _itemController,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: '¿En qué se usó?',
                          labelText: 'Concepto',
                          prefixIcon: Icon(
                            Icons.edit_note,
                            color: colorTipo.shade400,
                          ),
                          suffixIcon: aiSuggesting
                              ? Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.purple.shade300,
                                    ),
                                  ),
                                )
                              : aiSuggested
                              ? Icon(
                                  Icons.auto_awesome,
                                  size: 18,
                                  color: Colors.purple.shade300,
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withAlpha(15)
                              : Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onChanged: !esTransferencia && !esEdicion
                            ? (value) {
                                aiDebounce?.cancel();
                                aiDebounce = Timer(
                                  const Duration(milliseconds: 600),
                                  () async {
                                    if (value.trim().length < 3) return;
                                    setStateSB(() => aiSuggesting = true);
                                    final suggested = await _aiService
                                        .suggestCategory(
                                          value.trim(),
                                          categoriasDisponibles,
                                        );
                                    if (suggested != null && context.mounted) {
                                      setStateSB(() {
                                        categoriaSeleccionada = suggested;
                                        aiSuggesting = false;
                                        aiSuggested = true;
                                      });
                                    } else if (context.mounted) {
                                      setStateSB(() => aiSuggesting = false);
                                    }
                                  },
                                );
                              }
                            : null,
                      ),
                      const SizedBox(height: 14),

                      // Detalle
                      TextField(
                        controller: _detalleController,
                        decoration: InputDecoration(
                          hintText: 'Notas adicionales...',
                          labelText: 'Detalle (opcional)',
                          prefixIcon: Icon(
                            Icons.description_outlined,
                            color: colorTipo.shade400,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withAlpha(15)
                              : Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        maxLines: 2,
                        minLines: 1,
                      ),
                      const SizedBox(height: 14),

                      // Monto
                      TextField(
                        controller: _montoController,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: colorTipo.shade400,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Monto',
                          prefixIcon: Icon(
                            Icons.numbers_rounded,
                            color: colorTipo.shade400,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: colorTipo.withAlpha(isDark ? 20 : 10),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Categoría label
                      if (!esTransferencia) ...[
                        const Text(
                          'Categoría',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: categoriasDisponibles.map((cat) {
                            final isSelected = categoriaSeleccionada == cat;
                            return ChoiceChip(
                              avatar: _iconoCategoria(
                                cat,
                                size: 18,
                                color: isSelected
                                    ? Colors.white
                                    : colorTipo.shade600,
                              ),
                              label: Text(cat),
                              selected: isSelected,
                              selectedColor: colorTipo.shade400,
                              backgroundColor:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade100,
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.grey.shade300
                                          : Colors.black87),
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  setStateSB(() => categoriaSeleccionada = cat);
                                }
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Fecha y Cuenta
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: fechaSeleccionada,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (picked != null) {
                                  setStateSB(() => fechaSeleccionada = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Fecha',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? Colors.white.withAlpha(15)
                                      : Colors.grey.shade100,
                                  suffixIcon: Icon(
                                    Icons.calendar_month_rounded,
                                    size: 18,
                                    color: colorTipo.shade400,
                                  ),
                                  isDense: true,
                                ),
                                child: Text(
                                  '${fechaSeleccionada.day}/${fechaSeleccionada.month}/${fechaSeleccionada.year}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: cuentaSeleccionada,
                              decoration: InputDecoration(
                                labelText: esTransferencia
                                    ? 'Cuenta Origen'
                                    : 'Cuenta',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.white.withAlpha(15)
                                    : Colors.grey.shade100,
                                isDense: true,
                              ),
                              items: cuentasDisponibles
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(
                                        c,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setStateSB(() => cuentaSeleccionada = value);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (esTransferencia) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: cuentaDestinoSeleccionada,
                          decoration: InputDecoration(
                            labelText: 'Cuenta Destino',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey.shade900
                                : Colors.grey.shade50,
                            isDense: true,
                          ),
                          items: cuentasDisponibles
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setStateSB(() => cuentaDestinoSeleccionada = value);
                          },
                        ),
                      ] else if (settings.hasCreditCard) ...[
                        const SizedBox(height: 12),
                        // Método de pago
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              label: Text('Débito'),
                              icon: Icon(
                                Icons.account_balance_wallet,
                                size: 18,
                              ),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              label: Text('Crédito'),
                              icon: Icon(Icons.credit_card, size: 18),
                            ),
                          ],
                          selected: {esCredito},
                          onSelectionChanged: (s) =>
                              setStateSB(() => esCredito = s.first),
                          style: ButtonStyle(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                      if (esGasto) ...[
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('Compartir gasto con amigos'),
                          value: esCompartido,
                          onChanged: (val) {
                            setStateSB(() {
                              esCompartido = val;
                              if (val && amigosCompartidos.isEmpty) {
                                amigosCompartidos.add({
                                  'nombre': '',
                                  'monto': '',
                                });
                                nombreControllers.add(TextEditingController());
                                montoControllers.add(TextEditingController());
                              }
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: colorTipo.shade400,
                        ),
                        if (esCompartido) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Amigos',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () {
                                        final montoTotal =
                                            int.tryParse(
                                              _montoController.text.trim(),
                                            ) ??
                                            0;
                                        if (montoTotal > 0 &&
                                            amigosCompartidos.isNotEmpty) {
                                          final partes =
                                              amigosCompartidos.length +
                                              1; // yo + amigos
                                          final porPersona =
                                              (montoTotal / partes).round();
                                          setStateSB(() {
                                            for (
                                              int i = 0;
                                              i < amigosCompartidos.length;
                                              i++
                                            ) {
                                              amigosCompartidos[i]['monto'] =
                                                  porPersona.toString();
                                              montoControllers[i].text =
                                                  porPersona.toString();
                                            }
                                          });
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.pie_chart,
                                        size: 16,
                                      ),
                                      label: const Text('Partes iguales'),
                                    ),
                                  ],
                                ),
                                ...amigosCompartidos.asMap().entries.map((
                                  entry,
                                ) {
                                  final idx = entry.key;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: TextField(
                                            controller: nombreControllers[idx],
                                            decoration: const InputDecoration(
                                              hintText: 'Nombre',
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 1,
                                          child: TextField(
                                            controller: montoControllers[idx],
                                            decoration: const InputDecoration(
                                              hintText: 'Monto',
                                              prefixText: '\$ ',
                                              isDense: true,
                                            ),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle,
                                            color: Colors.red,
                                          ),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.only(
                                            left: 8,
                                          ),
                                          onPressed: () {
                                            HapticFeedback.lightImpact();
                                            setStateSB(() {
                                              amigosCompartidos.removeAt(idx);
                                              nombreControllers[idx].dispose();
                                              nombreControllers.removeAt(idx);
                                              montoControllers[idx].dispose();
                                              montoControllers.removeAt(idx);
                                              if (amigosCompartidos.isEmpty) {
                                                esCompartido = false;
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                TextButton.icon(
                                  onPressed: () {
                                    setStateSB(() {
                                      amigosCompartidos.add({
                                        'nombre': '',
                                        'monto': '',
                                      });
                                      nombreControllers.add(
                                        TextEditingController(),
                                      );
                                      montoControllers.add(
                                        TextEditingController(),
                                      );
                                    });
                                  },
                                  icon: const Icon(Icons.add),
                                  label: const Text('Agregar amigo'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 20),

                      // Toggle: Movimiento Proyectado
                      if (!esTransferencia) ...[
                        GestureDetector(
                          onTap: () => setStateSB(
                            () => esFantasmaForm = !esFantasmaForm,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: esFantasmaForm
                                  ? (isDark
                                        ? Colors.purple.shade900.withAlpha(80)
                                        : Colors.purple.shade50)
                                  : (isDark
                                        ? Colors.white.withAlpha(8)
                                        : Colors.grey.shade50),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: esFantasmaForm
                                    ? (isDark
                                          ? Colors.purple.shade600
                                          : Colors.purple.shade200)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Mov. proyectado',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: esFantasmaForm
                                        ? (isDark
                                              ? Colors.purpleAccent.shade100
                                              : Colors.purple.shade800)
                                        : (isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade600),
                                  ),
                                ),
                                const Spacer(),
                                Switch.adaptive(
                                  value: esFantasmaForm,
                                  onChanged: (v) =>
                                      setStateSB(() => esFantasmaForm = v),
                                  thumbColor: WidgetStateProperty.resolveWith(
                                    (states) =>
                                        states.contains(WidgetState.selected)
                                        ? Colors.purple.shade400
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // Botón guardar
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: guardar,
                          icon: Icon(esEdicion ? Icons.save : Icons.check),
                          label: Text(
                            esEdicion ? 'Guardar cambios' : 'Registrar $tipo',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorTipo.shade400,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
    final rangosCredito = _obtenerRangosCicloCredito(
      settings,
      referenceDate: now,
    );
    final curStart = rangosCredito['curStart']!;
    final curEnd = rangosCredito['curEnd']!;
    final nowEnd = rangosCredito['nowEnd']!;

    final creditExpenses = todosLosDatos
        .where(
          (m) =>
              (m['metodo_pago'] ?? 'Debito') == 'Credito' &&
              (m['tipo'] == 'Gasto'),
        )
        .toList();
    final creditAbonos = todosLosDatos
        .where(
          (m) =>
              (m['metodo_pago'] ?? 'Debito') == 'Credito' &&
              (m['tipo'] == 'Ingreso'),
        )
        .toList();
    final movimientosCreditoPorCuenta = _agruparMovimientosCreditoPorCuenta(
      todosLosDatos,
    );

    var porFacturarPendiente = 0;
    var facturadoPendiente = 0;
    var pagosPeriodo = 0;
    for (final movimientosCuenta in movimientosCreditoPorCuenta.values) {
      final resumen = _calcularResumenDeudaCreditoCuenta(
        movimientosCuenta: movimientosCuenta,
        cycleStart: curStart,
        nowEnd: nowEnd,
      );
      facturadoPendiente += resumen['facturadoPendiente'] ?? 0;
      porFacturarPendiente += resumen['porFacturarPendiente'] ?? 0;
      pagosPeriodo += resumen['pagos'] ?? 0;
    }

    final cuentasCredito = <String>[];
    for (final mov in todosLosDatos) {
      if ((mov['metodo_pago'] ?? 'Debito') != 'Credito') continue;
      final cuenta = (mov['cuenta'] ?? '').toString().trim();
      if (cuenta.isEmpty || cuentasCredito.contains(cuenta)) continue;
      cuentasCredito.add(cuenta);
    }
    if (cuentasCredito.isEmpty) {
      for (final acc in settings.activeAccounts) {
        if (_esCuentaCreditoPorNombre(acc)) {
          cuentasCredito.add(acc);
        }
      }
    }
    if (cuentasCredito.isEmpty && settings.activeAccounts.isNotEmpty) {
      cuentasCredito.add(settings.defaultAccount);
    }

    // --- Fin Lógica ---

    // Countdown al día de vencimiento
    final nextDue = _proximoVencimientoTarjeta(now, dueDay);
    final diasAlVencimiento = nextDue
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final esMesActualVisualizado =
        _mesVisualizado.year == now.year && _mesVisualizado.month == now.month;
    
    final fechaCorteFacturado = curStart.subtract(const Duration(days: 1));
    final vencimientoFacturado = _proximoVencimientoTarjeta(fechaCorteFacturado, dueDay);
    final vencimientoFacturadoFinDia = _finDelDia(vencimientoFacturado);
    
    final mostrarFacturadosYAbonos =
        esMesActualVisualizado && !now.isAfter(vencimientoFacturadoFinDia);

    // Filtrar movimientos de cada ciclo para las listas de detalle
    final movimientosPorFacturar = creditExpenses.where((m) {
      final d = DateTime.parse(m['fecha']);
      return !d.isBefore(curStart) && !d.isAfter(nowEnd);
    }).toList();
    final movimientosFacturados = creditExpenses.where((m) {
      final d = DateTime.parse(m['fecha']);
      return d.isBefore(curStart);
    }).toList();
    final movimientosAbonos =
        creditAbonos.where((m) {
          final d = DateTime.parse(m['fecha']);
          return !d.isAfter(nowEnd);
        }).toList()..sort((a, b) {
          final fa = DateTime.parse((a['fecha'] ?? '').toString());
          final fb = DateTime.parse((b['fecha'] ?? '').toString());
          return fb.compareTo(fa);
        });
    movimientosFacturados.sort((a, b) {
      final fa = DateTime.parse((a['fecha'] ?? '').toString());
      final fb = DateTime.parse((b['fecha'] ?? '').toString());
      return fb.compareTo(fa);
    });
    final movimientosFacturadosVisibles = mostrarFacturadosYAbonos
        ? movimientosFacturados
        : <Map<String, dynamic>>[];
    final movimientosAbonosVisibles = mostrarFacturadosYAbonos
        ? movimientosAbonos
        : <Map<String, dynamic>>[];
    final facturadoPendienteVisible = mostrarFacturadosYAbonos
        ? facturadoPendiente
        : 0;
    final pagosPeriodoVisible = mostrarFacturadosYAbonos ? pagosPeriodo : 0;

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
    final startingWeekday = firstDayOfMonth.weekday;
    final offset = startingWeekday - 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Countdown badge al vencimiento
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: diasAlVencimiento <= 1
                  ? Colors.red.shade50
                  : diasAlVencimiento <= 3
                  ? Colors.orange.shade50
                  : Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: diasAlVencimiento <= 1
                    ? Colors.red.shade200
                    : diasAlVencimiento <= 3
                    ? Colors.orange.shade200
                    : Colors.green.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  diasAlVencimiento <= 1
                      ? Icons.warning_amber_rounded
                      : Icons.schedule,
                  color: diasAlVencimiento <= 1
                      ? Colors.red.shade700
                      : diasAlVencimiento <= 3
                      ? Colors.orange.shade700
                      : Colors.green.shade700,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    diasAlVencimiento == 0
                        ? '¡Hoy vence tu tarjeta!'
                        : diasAlVencimiento == 1
                        ? 'Tu tarjeta vence mañana'
                        : 'Faltan $diasAlVencimiento días para el vencimiento (día $dueDay)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: diasAlVencimiento <= 1
                          ? Colors.red.shade800
                          : diasAlVencimiento <= 3
                          ? Colors.orange.shade800
                          : Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Tarjetas de Resumen
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.indigo.withValues(alpha: 0.15)
                        : Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.indigo.shade900
                          : Colors.indigo.shade100,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Por Facturar',
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.indigo.shade200
                              : Colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _textoMonto(porFacturarPendiente),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.indigo.shade100
                              : Colors.indigo,
                        ),
                      ),
                      Text(
                        '${curStart.day}/${curStart.month} - ${curEnd.day}/${curEnd.month}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.indigo.shade300
                              : Colors.indigo.shade300,
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
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.orange.withValues(alpha: 0.15)
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.orange.shade900
                          : Colors.orange.shade100,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Facturado',
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.deepOrange.shade200
                              : Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _textoMonto(facturadoPendienteVisible),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.deepOrange.shade100
                              : Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pagos/abonos: ${_textoMonto(pagosPeriodoVisible)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.green.shade200
                              : Colors.green.shade700,
                        ),
                      ),
                      Text(
                        'Anterior a ${curStart.day}/${curStart.month}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.deepOrange.shade300
                              : Colors.deepOrange.shade300,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Botón Cerrar Ciclo
          Builder(
            builder: (_) {
              final yaSeManualClose =
                  settings.lastManualBillingClose != null &&
                  settings.lastManualBillingClose!.isNotEmpty &&
                  (() {
                    final parsed = DateTime.tryParse(
                      settings.lastManualBillingClose!,
                    );
                    return parsed != null &&
                        parsed.year == now.year &&
                        parsed.month == now.month;
                  })();
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Column(
                children: [
                  if (yaSeManualClose)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(isDark ? 25 : 12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.withAlpha(40)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, size: 16, color: Colors.green.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ciclo cerrado manualmente el ${settings.lastManualBillingClose}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.green.shade200 : Colors.green.shade800,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              widget.settingsController.setLastManualBillingClose(null);
                            },
                            child: Icon(Icons.undo, size: 16, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      if (!yaSeManualClose && porFacturarPendiente > 0)
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.amber.shade200 : Colors.amber.shade800,
                              side: BorderSide(color: isDark ? Colors.amber.shade700 : Colors.amber.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => _confirmarCierreCiclo(porFacturarPendiente),
                            icon: const Icon(Icons.event_available, size: 20),
                            label: const Text('Cerrar ciclo ahora', style: TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      if (!yaSeManualClose && porFacturarPendiente > 0)
                        const SizedBox(width: 8),
                      if (yaSeManualClose || porFacturarPendiente <= 0)
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.amber.shade200 : Colors.amber.shade800,
                              side: BorderSide(color: isDark ? Colors.amber.shade700 : Colors.amber.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _mostrarConfiguracionFechas,
                            icon: const Icon(Icons.settings, size: 20),
                            label: const Text('Configurar fechas de TC', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        )
                      else
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? Colors.amber.shade200 : Colors.amber.shade800,
                            side: BorderSide(color: isDark ? Colors.amber.shade700 : Colors.amber.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          ),
                          onPressed: _mostrarConfiguracionFechas,
                          child: const Icon(Icons.settings, size: 20),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (mostrarFacturadosYAbonos)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800
                      : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.payments_outlined,
                        color: Colors.teal.shade600,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Pagos de tarjeta',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Facturado pendiente: ${_textoMonto(facturadoPendienteVisible)}',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade300
                          : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            cuentasCredito.isEmpty ||
                                facturadoPendienteVisible <= 0
                            ? null
                            : () => _mostrarDialogoAbonoTarjeta(
                                cuentasCredito: cuentasCredito,
                                itemAbono: _itemPagoFacturadoTarjeta,
                                montoInicial: facturadoPendienteVisible,
                                titulo: 'Pagar monto facturado',
                              ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Pagar facturado'),
                      ),
                      OutlinedButton.icon(
                        onPressed: cuentasCredito.isEmpty
                            ? null
                            : () => _mostrarDialogoAbonoTarjeta(
                                cuentasCredito: cuentasCredito,
                                itemAbono: _itemAbonoTarjeta,
                                titulo: 'Registrar abono',
                              ),
                        icon: const Icon(Icons.add_card),
                        label: const Text('Registrar abono'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800
                      : Colors.grey.shade200,
                ),
              ),
              child: const Text(
                'Facturados y abonos solo se muestran en el periodo actual antes del vencimiento.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : Colors.grey.shade200,
              ),
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
              color: Theme.of(context).cardColor,
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
                      final paid = (c['paidInstallments'] as int?) ?? 0;
                      final total = c['installments'] as int;
                      if (paid >= total) return false; // already completed
                      final start = DateTime.parse(c['startDate']);
                      final end = DateTime(
                        start.year,
                        start.month + total,
                        start.day,
                      );
                      return day == paymentDay &&
                          !date.isBefore(start) &&
                          date.isBefore(end);
                    }).toList();

                    // Chequear gastos e ingresos recurrentes/planificados
                    final gastosRecurrentesHoy = <Map<String, dynamic>>[];
                    final ingresosPlanificadosHoy = <Map<String, dynamic>>[];

                    for (final r in _recurrentes) {
                      final start = DateTime.parse(r['fecha_proximo_pago']);
                      final frecuencia = r['frecuencia'];
                      final tipo = r['tipo'] ?? 'Gasto';

                      // Solo mostramos desde la fecha programada en adelante
                      // (O si está vencido, start es anterior a hoy, date es start o futuro)
                      // Pero para visualizar recurrentes futuros, queremos ver proyecciones.
                      // La lógica simple: si date >= start (ignorando hora) y coincide patrón.
                      final dateDate = DateTime(
                        date.year,
                        date.month,
                        date.day,
                      );
                      final startDate = DateTime(
                        start.year,
                        start.month,
                        start.day,
                      );

                      if (dateDate.isBefore(startDate)) continue;

                      bool coincide = false;
                      if (frecuencia == 'Mensual') {
                        coincide = date.day == start.day;
                      } else if (frecuencia == 'Semanal') {
                        final diff = dateDate.difference(startDate).inDays;
                        coincide = diff % 7 == 0;
                      } else if (frecuencia == 'Anual') {
                        coincide =
                            date.month == start.month && date.day == start.day;
                      }

                      if (coincide) {
                        if (tipo == 'Ingreso') {
                          ingresosPlanificadosHoy.add(r);
                        } else {
                          gastosRecurrentesHoy.add(r);
                        }
                      }
                    }

                    final hasCreditPayment = creditosHoy.isNotEmpty;
                    final hasRecurringExpense = gastosRecurrentesHoy.isNotEmpty;
                    final hasPlannedIncome = ingresosPlanificadosHoy.isNotEmpty;
                    final hasAnyRecurring =
                        hasRecurringExpense || hasPlannedIncome;

                    Color? bgColor;
                    Color textColor = Theme.of(context).colorScheme.onSurface;
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;

                    if (isToday) {
                      bgColor = isDark
                          ? Colors.blue.withValues(alpha: 0.2)
                          : Colors.blue.shade50;
                      textColor = isDark
                          ? Colors.blue.shade200
                          : Colors.blue.shade900;
                    }
                    if (isBilling) {
                      bgColor = isDark
                          ? Colors.indigo.withValues(alpha: 0.2)
                          : Colors.indigo.shade100;
                      textColor = isDark
                          ? Colors.indigo.shade200
                          : Colors.indigo.shade900;
                    }
                    if (isDue) {
                      bgColor = isDark
                          ? Colors.red.withValues(alpha: 0.2)
                          : Colors.red.shade100;
                      textColor = isDark
                          ? Colors.red.shade200
                          : Colors.red.shade900;
                    }
                    if (hasCreditPayment || hasAnyRecurring) {
                      if (!isDue && !isBilling && !isToday) {
                        int eventTypes = 0;
                        if (hasCreditPayment) eventTypes++;
                        if (hasRecurringExpense) eventTypes++;
                        if (hasPlannedIncome) eventTypes++;

                        if (eventTypes == 1) {
                          if (hasCreditPayment) {
                            bgColor = isDark
                                ? Colors.green.withValues(alpha: 0.2)
                                : Colors.green.shade100;
                            textColor = isDark
                                ? Colors.green.shade200
                                : Colors.green.shade900;
                          } else if (hasRecurringExpense) {
                            bgColor = isDark
                                ? Colors.purple.withValues(alpha: 0.2)
                                : Colors.purple.shade100;
                            textColor = isDark
                                ? Colors.purple.shade200
                                : Colors.purple.shade900;
                          } else if (hasPlannedIncome) {
                            bgColor = isDark
                                ? Colors.teal.withValues(alpha: 0.2)
                                : Colors.teal.shade100;
                            textColor = isDark
                                ? Colors.teal.shade200
                                : Colors.teal.shade900;
                          }
                        } else {
                          // Hay más de un tipo de evento
                          bgColor = isDark
                              ? Colors.amber.withValues(alpha: 0.2)
                              : Colors.amber.shade100;
                          textColor = isDark
                              ? Colors.amber.shade200
                              : Colors.amber.shade900;
                        }
                      }
                    }

                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        if (isBilling ||
                            isDue ||
                            hasCreditPayment ||
                            hasAnyRecurring) {
                          _mostrarEventosDelDia(
                            date,
                            isBilling,
                            isDue,
                            creditosHoy,
                            gastosRecurrentesHoy,
                            ingresosPlanificadosHoy,
                          );
                        }
                      },
                      child: Container(
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
                            Positioned(
                              bottom: 4,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (hasCreditPayment)
                                    Container(
                                      width: 4,
                                      height: 4,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade700,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  if (hasRecurringExpense)
                                    Container(
                                      width: 4,
                                      height: 4,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade700,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  if (hasPlannedIncome)
                                    Container(
                                      width: 4,
                                      height: 4,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade700,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _leyendaCalendario(
                      Colors.purple.shade100,
                      'Gasto Recurrente',
                    ),
                    _leyendaCalendario(
                      Colors.teal.shade100,
                      'Ingreso Planificado',
                    ),
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

          // --- Detalle de movimientos del ciclo actual (Por Facturar) ---
          const SizedBox(height: 24),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Row(
              children: [
                Icon(
                  Icons.receipt_long,
                  color: Colors.indigo.shade600,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Movimientos Por Facturar (${movimientosPorFacturar.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            children: movimientosPorFacturar.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Sin movimientos en este ciclo',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ]
                : movimientosPorFacturar.map((m) {
                    final fecha = DateTime.parse(m['fecha']);
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: _iconoCategoria(m['categoria'] ?? '', size: 20),
                      title: Text(m['item'] ?? 'Sin nombre'),
                      subtitle: Text(
                        '${fecha.day}/${fecha.month}/${fecha.year} · ${m['categoria'] ?? ''}',
                      ),
                      trailing: Text(
                        _textoMonto((m['monto'] as num).toInt()),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.indigo.shade700,
                        ),
                      ),
                    );
                  }).toList(),
          ),

          // --- Detalle de movimientos facturados y abonos ---
          if (mostrarFacturadosYAbonos)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Icon(
                    Icons.receipt,
                    color: Colors.deepOrange.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Movimientos Facturados (${movimientosFacturadosVisibles.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              children: movimientosFacturadosVisibles.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Sin movimientos facturados',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ]
                  : movimientosFacturadosVisibles.map((m) {
                      final fecha = DateTime.parse(m['fecha']);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: _iconoCategoria(
                          m['categoria'] ?? '',
                          size: 20,
                        ),
                        title: Text(m['item'] ?? 'Sin nombre'),
                        subtitle: Text(
                          '${fecha.day}/${fecha.month}/${fecha.year} · ${m['categoria'] ?? ''}',
                        ),
                        trailing: Text(
                          _textoMonto((m['monto'] as num).toInt()),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.deepOrange.shade700,
                          ),
                        ),
                      );
                    }).toList(),
            ),
          if (mostrarFacturadosYAbonos)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Icon(Icons.payments, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Abonos registrados (${movimientosAbonosVisibles.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              children: movimientosAbonosVisibles.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Sin abonos en el periodo actual',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ]
                  : movimientosAbonosVisibles.map((m) {
                      final fecha = DateTime.parse(m['fecha']);
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: Icon(
                          Icons.arrow_circle_down_rounded,
                          color: Colors.green.shade700,
                          size: 20,
                        ),
                        title: Text(m['item'] ?? _itemAbonoTarjeta),
                        subtitle: Text(
                          '${fecha.day}/${fecha.month}/${fecha.year} · ${(m['cuenta'] ?? '').toString()}',
                        ),
                        trailing: Text(
                          _textoMonto((m['monto'] as num).toInt()),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.green.shade700,
                          ),
                        ),
                      );
                    }).toList(),
            ),

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

  void _mostrarEventosDelDia(
    DateTime date,
    bool isBilling,
    bool isDue,
    List<Map<String, dynamic>> creditos,
    List<Map<String, dynamic>> gastos,
    List<Map<String, dynamic>> ingresos,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2433) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Eventos: ${date.day}/${date.month}/${date.year}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (isDue)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red.withValues(alpha: 0.2),
                    child: const Icon(Icons.warning, color: Colors.red),
                  ),
                  title: const Text('Vencimiento de Tarjeta'),
                ),
              if (isBilling)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.withValues(alpha: 0.2),
                    child: const Icon(Icons.receipt_long, color: Colors.indigo),
                  ),
                  title: const Text('Cierre de Facturación'),
                ),
              for (final c in creditos)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.withValues(alpha: 0.2),
                    child: const Icon(Icons.credit_card, color: Colors.green),
                  ),
                  title: Text(c['name']),
                  subtitle: Text('Crédito - Cuota'),
                  trailing: Text(
                    _textoMonto(c['amount'] as int),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              for (final g in gastos)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.purple.withValues(alpha: 0.2),
                    child: const Icon(
                      Icons.arrow_downward,
                      color: Colors.purple,
                    ),
                  ),
                  title: Text(g['item']),
                  subtitle: const Text('Gasto Recurrente'),
                  trailing: Text(
                    _textoMonto(g['monto'] as int),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ),
              for (final i in ingresos)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.withValues(alpha: 0.2),
                    child: const Icon(Icons.arrow_upward, color: Colors.teal),
                  ),
                  title: Text(i['item']),
                  subtitle: const Text('Ingreso Planificado'),
                  trailing: Text(
                    _textoMonto(i['monto'] as int),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        );
      },
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
      final paid = (c['paidInstallments'] as int?) ?? 0;
      final total = c['installments'] as int;
      if (paid >= total) continue; // already completed
      if (payDay <= daysInMonth) {
        final start = DateTime.parse(c['startDate']);
        final end = DateTime(start.year, start.month + total, start.day);
        final current = DateTime(
          _mesVisualizado.year,
          _mesVisualizado.month,
          payDay,
        );

        if (!current.isBefore(start) && current.isBefore(end)) {
          final cuotaSiguiente = paid + 1;
          eventos.add({
            'day': payDay,
            'title': '${c['name']} (Cuota $cuotaSiguiente/$total)',
            'monto': c['amount'],
            'color': Colors.green,
            'icon': Icons.account_balance,
          });
        }
      }
    }

    eventos.sort((a, b) => (a['day'] as int).compareTo(b['day'] as int));

    // Agregar también recurrentes del mes completo al listado inferior
    for (final r in _recurrentes) {
      final start = DateTime.parse(r['fecha_proximo_pago']);
      final frecuencia = r['frecuencia'];
      final tipo = r['tipo'] ?? 'Gasto';
      final monto = r['monto'] as int;
      final isIngreso = tipo == 'Ingreso';

      final dates = <int>[];

      if (frecuencia == 'Mensual') {
        dates.add(start.day);
      } else if (frecuencia == 'Anual' &&
          start.month == _mesVisualizado.month) {
        dates.add(start.day);
      } else if (frecuencia == 'Semanal') {
        // Encontrar todos los días en el mes que caen en este día de la semana
        for (int day = 1; day <= daysInMonth; day++) {
          final currentDate = DateTime(
            _mesVisualizado.year,
            _mesVisualizado.month,
            day,
          );
          final startDate = DateTime(start.year, start.month, start.day);
          if (!currentDate.isBefore(startDate)) {
            final diff = currentDate.difference(startDate).inDays;
            if (diff % 7 == 0) {
              dates.add(day);
            }
          }
        }
      }

      for (final payDay in dates) {
        if (payDay <= daysInMonth) {
          eventos.add({
            'day': payDay,
            'title': r['item'],
            'monto': monto,
            'color': isIngreso ? Colors.teal : Colors.purple,
            'icon': isIngreso ? Icons.arrow_upward : Icons.arrow_downward,
          });
        }
      }
    }

    final eventosPorDia = <int, List<Map<String, dynamic>>>{};
    for (final e in eventos) {
      final day = e['day'] as int;
      eventosPorDia.putIfAbsent(day, () => []).add(e);
    }

    final sortedDays = eventosPorDia.keys.toList()..sort();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: sortedDays.map((day) {
        final eventosDia = eventosPorDia[day]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Día $day',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: isDark ? const Color(0xFF1E2433) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < eventosDia.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          indent: 16,
                          endIndent: 16,
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200,
                        ),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (eventosDia[i]['color'] as Color)
                              .withAlpha(isDark ? 50 : 30),
                          child: Icon(
                            eventosDia[i]['icon'] as IconData,
                            color: eventosDia[i]['color'] as Color,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          eventosDia[i]['title'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        trailing: eventosDia[i].containsKey('monto')
                            ? Text(
                                _textoMonto(eventosDia[i]['monto'] as int),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.green.shade300
                                      : Colors.green.shade800,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _tarjetaCreditoConsumo(Map<String, dynamic> credit) {
    final totalCuotas = credit['installments'] as int;
    final montoCuota = credit['amount'] as int;
    final cuotasPagadas = (credit['paidInstallments'] as int?) ?? 0;
    final cuenta = (credit['cuenta'] ?? '').toString();
    final completado = cuotasPagadas >= totalCuotas;

    final progreso = totalCuotas > 0 ? cuotasPagadas / totalCuotas : 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2433) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 50 : 10),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
        border: isDark ? Border.all(color: Colors.grey.shade800) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  credit['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _textoMonto(montoCuota),
                  style: TextStyle(
                    color: isDark
                        ? Colors.green.shade300
                        : Colors.green.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Cuota $cuotasPagadas de $totalCuotas',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              if (cuenta.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.account_balance,
                  size: 12,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                ),
                const SizedBox(width: 3),
                Text(
                  cuenta,
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progreso,
              backgroundColor: isDark
                  ? Colors.grey.shade800
                  : Colors.grey.shade100,
              color: completado ? Colors.green : Colors.teal,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          if (completado)
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: Colors.green.shade400,
                ),
                const SizedBox(width: 6),
                Text(
                  'Crédito completado',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade400,
                  ),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Próximo pago: día ${credit['paymentDay']}',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.grey.shade400 : Colors.black87,
                  ),
                ),
                SizedBox(
                  height: 32,
                  child: ElevatedButton.icon(
                    onPressed: () => _pagarCuotaCredito(credit),
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(
                      'Pagar Cuota ${cuotasPagadas + 1}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _pagarCuotaCredito(Map<String, dynamic> credit) async {
    final totalCuotas = credit['installments'] as int;
    final montoCuota = credit['amount'] as int;
    final cuotasPagadas = (credit['paidInstallments'] as int?) ?? 0;
    final cuenta = (credit['cuenta'] ?? '').toString();
    final nombre = (credit['name'] ?? '').toString();
    final cuotaSiguiente = cuotasPagadas + 1;

    if (cuotaSiguiente > totalCuotas) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar Pago'),
          content: Text(
            '¿Pagar cuota $cuotaSiguiente de $totalCuotas de "$nombre"?\n\n'
            'Monto: ${formatoMoneda(montoCuota)}\n'
            'Cuenta: $cuenta',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('Pagar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) return;

    try {
      // Register expense in Supabase
      await supabase.from('gastos').insert({
        'user_id': supabase.auth.currentUser!.id,
        'fecha': DateTime.now().toIso8601String().split('T').first,
        'item': '$nombre (Cuota $cuotaSiguiente/$totalCuotas)',
        'monto': montoCuota,
        'categoria': 'Créditos',
        'cuenta': cuenta,
        'tipo': 'Gasto',
        'metodo_pago': 'Debito',
      });

      // Update paid installments
      final updated = Map<String, dynamic>.from(credit);
      updated['paidInstallments'] = cuotaSiguiente;
      widget.settingsController.updateConsumptionCredit(
        credit['id'] as String,
        updated,
      );

      if (mounted) {
        _mostrarSnack(
          '✅ Cuota $cuotaSiguiente pagada: ${formatoMoneda(montoCuota)} desde $cuenta',
        );
      }
    } catch (e) {
      if (mounted) {
        _mostrarSnack('Error al registrar pago: $e');
      }
    }
  }

  Future<void> _agregarCreditoConsumo() async {
    final settings = widget.settingsController.settings;
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final installmentsCtrl = TextEditingController();
    final paymentDayCtrl = TextEditingController();
    DateTime? startDate;
    String cuentaSeleccionada = settings.defaultAccount;

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
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: cuentaSeleccionada,
                      decoration: const InputDecoration(
                        labelText: 'Cuenta de cargo',
                        prefixIcon: Icon(Icons.account_balance),
                      ),
                      items: settings.activeAccounts.map((cuenta) {
                        return DropdownMenuItem(
                          value: cuenta,
                          child: Text(cuenta),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setStateSB(() => cuentaSeleccionada = value);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
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
                      'cuenta': cuentaSeleccionada,
                      'paidInstallments': 0,
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

  Future<void> _chequearRecurrentes() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await supabase
          .from('gastos_programados')
          .select()
          .eq('user_id', user.id)
          .eq('activo', true)
          .lte('fecha_proximo_pago', DateTime.now().toIso8601String());

      final List<Map<String, dynamic>> pendientes =
          List<Map<String, dynamic>>.from(response);

      if (pendientes.isEmpty) return;

      if (!mounted) return;

      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Gastos Recurrentes Pendientes'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Se encontraron los siguientes pagos vencidos:'),
                const SizedBox(height: 10),
                ...pendientes.map(
                  (p) => ListTile(
                    dense: true,
                    leading: Icon(
                      p['tipo'] == 'Ingreso'
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      color: p['tipo'] == 'Ingreso' ? Colors.green : Colors.red,
                    ),
                    title: Text(p['item']),
                    subtitle: Text(_textoMonto(p['monto'])),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Omitir por ahora'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar Todos'),
            ),
          ],
        ),
      );

      if (confirmar == true) {
        for (final p in pendientes) {
          // 1. Insertar movimiento
          await supabase.from('gastos').insert({
            'user_id': user.id,
            'fecha': DateTime.now()
                .toIso8601String(), // Se registra con fecha de HOY
            'item': p['item'],
            'monto': p['monto'],
            'categoria': p['categoria'],
            'cuenta': p['cuenta'],
            'tipo': p['tipo'],
          });

          // 2. Calcular nueva fecha
          final fechaActual = DateTime.parse(p['fecha_proximo_pago']);
          DateTime nuevaFecha = fechaActual;
          final frecuencia = p['frecuencia'];

          if (frecuencia == 'Mensual') {
            // Adds one month correctly handling end of month
            final newMonth = fechaActual.month + 1;
            final year = fechaActual.year + (newMonth > 12 ? 1 : 0);
            final month = newMonth > 12 ? 1 : newMonth;
            final day = fechaActual.day;
            // Handle overflow (e.g., Jan 31 -> Feb 28)
            final daysInNextMonth = DateUtils.getDaysInMonth(year, month);
            nuevaFecha = DateTime(
              year,
              month,
              day > daysInNextMonth ? daysInNextMonth : day,
            );
          } else if (frecuencia == 'Semanal') {
            nuevaFecha = fechaActual.add(const Duration(days: 7));
          } else if (frecuencia == 'Anual') {
            nuevaFecha = DateTime(
              fechaActual.year + 1,
              fechaActual.month,
              fechaActual.day,
            );
          } else if (frecuencia == 'Unico') {
            // Desactivar
            await supabase
                .from('gastos_programados')
                .update({'activo': false})
                .eq('id', p['id']);
            continue;
          }

          // 3. Actualizar recurrencia
          await supabase
              .from('gastos_programados')
              .update({'fecha_proximo_pago': nuevaFecha.toIso8601String()})
              .eq('id', p['id']);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Movimientos recurrentes registrados'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error chequeando recurrentes: $e');
    }
    _cargarRecurrentes();
  }

  Future<void> _cargarRecurrentes() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final response = await supabase
          .from('gastos_programados')
          .select()
          .eq('user_id', user.id)
          .eq('activo', true);
      if (mounted) {
        setState(() {
          _recurrentes = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error cargando recurrentes: $e');
    }
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

/// A reusable widget that provides a press-to-scale animation effect.
class _ScaleTap extends StatefulWidget {
  const _ScaleTap({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<_ScaleTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 250),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// ─── FORMULARIO META DE AHORRO ──────────────────────────────────────────────

class _FormularioMeta extends StatefulWidget {
  final Map<String, dynamic>? metaExistente;
  final String Function(num numero, {bool ocultar}) formatoMoneda;
  final Future<void> Function(Map<String, dynamic> data) onGuardar;

  const _FormularioMeta({
    this.metaExistente,
    required this.formatoMoneda,
    required this.onGuardar,
  });

  @override
  State<_FormularioMeta> createState() => _FormularioMetaState();
}

class _FormularioMetaState extends State<_FormularioMeta> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nombreController;
  late TextEditingController _montoMetaController;
  late TextEditingController _montoActualController;
  String? _emojiSeleccionado;
  DateTime? _fechaLimite;
  Color _colorSeleccionado = const Color(0xFF009688);
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final meta = widget.metaExistente;
    _nombreController = TextEditingController(
      text: meta?['nombre']?.toString() ?? '',
    );
    _montoMetaController = TextEditingController(
      text: meta?['monto_meta']?.toString() ?? '',
    );
    _montoActualController = TextEditingController(
      text: meta != null ? (meta['monto_actual'] ?? 0).toString() : '',
    );
    _emojiSeleccionado = meta?['emoji'] as String?;
    if (meta?['fecha_limite'] != null) {
      _fechaLimite = DateTime.tryParse(meta!['fecha_limite']);
    }
    if (meta?['color'] != null) {
      try {
        _colorSeleccionado = Color(
          int.parse((meta!['color'] as String).replaceFirst('#', '0xFF')),
        );
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _montoMetaController.dispose();
    _montoActualController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.metaExistente != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                Text(
                  isEditing ? 'Editar meta' : 'Nueva meta de ahorro',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // Nombre
                TextFormField(
                  controller: _nombreController,
                  decoration: InputDecoration(
                    labelText: 'Nombre de la meta',
                    hintText: 'Ej: Viaje a Japón',
                    prefixIcon:
                        _emojiSeleccionado != null &&
                            _emojiSeleccionado!.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(left: 12, right: 4),
                            child: Text(
                              _emojiSeleccionado!,
                              style: const TextStyle(fontSize: 20),
                            ),
                          )
                        : const Icon(Icons.flag_outlined),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 0,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Requerido'
                      : null,
                ),
                const SizedBox(height: 16),

                // Emoji selector
                Text(
                  'Emoji (opcional)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      // Clear emoji option
                      GestureDetector(
                        onTap: () => setState(() => _emojiSeleccionado = null),
                        child: Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: _emojiSeleccionado == null
                                ? (isDark
                                      ? Colors.teal.shade800
                                      : Colors.teal.shade100)
                                : (isDark
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(10),
                            border: _emojiSeleccionado == null
                                ? Border.all(
                                    color: Colors.teal.shade400,
                                    width: 2,
                                  )
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      ..._PantallaPrincipalState._emojisMeta.map((emoji) {
                        final isSelected = _emojiSeleccionado == emoji;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _emojiSeleccionado = emoji),
                          child: Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark
                                        ? Colors.teal.shade800
                                        : Colors.teal.shade100)
                                  : (isDark
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(10),
                              border: isSelected
                                  ? Border.all(
                                      color: Colors.teal.shade400,
                                      width: 2,
                                    )
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Monto meta
                TextFormField(
                  controller: _montoMetaController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Monto objetivo',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Requerido';
                    }
                    final parsed = int.tryParse(value.trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Debe ser mayor a 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Monto actual (solo en creación o edición)
                TextFormField(
                  controller: _montoActualController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Monto inicial ahorrado',
                    hintText: '0',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Fecha límite (optional)
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Fecha límite (opcional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            _fechaLimite ??
                            DateTime.now().add(const Duration(days: 90)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (picked != null) {
                        setState(() => _fechaLimite = picked);
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fechaLimite != null
                              ? '${_fechaLimite!.day}/${_fechaLimite!.month}/${_fechaLimite!.year}'
                              : 'Sin fecha límite',
                          style: TextStyle(
                            color: _fechaLimite != null
                                ? null
                                : (isDark
                                      ? Colors.grey.shade500
                                      : Colors.grey.shade500),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_fechaLimite != null)
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _fechaLimite = null),
                                child: Icon(
                                  Icons.clear,
                                  size: 18,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            const SizedBox(width: 4),
                            const Icon(Icons.calendar_today, size: 18),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Color picker
                Text(
                  'Color de la meta',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _PantallaPrincipalState._coloresMeta.map((color) {
                    final isSelected =
                        _colorSeleccionado.toARGB32() == color.toARGB32();
                    return GestureDetector(
                      onTap: () => setState(() => _colorSeleccionado = color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: isSelected ? 36 : 30,
                        height: isSelected ? 36 : 30,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(
                                  color: isDark ? Colors.white : Colors.black87,
                                  width: 2.5,
                                )
                              : null,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withAlpha(120),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isEditing ? 'Guardar cambios' : 'Crear meta',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final data = <String, dynamic>{
      'nombre': _nombreController.text.trim(),
      'emoji': _emojiSeleccionado,
      'monto_meta': int.parse(_montoMetaController.text.trim()),
      'monto_actual': int.tryParse(_montoActualController.text.trim()) ?? 0,
      'fecha_limite': _fechaLimite?.toIso8601String().split('T').first,
      'color': _colorToHex(_colorSeleccionado),
    };

    try {
      await widget.onGuardar(data);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SIMULADOR DE COMPRAS — Widget de pantalla completa
// ═══════════════════════════════════════════════════════════════════

class _SimuladorCompraSheet extends StatefulWidget {
  final int ingresoPromedio;
  final int gastoPromedio;
  final int flujoBasePromedio;
  final int patrimonioActual;
  final String Function(num) formatoMoneda;

  const _SimuladorCompraSheet({
    required this.ingresoPromedio,
    required this.gastoPromedio,
    required this.flujoBasePromedio,
    required this.patrimonioActual,
    required this.formatoMoneda,
  });

  @override
  State<_SimuladorCompraSheet> createState() => _SimuladorCompraSheetState();
}

class _SimuladorCompraSheetState extends State<_SimuladorCompraSheet> {
  final _nombreCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _cuotasCtrl = TextEditingController(text: '12');
  final _tasaCtrl = TextEditingController(text: '0');

  bool _esCuotas = false;
  bool _simulado = false;
  final int _mesInicioOffset = 0; // 0 = mes actual

  // Resultados
  List<Map<String, dynamic>> _proyeccion = [];
  int _cuotaMensual = 0;
  int _totalConInteres = 0;
  int _costoInteres = 0;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _montoCtrl.dispose();
    _cuotasCtrl.dispose();
    _tasaCtrl.dispose();
    super.dispose();
  }

  void _calcularSimulacion() {
    final montoTotal =
        int.tryParse(_montoCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (montoTotal <= 0) return;

    final now = DateTime.now();

    if (!_esCuotas) {
      // ── CONTADO ──
      final flujoConCompra = widget.flujoBasePromedio - montoTotal;
      final diasDelMes = DateUtils.getDaysInMonth(now.year, now.month);
      final diasRestantes = diasDelMes - now.day + 1;
      _cuotaMensual = montoTotal;
      _totalConInteres = montoTotal;
      _costoInteres = 0;

      _proyeccion = [
        {
          'mes': DateTime(now.year, now.month),
          'label': _nombreMes(now.month, now.year),
          'flujoSin': widget.flujoBasePromedio,
          'flujoCon': flujoConCompra,
          'cuota': montoTotal,
          'diasRestantes': diasRestantes,
        },
      ];
    } else {
      // ── CUOTAS CON INTERÉS ──
      final numCuotas = int.tryParse(_cuotasCtrl.text) ?? 12;
      final tasaAnual =
          double.tryParse(_tasaCtrl.text.replaceAll(',', '.')) ?? 0;

      if (numCuotas <= 0) return;

      if (tasaAnual > 0) {
        // Fórmula francesa: C = P * r * (1+r)^n / ((1+r)^n - 1)
        final tasaMensual = tasaAnual / 100 / 12;
        final potencia = _pow(1 + tasaMensual, numCuotas);
        _cuotaMensual = (montoTotal * tasaMensual * potencia / (potencia - 1))
            .round();
        _totalConInteres = _cuotaMensual * numCuotas;
        _costoInteres = _totalConInteres - montoTotal;
      } else {
        _cuotaMensual = (montoTotal / numCuotas).ceil();
        _totalConInteres = montoTotal;
        _costoInteres = 0;
      }

      _proyeccion = List.generate(numCuotas, (i) {
        final mesIdx = now.month + _mesInicioOffset + i;
        final fecha = DateTime(now.year, mesIdx);
        return {
          'mes': fecha,
          'label': _nombreMes(fecha.month, fecha.year),
          'flujoSin': widget.flujoBasePromedio,
          'flujoCon': widget.flujoBasePromedio - _cuotaMensual,
          'cuota': _cuotaMensual,
          'numeroCuota': i + 1,
        };
      });
    }

    setState(() => _simulado = true);
  }

  double _pow(double base, int exp) {
    var result = 1.0;
    for (var i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }

  String _nombreMes(int month, int year) {
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
    final m = ((month - 1) % 12 + 12) % 12;
    return '${meses[m]} $year';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.92,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.deepPurple.shade400,
                        Colors.indigo.shade400,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Simulador de Compra',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Analiza el impacto antes de comprar',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── FORMULARIO ──
                  _seccionTitulo(
                    'Datos de la compra',
                    Icons.shopping_bag_outlined,
                  ),
                  const SizedBox(height: 12),
                  _campo(
                    controller: _nombreCtrl,
                    label: '¿Qué quieres comprar?',
                    hint: 'Ej: MacBook Pro, Viaje, etc.',
                    icon: Icons.label_outline,
                  ),
                  const SizedBox(height: 12),
                  _campo(
                    controller: _montoCtrl,
                    label: 'Monto total',
                    hint: 'Precio de la compra',
                    icon: Icons.attach_money,
                    isNumber: true,
                  ),
                  const SizedBox(height: 16),
                  // Toggle Contado / Cuotas
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2433) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _esCuotas = false;
                              _simulado = false;
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: !_esCuotas
                                    ? Colors.deepPurple.withAlpha(
                                        isDark ? 60 : 30,
                                      )
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.payment,
                                    size: 18,
                                    color: !_esCuotas
                                        ? Colors.deepPurple
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Contado',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: !_esCuotas
                                          ? (isDark
                                                ? Colors.deepPurple.shade200
                                                : Colors.deepPurple)
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _esCuotas = true;
                              _simulado = false;
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _esCuotas
                                    ? Colors.deepPurple.withAlpha(
                                        isDark ? 60 : 30,
                                      )
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.calendar_month,
                                    size: 18,
                                    color: _esCuotas
                                        ? Colors.deepPurple
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'En cuotas',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _esCuotas
                                          ? (isDark
                                                ? Colors.deepPurple.shade200
                                                : Colors.deepPurple)
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Campos de cuotas
                  if (_esCuotas) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _campo(
                            controller: _cuotasCtrl,
                            label: 'Nº de cuotas',
                            hint: '12',
                            icon: Icons.numbers,
                            isNumber: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _campo(
                            controller: _tasaCtrl,
                            label: 'Tasa anual %',
                            hint: '0',
                            icon: Icons.percent,
                            isNumber: true,
                            isDecimal: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Chips de cuotas rápidas
                    Wrap(
                      spacing: 8,
                      children: [3, 6, 12, 18, 24, 36].map((n) {
                        final selected = _cuotasCtrl.text == n.toString();
                        return ChoiceChip(
                          label: Text('$n'),
                          selected: selected,
                          onSelected: (_) {
                            setState(() {
                              _cuotasCtrl.text = n.toString();
                              _simulado = false;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Botón Simular
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _calcularSimulacion,
                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                      label: const Text(
                        'Simular',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  // ── RESULTADOS ──
                  if (_simulado) ...[
                    const SizedBox(height: 28),
                    _seccionTitulo('Resultado', Icons.analytics_outlined),
                    const SizedBox(height: 12),
                    // Resumen Card
                    _tarjetaResultado(isDark),
                    const SizedBox(height: 16),
                    // Comparación de presupuesto diario
                    _tarjetaPresupuestoDiario(isDark),
                    const SizedBox(height: 16),
                    // Impacto en patrimonio total
                    _tarjetaImpactoPatrimonio(isDark),
                    const SizedBox(height: 16),
                    // Alertas de riesgo
                    _construirAlertas(isDark),
                    // Gráfico proyección
                    if (_proyeccion.length > 1) ...[
                      const SizedBox(height: 16),
                      _construirGraficoProyeccion(isDark),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionTitulo(String titulo, IconData icono) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(
          icono,
          size: 20,
          color: isDark ? Colors.deepPurple.shade200 : Colors.deepPurple,
        ),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.grey.shade200 : Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isNumber = false,
    bool isDecimal = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      keyboardType: isNumber
          ? (isDecimal
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.number)
          : TextInputType.text,
      inputFormatters: isNumber && !isDecimal
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      onChanged: (_) {
        if (_simulado) setState(() => _simulado = false);
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: isDark ? const Color(0xFF1E2433) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
        ),
      ),
    );
  }

  Widget _tarjetaResultado(bool isDark) {
    final nombre = _nombreCtrl.text.trim().isEmpty
        ? 'Compra simulada'
        : _nombreCtrl.text.trim();
    final montoOriginal =
        int.tryParse(_montoCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2433) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 40 : 8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shopping_bag,
                color: Colors.deepPurple.shade300,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nombre,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _filaResumen(
            'Precio',
            widget.formatoMoneda(montoOriginal),
            Icons.sell_outlined,
            isDark ? Colors.grey.shade300 : Colors.grey.shade700,
          ),
          if (_esCuotas) ...[
            const SizedBox(height: 6),
            _filaResumen(
              'Cuota mensual',
              widget.formatoMoneda(_cuotaMensual),
              Icons.calendar_today,
              Colors.deepPurple,
            ),
            const SizedBox(height: 6),
            _filaResumen(
              'Cuotas',
              '${_cuotasCtrl.text}x ${widget.formatoMoneda(_cuotaMensual)}',
              Icons.numbers,
              isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
            if (_costoInteres > 0) ...[
              const SizedBox(height: 6),
              _filaResumen(
                'Costo financiero',
                '+${widget.formatoMoneda(_costoInteres)}',
                Icons.trending_up,
                Colors.orange.shade700,
              ),
              const SizedBox(height: 6),
              _filaResumen(
                'Total a pagar',
                widget.formatoMoneda(_totalConInteres),
                Icons.account_balance_wallet,
                Colors.red.shade600,
              ),
            ],
          ] else ...[
            const SizedBox(height: 6),
            _filaResumen(
              'Pago único',
              widget.formatoMoneda(montoOriginal),
              Icons.bolt,
              Colors.deepPurple,
            ),
          ],
        ],
      ),
    );
  }

  Widget _filaResumen(String label, String valor, IconData icono, Color color) {
    return Row(
      children: [
        Icon(icono, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
        const Spacer(),
        Text(
          valor,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _tarjetaPresupuestoDiario(bool isDark) {
    final now = DateTime.now();
    final diasDelMes = DateUtils.getDaysInMonth(now.year, now.month);
    final diasRestantes = diasDelMes - now.day + 1;

    final presupuestoActual = diasRestantes > 0
        ? widget.flujoBasePromedio ~/ diasRestantes
        : widget.flujoBasePromedio;
    final impactoMensual = _esCuotas
        ? _cuotaMensual
        : (int.tryParse(_montoCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
              0);
    final presupuestoConCompra = diasRestantes > 0
        ? (widget.flujoBasePromedio - impactoMensual) ~/ diasRestantes
        : widget.flujoBasePromedio - impactoMensual;

    final diferencia = presupuestoConCompra - presupuestoActual;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2433) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.today_outlined,
                size: 20,
                color: isDark ? Colors.cyan.shade200 : Colors.cyan.shade700,
              ),
              const SizedBox(width: 8),
              const Text(
                'Presupuesto diario',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _miniCard(
                  'Actual',
                  widget.formatoMoneda(presupuestoActual),
                  presupuestoActual >= 0 ? Colors.green : Colors.red,
                  isDark,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 18, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Expanded(
                child: _miniCard(
                  'Con compra',
                  widget.formatoMoneda(presupuestoConCompra),
                  presupuestoConCompra >= 0 ? Colors.green : Colors.red,
                  isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: (diferencia >= 0 ? Colors.green : Colors.red).withAlpha(
                isDark ? 30 : 15,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  diferencia >= 0 ? Icons.thumb_up : Icons.thumb_down,
                  size: 16,
                  color: diferencia >= 0 ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  '${diferencia >= 0 ? '+' : ''}${widget.formatoMoneda(diferencia)}/día',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: diferencia >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCard(String label, String valor, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 25 : 12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaImpactoPatrimonio(bool isDark) {
    final montoTotal =
        int.tryParse(_montoCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    // Para contado: el patrimonio baja por el monto completo
    // Para cuotas: el patrimonio baja por el total con intereses
    final costoTotal = _esCuotas ? _totalConInteres : montoTotal;
    final patrimonioConCompra = widget.patrimonioActual - costoTotal;
    final diferencia = patrimonioConCompra - widget.patrimonioActual;
    final porcentajeCambio = widget.patrimonioActual != 0
        ? (diferencia / widget.patrimonioActual.abs()) * 100
        : 0.0;

    final colorPatrimonioCon = patrimonioConCompra >= 0
        ? Colors.green
        : Colors.red;
    final colorPatrimonioActual = widget.patrimonioActual >= 0
        ? Colors.green
        : Colors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2433) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_outlined,
                size: 20,
                color: isDark ? Colors.amber.shade200 : Colors.amber.shade800,
              ),
              const SizedBox(width: 8),
              const Text(
                'Impacto en patrimonio',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _miniCard(
                  'Actual',
                  widget.formatoMoneda(widget.patrimonioActual),
                  colorPatrimonioActual,
                  isDark,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 18, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Expanded(
                child: _miniCard(
                  'Con compra',
                  widget.formatoMoneda(patrimonioConCompra),
                  colorPatrimonioCon,
                  isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Barra de impacto
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(isDark ? 30 : 15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.trending_down, size: 16, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  '${widget.formatoMoneda(diferencia)} (${porcentajeCambio.toStringAsFixed(1)}%)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
          if (_esCuotas && _costoInteres > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(isDark ? 30 : 15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withAlpha(40)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Incluye ${widget.formatoMoneda(_costoInteres)} en intereses',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.orange.shade200
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Barra visual de proporción
          _barraProporcionPatrimonio(
            widget.patrimonioActual,
            patrimonioConCompra,
            costoTotal,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _barraProporcionPatrimonio(
    int patrimonioActual,
    int patrimonioConCompra,
    int costoCompra,
    bool isDark,
  ) {
    // Mostrar visualmente qué proporción del patrimonio representa la compra
    final absPatrimonio = patrimonioActual.abs();
    final fraccionCompra = absPatrimonio > 0
        ? (costoCompra / absPatrimonio).clamp(0.0, 1.0)
        : 1.0;
    final fraccionRestante = 1.0 - fraccionCompra;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Proporción sobre tu patrimonio',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                // Porción que queda
                Expanded(
                  flex: (fraccionRestante * 100).round().clamp(1, 100),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.tealAccent.withAlpha(80)
                          : Colors.teal.shade300,
                    ),
                  ),
                ),
                // Porción de la compra
                Expanded(
                  flex: (fraccionCompra * 100).round().clamp(1, 100),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.redAccent.withAlpha(120)
                          : Colors.red.shade400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.tealAccent.withAlpha(80)
                        : Colors.teal.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Restante ${(fraccionRestante * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.redAccent.withAlpha(120)
                        : Colors.red.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Compra ${(fraccionCompra * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _construirAlertas(bool isDark) {
    final mesesNegativos = _proyeccion
        .where((p) => (p['flujoCon'] as int) < 0)
        .length;
    if (mesesNegativos == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.withAlpha(isDark ? 30 : 15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withAlpha(60)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Colors.green.shade600,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tu flujo se mantiene positivo. ¡Puedes hacerlo!',
                style: TextStyle(
                  color: isDark ? Colors.green.shade200 : Colors.green.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(isDark ? 30 : 15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.red.shade600,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¡Atención!',
                  style: TextStyle(
                    color: isDark ? Colors.red.shade200 : Colors.red.shade800,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _esCuotas
                      ? 'En $mesesNegativos de ${_proyeccion.length} meses tu flujo sería negativo. '
                            'Considera menos cuotas o revisar tus gastos.'
                      : 'Tu flujo quedaría negativo este mes. '
                            'Considera pagar en cuotas.',
                  style: TextStyle(
                    color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirGraficoProyeccion(bool isDark) {
    // Limitar a mostrar máximo 12 barras, con paginación si hay más
    final maxVisible = 12;
    final total = _proyeccion.length;
    final datos = total <= maxVisible
        ? _proyeccion
        : _proyeccion.sublist(0, maxVisible);

    // Encontrar escala
    var maxAbs = 1.0;
    for (final p in datos) {
      final sinAbs = (p['flujoSin'] as int).abs().toDouble();
      final conAbs = (p['flujoCon'] as int).abs().toDouble();
      if (sinAbs > maxAbs) maxAbs = sinAbs;
      if (conAbs > maxAbs) maxAbs = conAbs;
    }

    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2433) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart,
                size: 20,
                color: isDark ? Colors.deepPurple.shade200 : Colors.deepPurple,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Proyección de flujo mensual',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Leyenda
          Row(
            children: [
              _leyenda(Colors.green.shade400, 'Sin compra'),
              const SizedBox(width: 16),
              _leyenda(Colors.deepPurple.shade400, 'Con compra'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: datos.map((p) {
                final flujoSin = p['flujoSin'] as int;
                final flujoCon = p['flujoCon'] as int;
                final label = p['label'] as String;

                final alturaSin = ((flujoSin.abs() / maxAbs) * 90) + 4;
                final alturaCon = ((flujoCon.abs() / maxAbs) * 90) + 4;

                final colorSin = flujoSin >= 0
                    ? Colors.green.shade400
                    : Colors.red.shade300;
                final colorCon = flujoCon >= 0
                    ? Colors.deepPurple.shade400
                    : Colors.red.shade600;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              width: 8,
                              height: alturaSin,
                              decoration: BoxDecoration(
                                color: colorSin,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Container(
                              width: 8,
                              height: alturaCon,
                              decoration: BoxDecoration(
                                color: colorCon,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label.split(' ')[0], // Solo mes corto
                          style: TextStyle(
                            fontSize: 9,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (total > maxVisible)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Mostrando primeros $maxVisible de $total meses',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    ));
  }

  Widget _leyenda(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

// â”€â”€ Dashed border painter for ghost transactions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double borderRadius;
  final double dashWidth;
  final double dashSpace;
  final double strokeWidth;

  const _DashedBorderPainter({
    required this.color,
    required this.borderRadius,
    required this.dashWidth,
    required this.dashSpace,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(borderRadius),
    );

    final path = Path()..addRRect(rrect);
    final PathMetrics pathMetrics = path.computeMetrics();

    for (final PathMetric metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
