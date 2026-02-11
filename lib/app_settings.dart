import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.seedColorValue,
    required this.compactMode,
    required this.hideAmounts,
    required this.currencyCode,
    required this.localeCode,
    required this.weekStartDay,
    required this.budgetCycleDay,
    required this.defaultAccount,
    required this.activeAccounts,
    required this.archivedAccounts,
    required this.activeCategories,
    required this.archivedCategories,
    required this.activeIncomeCategories,
    required this.archivedIncomeCategories,
    required this.globalMonthlyBudget,
    required this.categoryBudgets,
    required this.categoryEmojis,
    required this.savingsTargetPercent,
    required this.enableBudgetAlerts,
    required this.enableCashflowAlerts,
    required this.enableUnusualSpendAlerts,
    required this.budgetAlertThresholdPercent,
    required this.unusualSpendMultiplier,
    required this.lockEnabled,
    required this.biometricEnabled,
    required this.autoLockMinutes,
    required this.creditCardBillingDay,
    required this.creditCardDueDay,
    required this.enableCreditDueAlerts,
    required this.creditDueAlertDaysBefore,
    required this.consumptionCredits,
  });

  final String themeMode;
  final int seedColorValue;
  final bool compactMode;
  final bool hideAmounts;
  final String currencyCode;
  final String localeCode;
  final String weekStartDay;
  final int budgetCycleDay;
  final String defaultAccount;
  final List<String> activeAccounts;
  final List<String> archivedAccounts;
  final List<String> activeCategories;
  final List<String> archivedCategories;
  final List<String> activeIncomeCategories;
  final List<String> archivedIncomeCategories;
  final int? globalMonthlyBudget;
  final Map<String, int> categoryBudgets;
  final Map<String, String> categoryEmojis;
  final double savingsTargetPercent;
  final bool enableBudgetAlerts;
  final bool enableCashflowAlerts;
  final bool enableUnusualSpendAlerts;
  final double budgetAlertThresholdPercent;
  final double unusualSpendMultiplier;
  final bool lockEnabled;
  final bool biometricEnabled;
  final int autoLockMinutes;
  final int creditCardBillingDay;
  final int creditCardDueDay;
  final bool enableCreditDueAlerts;
  final int creditDueAlertDaysBefore;
  final List<Map<String, dynamic>> consumptionCredits;

  static const _unset = Object();

  factory AppSettings.defaults() {
    return const AppSettings(
      themeMode: 'system',
      seedColorValue: 0xFF00897B,
      compactMode: false,
      hideAmounts: false,
      currencyCode: 'CLP',
      localeCode: 'es_CL',
      weekStartDay: 'monday',
      budgetCycleDay: 1,
      defaultAccount: 'Banco Bice',
      activeAccounts: ['Banco Bice'],
      archivedAccounts: [],
      activeCategories: [
        'Comida',
        'Transporte',
        'Regalos',
        'Suscripciones',
        'Carrete',
        'Panoramas',
        'Ropa',
        'Bencina',
        'Salud',
        'Deportes',
        'Peluqueria',
        'Supermercado',
        'Varios',
      ],
      archivedCategories: [],
      activeIncomeCategories: [
        'Sueldo',
        'Freelance',
        'Transferencia Recibida',
        'Inversiones',
        'Reembolso',
        'Arriendo',
        'Venta',
        'Mesada',
        'Otros Ingresos',
      ],
      archivedIncomeCategories: [],
      globalMonthlyBudget: null,
      categoryBudgets: {},
      categoryEmojis: {},
      savingsTargetPercent: 20,
      enableBudgetAlerts: true,
      enableCashflowAlerts: true,
      enableUnusualSpendAlerts: true,
      budgetAlertThresholdPercent: 80,
      unusualSpendMultiplier: 1.35,
      lockEnabled: false,
      biometricEnabled: false,
      autoLockMinutes: 1,
      creditCardBillingDay: 5,
      creditCardDueDay: 15,
      enableCreditDueAlerts: true,
      creditDueAlertDaysBefore: 3,
      consumptionCredits: [],
    );
  }

  AppSettings copyWith({
    String? themeMode,
    int? seedColorValue,
    bool? compactMode,
    bool? hideAmounts,
    String? currencyCode,
    String? localeCode,
    String? weekStartDay,
    int? budgetCycleDay,
    String? defaultAccount,
    List<String>? activeAccounts,
    List<String>? archivedAccounts,
    List<String>? activeCategories,
    List<String>? archivedCategories,
    List<String>? activeIncomeCategories,
    List<String>? archivedIncomeCategories,
    Object? globalMonthlyBudget = _unset,
    Map<String, int>? categoryBudgets,
    Map<String, String>? categoryEmojis,
    double? savingsTargetPercent,
    bool? enableBudgetAlerts,
    bool? enableCashflowAlerts,
    bool? enableUnusualSpendAlerts,
    double? budgetAlertThresholdPercent,
    double? unusualSpendMultiplier,
    bool? lockEnabled,
    bool? biometricEnabled,
    int? autoLockMinutes,
    int? creditCardBillingDay,
    int? creditCardDueDay,
    bool? enableCreditDueAlerts,
    int? creditDueAlertDaysBefore,
    List<Map<String, dynamic>>? consumptionCredits,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seedColorValue: seedColorValue ?? this.seedColorValue,
      compactMode: compactMode ?? this.compactMode,
      hideAmounts: hideAmounts ?? this.hideAmounts,
      currencyCode: currencyCode ?? this.currencyCode,
      localeCode: localeCode ?? this.localeCode,
      weekStartDay: weekStartDay ?? this.weekStartDay,
      budgetCycleDay: budgetCycleDay ?? this.budgetCycleDay,
      defaultAccount: defaultAccount ?? this.defaultAccount,
      activeAccounts: activeAccounts ?? this.activeAccounts,
      archivedAccounts: archivedAccounts ?? this.archivedAccounts,
      activeCategories: activeCategories ?? this.activeCategories,
      archivedCategories: archivedCategories ?? this.archivedCategories,
      activeIncomeCategories:
          activeIncomeCategories ?? this.activeIncomeCategories,
      archivedIncomeCategories:
          archivedIncomeCategories ?? this.archivedIncomeCategories,
      globalMonthlyBudget: identical(globalMonthlyBudget, _unset)
          ? this.globalMonthlyBudget
          : globalMonthlyBudget as int?,
      categoryBudgets: categoryBudgets ?? this.categoryBudgets,
      categoryEmojis: categoryEmojis ?? this.categoryEmojis,
      savingsTargetPercent: savingsTargetPercent ?? this.savingsTargetPercent,
      enableBudgetAlerts: enableBudgetAlerts ?? this.enableBudgetAlerts,
      enableCashflowAlerts: enableCashflowAlerts ?? this.enableCashflowAlerts,
      enableUnusualSpendAlerts:
          enableUnusualSpendAlerts ?? this.enableUnusualSpendAlerts,
      budgetAlertThresholdPercent:
          budgetAlertThresholdPercent ?? this.budgetAlertThresholdPercent,
      unusualSpendMultiplier:
          unusualSpendMultiplier ?? this.unusualSpendMultiplier,
      lockEnabled: lockEnabled ?? this.lockEnabled,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
      creditCardBillingDay: creditCardBillingDay ?? this.creditCardBillingDay,
      creditCardDueDay: creditCardDueDay ?? this.creditCardDueDay,
      enableCreditDueAlerts:
          enableCreditDueAlerts ?? this.enableCreditDueAlerts,
      creditDueAlertDaysBefore:
          creditDueAlertDaysBefore ?? this.creditDueAlertDaysBefore,
      consumptionCredits: consumptionCredits ?? this.consumptionCredits,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeMode': themeMode,
      'seedColorValue': seedColorValue,
      'compactMode': compactMode,
      'hideAmounts': hideAmounts,
      'currencyCode': currencyCode,
      'localeCode': localeCode,
      'weekStartDay': weekStartDay,
      'budgetCycleDay': budgetCycleDay,
      'defaultAccount': defaultAccount,
      'activeAccounts': activeAccounts,
      'archivedAccounts': archivedAccounts,
      'activeCategories': activeCategories,
      'archivedCategories': archivedCategories,
      'activeIncomeCategories': activeIncomeCategories,
      'archivedIncomeCategories': archivedIncomeCategories,
      'globalMonthlyBudget': globalMonthlyBudget,
      'categoryBudgets': categoryBudgets,
      'categoryEmojis': categoryEmojis,
      'savingsTargetPercent': savingsTargetPercent,
      'enableBudgetAlerts': enableBudgetAlerts,
      'enableCashflowAlerts': enableCashflowAlerts,
      'enableUnusualSpendAlerts': enableUnusualSpendAlerts,
      'budgetAlertThresholdPercent': budgetAlertThresholdPercent,
      'unusualSpendMultiplier': unusualSpendMultiplier,
      'lockEnabled': lockEnabled,
      'biometricEnabled': biometricEnabled,
      'autoLockMinutes': autoLockMinutes,
      'creditCardBillingDay': creditCardBillingDay,
      'creditCardDueDay': creditCardDueDay,
      'enableCreditDueAlerts': enableCreditDueAlerts,
      'creditDueAlertDaysBefore': creditDueAlertDaysBefore,
      'consumptionCredits': consumptionCredits,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.defaults();
    return AppSettings(
      themeMode: (json['themeMode'] as String?) ?? defaults.themeMode,
      seedColorValue:
          (json['seedColorValue'] as num?)?.toInt() ?? defaults.seedColorValue,
      compactMode: (json['compactMode'] as bool?) ?? defaults.compactMode,
      hideAmounts: (json['hideAmounts'] as bool?) ?? defaults.hideAmounts,
      currencyCode: (json['currencyCode'] as String?) ?? defaults.currencyCode,
      localeCode: (json['localeCode'] as String?) ?? defaults.localeCode,
      weekStartDay: (json['weekStartDay'] as String?) ?? defaults.weekStartDay,
      budgetCycleDay:
          (json['budgetCycleDay'] as num?)?.toInt() ?? defaults.budgetCycleDay,
      defaultAccount:
          (json['defaultAccount'] as String?) ?? defaults.defaultAccount,
      activeAccounts:
          _asStringList(json['activeAccounts']) ?? defaults.activeAccounts,
      archivedAccounts:
          _asStringList(json['archivedAccounts']) ?? defaults.archivedAccounts,
      activeCategories:
          _asStringList(json['activeCategories']) ?? defaults.activeCategories,
      archivedCategories:
          _asStringList(json['archivedCategories']) ??
          defaults.archivedCategories,
      activeIncomeCategories:
          _asStringList(json['activeIncomeCategories']) ??
          defaults.activeIncomeCategories,
      archivedIncomeCategories:
          _asStringList(json['archivedIncomeCategories']) ??
          defaults.archivedIncomeCategories,
      globalMonthlyBudget: (json['globalMonthlyBudget'] as num?)?.toInt(),
      categoryBudgets: _asIntMap(json['categoryBudgets']),
      categoryEmojis: _asStringMap(json['categoryEmojis']),
      savingsTargetPercent:
          (json['savingsTargetPercent'] as num?)?.toDouble() ??
          defaults.savingsTargetPercent,
      enableBudgetAlerts:
          (json['enableBudgetAlerts'] as bool?) ?? defaults.enableBudgetAlerts,
      enableCashflowAlerts:
          (json['enableCashflowAlerts'] as bool?) ??
          defaults.enableCashflowAlerts,
      enableUnusualSpendAlerts:
          (json['enableUnusualSpendAlerts'] as bool?) ??
          defaults.enableUnusualSpendAlerts,
      budgetAlertThresholdPercent:
          (json['budgetAlertThresholdPercent'] as num?)?.toDouble() ??
          defaults.budgetAlertThresholdPercent,
      unusualSpendMultiplier:
          (json['unusualSpendMultiplier'] as num?)?.toDouble() ??
          defaults.unusualSpendMultiplier,
      lockEnabled: (json['lockEnabled'] as bool?) ?? defaults.lockEnabled,
      biometricEnabled:
          (json['biometricEnabled'] as bool?) ?? defaults.biometricEnabled,
      autoLockMinutes:
          (json['autoLockMinutes'] as num?)?.toInt() ??
          defaults.autoLockMinutes,
      creditCardBillingDay:
          (json['creditCardBillingDay'] as num?)?.toInt() ??
          defaults.creditCardBillingDay,
      creditCardDueDay:
          (json['creditCardDueDay'] as num?)?.toInt() ??
          defaults.creditCardDueDay,
      enableCreditDueAlerts:
          (json['enableCreditDueAlerts'] as bool?) ??
          defaults.enableCreditDueAlerts,
      creditDueAlertDaysBefore:
          (json['creditDueAlertDaysBefore'] as num?)?.toInt() ??
          defaults.creditDueAlertDaysBefore,
      consumptionCredits:
          (json['consumptionCredits'] as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          defaults.consumptionCredits,
    );
  }

  static List<String>? _asStringList(dynamic value) {
    if (value is! List) {
      return null;
    }
    return value.map((e) => e.toString()).toList();
  }

  static Map<String, int> _asIntMap(dynamic value) {
    if (value is! Map) {
      return {};
    }
    final map = <String, int>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final raw = entry.value;
      if (raw is num) {
        map[key] = raw.toInt();
      }
    }
    return map;
  }

  static Map<String, String> _asStringMap(dynamic value) {
    if (value is! Map) {
      return {};
    }
    final map = <String, String>{};
    for (final entry in value.entries) {
      map[entry.key.toString()] = entry.value.toString();
    }
    return map;
  }
}

