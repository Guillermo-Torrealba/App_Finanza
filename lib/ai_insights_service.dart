import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Resultado estructurado del análisis de IA.
class AiInsightsResult {
  final String resumen;
  final List<AiInsight> insights;
  final List<String> recomendaciones;

  AiInsightsResult({
    required this.resumen,
    required this.insights,
    required this.recomendaciones,
  });

  factory AiInsightsResult.fromJson(Map<String, dynamic> json) {
    final rawInsights = json['insights'];
    final rawRecommendations = json['recomendaciones'];
    return AiInsightsResult(
      resumen: (json['resumen'] ?? '').toString(),
      insights: rawInsights is List
          ? rawInsights
              .whereType<Map>()
              .map((item) => AiInsight.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      recomendaciones: rawRecommendations is List
          ? rawRecommendations.map((item) => item.toString()).toList()
          : const [],
    );
  }
}

class AiInsight {
  final String titulo;
  final String descripcion;
  final String tipo;

  AiInsight({
    required this.titulo,
    required this.descripcion,
    required this.tipo,
  });

  factory AiInsight.fromJson(Map<String, dynamic> json) {
    return AiInsight(
      titulo: (json['titulo'] ?? '').toString(),
      descripcion: (json['descripcion'] ?? '').toString(),
      tipo: (json['tipo'] ?? 'info').toString(),
    );
  }
}

class AiInsightsService {
  AiInsightsService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  String? _lastFingerprint;
  AiInsightsResult? _cachedResult;
  final Map<String, String> _categoryCache = {};

  Future<Map<String, dynamic>> _invoke(
    String function,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.functions.invoke(function, body: body);
    final data = response.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const FormatException('Respuesta no válida del servicio.');
  }

  /// Analiza datos financieros agregados del período seleccionado.
  Future<AiInsightsResult> analyzeFinances(
    Map<String, dynamic> resumen,
  ) async {
    final fingerprint = jsonEncode(resumen);
    if (fingerprint == _lastFingerprint && _cachedResult != null) {
      return _cachedResult!;
    }

    final data = await _invoke('ai_insights', resumen);
    final result = AiInsightsResult.fromJson(data);
    _lastFingerprint = fingerprint;
    _cachedResult = result;
    return result;
  }

  void invalidateCache() {
    _lastFingerprint = null;
    _cachedResult = null;
  }

  Future<String?> suggestCategory(
    String concepto,
    List<String> categorias,
  ) async {
    if (concepto.trim().length < 3 || categorias.isEmpty) return null;
    final cacheKey = '${concepto.trim().toLowerCase()}|${categorias.join(',')}';
    if (_categoryCache.containsKey(cacheKey)) return _categoryCache[cacheKey];

    try {
      final data = await _invoke('ai_tools', {
        'action': 'suggest_category',
        'concepto': concepto,
        'categorias': categorias,
      });
      final suggestion = data['category']?.toString();
      if (suggestion == null || suggestion.isEmpty) return null;
      final match = categorias.firstWhere(
        (category) => category.toLowerCase() == suggestion.toLowerCase(),
        orElse: () => '',
      );
      if (match.isEmpty) return null;
      _categoryCache[cacheKey] = match;
      return match;
    } catch (_) {
      return null;
    }
  }

  Future<List<AiProactiveAlert>> generateProactiveAlerts(
    Map<String, dynamic> datosRecientes,
  ) async {
    if (datosRecientes.isEmpty) return [];
    try {
      final data = await _invoke('ai_tools', {
        'action': 'proactive_alerts',
        'data': datosRecientes,
      });
      final alerts = data['alerts'];
      if (alerts is! List) return [];
      return alerts
          .whereType<Map>()
          .map((item) => AiProactiveAlert.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<AiWeeklySummary?> generateWeeklySummary(
    Map<String, dynamic> datosSemana,
  ) async {
    if (datosSemana.isEmpty) return null;
    try {
      final data = await _invoke('ai_tools', {
        'action': 'weekly_summary',
        'data': datosSemana,
      });
      return AiWeeklySummary.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<ParsedTransaction?> parseNaturalLanguage(
    String texto, {
    required List<String> categoriasGasto,
    required List<String> categoriasIngreso,
    required List<String> cuentas,
    required String fechaHoy,
  }) async {
    if (texto.trim().length < 3) return null;
    try {
      final data = await _invoke('quick_entry', {
        'text': texto,
        'categorias': categoriasGasto,
        'categorias_ingreso': categoriasIngreso,
        'cuentas': cuentas,
        'fecha_actual': fechaHoy,
        'zona_horaria': 'America/Santiago',
      });
      return ParsedTransaction.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}

class ParsedTransaction {
  final String tipo;
  final String item;
  final int monto;
  final String categoria;
  final String fecha;
  final String? cuenta;
  final String metodoPago;

  ParsedTransaction({
    required this.tipo,
    required this.item,
    required this.monto,
    required this.categoria,
    required this.fecha,
    this.cuenta,
    this.metodoPago = 'Debito',
  });

  factory ParsedTransaction.fromJson(Map<String, dynamic> json) {
    return ParsedTransaction(
      tipo: (json['tipo'] ?? 'Gasto').toString(),
      item: (json['item'] ?? '').toString(),
      monto: (json['monto'] as num? ?? 0).toInt(),
      categoria: (json['categoria'] ?? 'Varios').toString(),
      fecha: (json['fecha'] ?? '').toString(),
      cuenta: json['cuenta']?.toString(),
      metodoPago: (json['metodo_pago'] ?? 'Debito').toString(),
    );
  }
}

class AiProactiveAlert {
  final String titulo;
  final String mensaje;
  final String tipo;

  AiProactiveAlert({
    required this.titulo,
    required this.mensaje,
    required this.tipo,
  });

  factory AiProactiveAlert.fromJson(Map<String, dynamic> json) {
    return AiProactiveAlert(
      titulo: (json['titulo'] ?? '').toString(),
      mensaje: (json['mensaje'] ?? '').toString(),
      tipo: (json['tipo'] ?? 'alerta').toString(),
    );
  }
}

class AiWeeklySummary {
  final String resumen;
  final double variacionPorcentual;
  final Map<String, dynamic> categoriaTop;
  final String recomendacion;

  AiWeeklySummary({
    required this.resumen,
    required this.variacionPorcentual,
    required this.categoriaTop,
    required this.recomendacion,
  });

  factory AiWeeklySummary.fromJson(Map<String, dynamic> json) {
    final rawCategory = json['categoria_top'];
    return AiWeeklySummary(
      resumen: (json['resumen'] ?? '').toString(),
      variacionPorcentual: (json['variacion_porcentual'] as num? ?? 0).toDouble(),
      categoriaTop: rawCategory is Map
          ? Map<String, dynamic>.from(rawCategory)
          : {'nombre': 'N/A', 'monto': 0},
      recomendacion: (json['recomendacion'] ?? '').toString(),
    );
  }
}