class SettingsController extends ChangeNotifier {
  SettingsController({
    required SharedPreferences preferences,
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuth,
  }) : _preferences = preferences,
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _localAuth = localAuth ?? LocalAuthentication();

  static const _settingsKey = 'app_settings_v1';
  static const _pinHashKey = 'security_pin_hash';
  static const _pinSaltKey = 'security_pin_salt';

  final SharedPreferences _preferences;
  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuth;
  final Random _random = Random.secure();

  AppSettings _settings = AppSettings.defaults();
  bool _ready = false;
  bool _hasPinConfigured = false;
  bool _biometricAvailable = false;

  AppSettings get settings => _settings;
  bool get isReady => _ready;
  bool get hasPinConfigured => _hasPinConfigured;
  bool get biometricAvailable => _biometricAvailable;

  Future<void> init() async {
    final raw = _preferences.getString(_settingsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _settings = AppSettings.fromJson(decoded);
      } catch (_) {
        _settings = AppSettings.defaults();
      }
    }
    _hasPinConfigured = await _hasPinData();
    _biometricAvailable = await _resolveBiometrics();

    // Sync with cloud if logged in
    await loadFromCloud();

    _ready = true;
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    try {
      await _preferences.setString(
        _settingsKey,
        jsonEncode(_settings.toJson()),
      );
      // Fire-and-forget sync
      syncToCloud();
    } catch (e, stack) {
      debugPrint('Error saving settings: $e\n$stack');
    }
  }

  Future<void> syncToCloud() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .upsert({
            'id': session.user.id,
            'updated_at': DateTime.now().toIso8601String(),
            'settings': _settings.toJson(),
          })
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore sync errors
    }
  }

  Future<void> loadFromCloud() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', session.user.id)
          .maybeSingle();

      if (response != null && response['settings'] != null) {
        final cloudSettings = AppSettings.fromJson(response['settings']);
        _settings = cloudSettings;
        // Update local storage to match cloud
        await _preferences.setString(
          _settingsKey,
          jsonEncode(_settings.toJson()),
        );
        notifyListeners();
      }
    } catch (_) {
      // Ignore sync errors
    }
  }

  void _apply(AppSettings updated) {
    _settings = updated;
    try {
      notifyListeners();
    } catch (e, stack) {
      debugPrint('Error in notifyListeners (UI Rebuild?): $e\n$stack');
    }
    _saveSettings(); // Fire-and-forget inside
  }

  void setThemeMode(String value) =>
      _apply(_settings.copyWith(themeMode: value));
  void setSeedColor(int value) =>
      _apply(_settings.copyWith(seedColorValue: value));
  void setCompactMode(bool value) =>
      _apply(_settings.copyWith(compactMode: value));
  void setHideAmounts(bool value) =>
      _apply(_settings.copyWith(hideAmounts: value));
  void setCurrencyCode(String value) =>
      _apply(_settings.copyWith(currencyCode: value));
  void setLocaleCode(String value) =>
      _apply(_settings.copyWith(localeCode: value));
  void setWeekStartDay(String value) =>
      _apply(_settings.copyWith(weekStartDay: value));
  void setBudgetCycleDay(int value) =>
      _apply(_settings.copyWith(budgetCycleDay: value.clamp(1, 28)));

  void addAccount(String value) {
    final account = value.trim();
    if (account.isEmpty) {
      return;
    }
    final active = [..._settings.activeAccounts];
    final archived = [..._settings.archivedAccounts];
    if (active.any((x) => x.toLowerCase() == account.toLowerCase())) {
      return;
    }
    archived.removeWhere((x) => x.toLowerCase() == account.toLowerCase());
    active.add(account);
    _apply(
      _settings.copyWith(activeAccounts: active, archivedAccounts: archived),
    );
  }

  void renameAccount(String oldValue, String newValue) {
    final account = newValue.trim();
    if (account.isEmpty) {
      return;
    }
    final active = _settings.activeAccounts
        .map((e) => e == oldValue ? account : e)
        .toList();
    final archived = _settings.archivedAccounts
        .map((e) => e == oldValue ? account : e)
        .toList();
    final defaultAccount = _settings.defaultAccount == oldValue
        ? account
        : _settings.defaultAccount;
    _apply(
      _settings.copyWith(
        activeAccounts: _dedupe(active),
        archivedAccounts: _dedupe(archived),
        defaultAccount: defaultAccount,
      ),
    );
  }

  void archiveAccount(String account) {
    final active = [..._settings.activeAccounts];
    if (!active.contains(account) || active.length <= 1) {
      return;
    }
    active.remove(account);
    final archived = [..._settings.archivedAccounts];
    if (!archived.contains(account)) {
      archived.add(account);
    }
    var defaultAccount = _settings.defaultAccount;
    if (defaultAccount == account) {
      defaultAccount = active.first;
    }
    _apply(
      _settings.copyWith(
        activeAccounts: active,
        archivedAccounts: archived,
        defaultAccount: defaultAccount,
      ),
    );
  }

  void restoreAccount(String account) {
    final active = [..._settings.activeAccounts];
    final archived = [..._settings.archivedAccounts];
    if (!archived.contains(account)) {
      return;
    }
    archived.remove(account);
    if (!active.contains(account)) {
      active.add(account);
    }
    _apply(
      _settings.copyWith(activeAccounts: active, archivedAccounts: archived),
    );
  }

  void setDefaultAccount(String account) {
    if (!_settings.activeAccounts.contains(account)) {
      return;
    }
    _apply(_settings.copyWith(defaultAccount: account));
  }

  void addCategory(String value) {
    final category = value.trim();
    if (category.isEmpty) {
      return;
    }
    final active = [..._settings.activeCategories];
    final archived = [..._settings.archivedCategories];
    if (active.any((x) => x.toLowerCase() == category.toLowerCase())) {
      return;
    }
    archived.removeWhere((x) => x.toLowerCase() == category.toLowerCase());
    active.add(category);
    _apply(
      _settings.copyWith(
        activeCategories: active,
        archivedCategories: archived,
      ),
    );
  }

  void renameCategory(String oldValue, String newValue) {
    final category = newValue.trim();
    if (category.isEmpty) {
      return;
    }
    final active = _settings.activeCategories
        .map((e) => e == oldValue ? category : e)
        .toList();
    final archived = _settings.archivedCategories
        .map((e) => e == oldValue ? category : e)
        .toList();
    final budgets = Map<String, int>.from(_settings.categoryBudgets);
    if (budgets.containsKey(oldValue)) {
      budgets[category] = budgets.remove(oldValue)!;
    }
    final emojis = Map<String, String>.from(_settings.categoryEmojis);
    if (emojis.containsKey(oldValue)) {
      emojis[category] = emojis.remove(oldValue)!;
    }
    _apply(
      _settings.copyWith(
        activeCategories: _dedupe(active),
        archivedCategories: _dedupe(archived),
        categoryBudgets: budgets,
        categoryEmojis: emojis,
      ),
    );
  }

  void archiveCategory(String category) {
    final active = [..._settings.activeCategories];
    if (!active.contains(category) || active.length <= 1) {
      return;
    }
    active.remove(category);
    final archived = [..._settings.archivedCategories];
    if (!archived.contains(category)) {
      archived.add(category);
    }
    _apply(
      _settings.copyWith(
        activeCategories: active,
        archivedCategories: archived,
      ),
    );
  }

  void restoreCategory(String category) {
    final active = [..._settings.activeCategories];
    final archived = [..._settings.archivedCategories];
    if (!archived.contains(category)) {
      return;
    }
    archived.remove(category);
    if (!active.contains(category)) {
      active.add(category);
    }
    _apply(
      _settings.copyWith(
        activeCategories: active,
        archivedCategories: archived,
      ),
    );
  }

  void setGlobalMonthlyBudget(int? value) {
    if (value == null || value <= 0) {
      _apply(_settings.copyWith(globalMonthlyBudget: null));
      return;
    }
    _apply(_settings.copyWith(globalMonthlyBudget: value));
  }

  void setCategoryBudget(String category, int? value) {
    final budgets = Map<String, int>.from(_settings.categoryBudgets);
    if (value == null || value <= 0) {
      budgets.remove(category);
    } else {
      budgets[category] = value;
    }
    _apply(_settings.copyWith(categoryBudgets: budgets));
  }

  void setCategoryEmoji(String category, String? emoji) {
    final emojis = Map<String, String>.from(_settings.categoryEmojis);
    if (emoji == null || emoji.isEmpty) {
      emojis.remove(category);
    } else {
      emojis[category] = emoji;
    }
    _apply(_settings.copyWith(categoryEmojis: emojis));
  }

  void setSavingsTargetPercent(double value) =>
      _apply(_settings.copyWith(savingsTargetPercent: value.clamp(0, 100)));
  void setBudgetAlertsEnabled(bool value) =>
      _apply(_settings.copyWith(enableBudgetAlerts: value));
  void setCashflowAlertsEnabled(bool value) =>
      _apply(_settings.copyWith(enableCashflowAlerts: value));
  void setUnusualAlertsEnabled(bool value) =>
      _apply(_settings.copyWith(enableUnusualSpendAlerts: value));
  void setBudgetAlertThresholdPercent(double value) => _apply(
    _settings.copyWith(budgetAlertThresholdPercent: value.clamp(50, 100)),
  );
  void setUnusualSpendMultiplier(double value) =>
      _apply(_settings.copyWith(unusualSpendMultiplier: value.clamp(1.1, 2.5)));
  void setLockEnabled(bool value) =>
      _apply(_settings.copyWith(lockEnabled: value));
  void setBiometricEnabled(bool value) =>
      _apply(_settings.copyWith(biometricEnabled: value));
  void setAutoLockMinutes(int value) =>
      _apply(_settings.copyWith(autoLockMinutes: value));
  void setCreditCardBillingDay(int value) =>
      _apply(_settings.copyWith(creditCardBillingDay: value.clamp(1, 31)));
  void setCreditCardDueDay(int value) =>
      _apply(_settings.copyWith(creditCardDueDay: value.clamp(1, 31)));
  void setEnableCreditDueAlerts(bool value) =>
      _apply(_settings.copyWith(enableCreditDueAlerts: value));
  void setCreditDueAlertDaysBefore(int value) =>
      _apply(_settings.copyWith(creditDueAlertDaysBefore: value.clamp(1, 7)));
  void addConsumptionCredit(Map<String, dynamic> credit) {
    final current = List<Map<String, dynamic>>.from(
      _settings.consumptionCredits,
    );
    current.add(credit);
    _apply(_settings.copyWith(consumptionCredits: current));
  }

  void removeConsumptionCredit(String id) {
    final current = List<Map<String, dynamic>>.from(
      _settings.consumptionCredits,
    );
    current.removeWhere((c) => c['id'] == id);
    _apply(_settings.copyWith(consumptionCredits: current));
  }

  void updateConsumptionCredit(String id, Map<String, dynamic> credit) {
    final current = List<Map<String, dynamic>>.from(
      _settings.consumptionCredits,
    );
    final index = current.indexWhere((c) => c['id'] == id);
    if (index != -1) {
      current[index] = credit;
      _apply(_settings.copyWith(consumptionCredits: current));
    }
  }

  Future<void> resetSettings() async {
    _settings = AppSettings.defaults();
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hash(pin, salt);
    await _secureStorage.write(key: _pinSaltKey, value: salt);
    await _secureStorage.write(key: _pinHashKey, value: hash);
    _hasPinConfigured = true;
    notifyListeners();
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _secureStorage.read(key: _pinSaltKey);
    final hash = await _secureStorage.read(key: _pinHashKey);
    if (salt == null || hash == null) {
      return false;
    }
    return _hash(pin, salt) == hash;
  }

  Future<void> clearPin() async {
    await _secureStorage.delete(key: _pinSaltKey);
    await _secureStorage.delete(key: _pinHashKey);
    _hasPinConfigured = false;
    _apply(_settings.copyWith(lockEnabled: false, biometricEnabled: false));
  }

  Future<bool> authenticateBiometric() async {
    if (!_settings.biometricEnabled || !_biometricAvailable) {
      return false;
    }
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Desbloquear App Finanzas',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasPinData() async {
    final hash = await _secureStorage.read(key: _pinHashKey);
    final salt = await _secureStorage.read(key: _pinSaltKey);
    return hash != null && salt != null;
  }

  Future<bool> _resolveBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      return canCheck && supported;
    } catch (_) {
      return false;
    }
  }

  String _generateSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String pin, String salt) {
    final data = utf8.encode('$salt::$pin');
    return sha256.convert(data).toString();
  }

  static List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final output = <String>[];
    for (final value in values) {
      final clean = value.trim();
      if (clean.isEmpty) {
        continue;
      }
      final key = clean.toLowerCase();
      if (seen.contains(key)) {
        continue;
      }
      seen.add(key);
      output.add(clean);
    }
    return output;
  }
}
