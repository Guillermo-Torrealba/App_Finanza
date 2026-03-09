import 'dart:convert';
import 'package:http/http.dart' as http;

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
    return AiInsightsResult(
      resumen: json['resumen'] ?? '',
      insights: (json['insights'] as List<dynamic>? ?? [])
          .map((e) => AiInsight.fromJson(e as Map<String, dynamic>))
          .toList(),
      recomendaciones: (json['recomendaciones'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class AiInsight {
  final String titulo;
  final String descripcion;
  final String tipo; // 'positivo', 'alerta', 'negativo'

  AiInsight({
    required this.titulo,
    required this.descripcion,
    required this.tipo,
  });

  factory AiInsight.fromJson(Map<String, dynamic> json) {
    return AiInsight(
      titulo: json['titulo'] ?? '',
      descripcion: json['descripcion'] ?? '',
      tipo: json['tipo'] ?? 'info',
    );
  }
}

class AiInsightsService {
  final String _apiKey;
  static const String _model = 'gpt-4o-mini';
  static const String _apiUrl = 'https://api.openai.com/v1/chat/completions';

  AiInsightsService({required String apiKey}) : _apiKey = apiKey;

  // Cache simple para no repetir la misma consulta
  String? _lastFingerprint;
  AiInsightsResult? _cachedResult;

  /// Analiza las finanzas del usuario y retorna insights.
  /// [resumen] contiene los datos financieros del mes (sin info personal).
  Future<AiInsightsResult> analyzeFinances(Map<String, dynamic> resumen) async {
    // Fingerprint basado en los datos para cache
    final fingerprint = jsonEncode(resumen);
    if (fingerprint == _lastFingerprint && _cachedResult != null) {
      return _cachedResult!;
    }

    final systemPrompt = '''
Eres un asesor financiero personal experto, amigable y directo.
Analiza los datos financieros del usuario y genera insights accionables.

REGLAS:
- Sé conciso pero específico. Usa los números reales.
- Adapta el tono: celebra logros, advierte problemas sin ser alarmista.
- Los montos están en la moneda indicada en "moneda". Formatea los montos con separador de miles usando punto (.) 
- Responde SIEMPRE en español.
- Responde ÚNICAMENTE con un JSON válido (sin markdown, sin ```json, sin texto antes ni después).

El JSON debe tener esta estructura exacta:
{
  "resumen": "2-3 oraciones con el panorama general del mes",
  "insights": [
    {
      "titulo": "Título corto del insight",
      "descripcion": "Explicación detallada con números",
      "tipo": "positivo|alerta|negativo"
    }
  ],
  "recomendaciones": [
    "Recomendación accionable 1",
    "Recomendación accionable 2"
  ]
}

Genera entre 3 y 5 insights y 2 recomendaciones.
''';

    final userMessage =
        '''
Aquí están mis datos financieros del mes:

${const JsonEncoder.withIndent('  ').convert(resumen)}

Analiza mis finanzas y dame insights útiles.
''';

    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'temperature': 0.7,
        'max_tokens': 1500,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Error de API OpenAI (${response.statusCode}): ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['choices'][0]['message']['content'] as String;

    // Limpiar posibles backticks markdown que el LLM a veces agrega
    final cleanContent = content
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'```\s*$', multiLine: true), '')
        .trim();

    final parsed = jsonDecode(cleanContent) as Map<String, dynamic>;
    final result = AiInsightsResult.fromJson(parsed);

    _lastFingerprint = fingerprint;
    _cachedResult = result;

    return result;
  }

  /// Invalida el cache (ej. cuando cambian los datos).
  void invalidateCache() {
    _lastFingerprint = null;
    _cachedResult = null;
  }

  // ── Auto-Categorización ──

  final Map<String, String> _categoryCache = {};

  /// Sugiere la mejor categoría para un concepto de gasto.
  /// Retorna el nombre exacto de una de las [categorias] disponibles.
  /// Retorna null si no puede determinar o hay error.
  Future<String?> suggestCategory(
    String concepto,
    List<String> categorias,
  ) async {
    if (concepto.trim().length < 3 || categorias.isEmpty) return null;

    final cacheKey = '${concepto.trim().toLowerCase()}|${categorias.join(",")}';
    if (_categoryCache.containsKey(cacheKey)) {
      return _categoryCache[cacheKey];
    }

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content':
                  'Eres un clasificador de gastos. El usuario te da el nombre de un gasto y tú respondes ÚNICAMENTE con el nombre exacto de la categoría más apropiada de la lista. No agregues puntuación, explicaciones ni nada más. Solo el nombre de la categoría.',
            },
            {
              'role': 'user',
              'content':
                  'Categorías disponibles: ${categorias.join(", ")}\n\nGasto: "$concepto"\n\nCategoría:',
            },
          ],
          'temperature': 0.1,
          'max_tokens': 20,
        }),
      );

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestion = (body['choices'][0]['message']['content'] as String)
          .trim();

      // Verificar que la respuesta es una categoría válida
      final match = categorias.firstWhere(
        (c) => c.toLowerCase() == suggestion.toLowerCase(),
        orElse: () => '',
      );

      if (match.isNotEmpty) {
        _categoryCache[cacheKey] = match;
        return match;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Alertas Proactivas IA ──

  /// Genera alertas inteligentes basadas en patrones de gasto recientes.
  /// [datosRecientes] contiene gastos de los últimos 7 días desglosados.
  Future<List<AiProactiveAlert>> generateProactiveAlerts(
    Map<String, dynamic> datosRecientes,
  ) async {
    if (datosRecientes.isEmpty) return [];

    try {
      final systemPrompt = '''
Eres un asesor financiero que detecta patrones preocupantes o notables en los gastos recientes.
Analiza los datos de los últimos 7 días y genera entre 0 y 3 alertas cortas y accionables.

REGLAS:
- Solo genera alertas si hay algo RELEVANTE (patrón repetitivo, gasto inusual, ritmo peligroso, etc.).
- Si todo está normal y bajo control, devuelve una lista vacía [].
- Sé específico: usa números reales, nombres de categorías, días concretos.
- Los montos están en la moneda indicada. Formatea con separador de miles usando punto (.).
- Responde SIEMPRE en español.
- Responde ÚNICAMENTE con un JSON válido (sin markdown, sin texto extra).
- Cada alerta debe tener un tono diferente: "alerta" (preocupante), "negativo" (urgente), "tip" (consejo positivo).

JSON de respuesta (array):
[
  {
    "titulo": "Título corto y directo (máx 6 palabras)",
    "mensaje": "Explicación concisa con números (máx 2 oraciones)",
    "tipo": "alerta|negativo|tip"
  }
]

Si no hay nada relevante, responde: []
''';

      final userMessage =
          '''
Datos financieros de los últimos 7 días:

${const JsonEncoder.withIndent('  ').convert(datosRecientes)}

Genera alertas solo si detectas algo relevante.
''';

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userMessage},
          ],
          'temperature': 0.5,
          'max_tokens': 600,
        }),
      );

      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final content = (body['choices'][0]['message']['content'] as String)
          .trim();

      final cleanContent = content
          .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'```\s*$', multiLine: true), '')
          .trim();

      final parsed = jsonDecode(cleanContent);
      if (parsed is List) {
        return parsed
            .map((e) => AiProactiveAlert.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ── Resumen Semanal IA ──

  /// Genera un resumen narrativo de la semana financiera.
  Future<AiWeeklySummary?> generateWeeklySummary(
    Map<String, dynamic> datosSemana,
  ) async {
    if (datosSemana.isEmpty) return null;

    try {
      final systemPrompt = '''
Eres un asesor financiero amigable y directo. Resume la semana financiera del usuario.

REGLAS:
- Sé conciso: el resumen debe ser 2-3 oraciones máximo.
- Compara con la semana anterior si los datos están disponibles.
- Menciona la categoría donde más gastó.
- Da UNA recomendación accionable y específica.
- Los montos están en la moneda indicada. Formatea con separador de miles usando punto (.).
- Responde SIEMPRE en español.
- Responde ÚNICAMENTE con JSON válido (sin markdown, sin texto extra).

JSON de respuesta:
{
  "resumen": "2-3 oraciones resumiendo la semana",
  "variacion_porcentual": 15.5,
  "categoria_top": {"nombre": "Comida", "monto": 45000},
  "recomendacion": "Recomendación accionable y específica"
}
''';

      final userMessage =
          '''
Datos de mi semana financiera:

${const JsonEncoder.withIndent('  ').convert(datosSemana)}

Dame un resumen de mi semana.
''';

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userMessage},
          ],
          'temperature': 0.6,
          'max_tokens': 500,
        }),
      );

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final content = (body['choices'][0]['message']['content'] as String)
          .trim();

      final cleanContent = content
          .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'```\s*$', multiLine: true), '')
          .trim();

      final parsed = jsonDecode(cleanContent) as Map<String, dynamic>;
      return AiWeeklySummary.fromJson(parsed);
    } catch (_) {
      return null;
    }
  }

  // ── Entrada por Lenguaje Natural ──

  /// Parsea texto libre (escrito o transcrito de voz) en una transacción.
  Future<ParsedTransaction?> parseNaturalLanguage(
    String texto, {
    required List<String> categoriasGasto,
    required List<String> categoriasIngreso,
    required List<String> cuentas,
    required String fechaHoy,
  }) async {
    if (texto.trim().length < 3) return null;

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content':
                  '''Eres un parser de transacciones financieras. El usuario te describe un gasto o ingreso en lenguaje natural (texto o voz transcrita) y tú extraes los datos estructurados.

Fecha de hoy: $fechaHoy

REGLAS:
- Si dice "ayer", "anteayer", "el lunes", etc., calcula la fecha correcta relativa a hoy.
- Si no menciona fecha, usa la fecha de hoy.
- Si no menciona tipo, asume "Gasto".
- Si dice "me pagaron", "recibí", "cobré", "ingresé", "sueldo", "bono" → es "Ingreso".
- El monto puede venir como "15 lucas" (15000), "5 luca" (5000), "100 pesos" (100), "mil" (1000), etc.
- Elige la categoría más apropiada de las listas proporcionadas.
- Si menciona una cuenta específica, úsala; si no, deja null.
- Para metodo_pago: si dice "con tarjeta", "crédito", "a crédito", "con la tarjeta" → "Credito". Si dice "efectivo", "débito", "transferencia" o no menciona nada → "Debito".
- Responde ÚNICAMENTE con JSON válido, sin markdown ni texto extra.

Categorías de gasto: ${categoriasGasto.join(", ")}
Categorías de ingreso: ${categoriasIngreso.join(", ")}
Cuentas disponibles: ${cuentas.join(", ")}

JSON de respuesta:
{
  "tipo": "Gasto" o "Ingreso",
  "item": "nombre descriptivo corto",
  "monto": 15000,
  "categoria": "categoría elegida",
  "fecha": "2026-03-03",
  "cuenta": "nombre cuenta o null",
  "metodo_pago": "Debito" o "Credito"
}''',
            },
            {'role': 'user', 'content': texto},
          ],
          'temperature': 0.1,
          'max_tokens': 150,
        }),
      );

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final content = (body['choices'][0]['message']['content'] as String)
          .trim();

      final cleanContent = content
          .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'```\s*$', multiLine: true), '')
          .trim();

      final parsed = jsonDecode(cleanContent) as Map<String, dynamic>;
      return ParsedTransaction.fromJson(parsed);
    } catch (_) {
      return null;
    }
  }
}

/// Transacción parseada desde lenguaje natural.
class ParsedTransaction {
  final String tipo;
  final String item;
  final int monto;
  final String categoria;
  final String fecha; // yyyy-MM-dd
  final String? cuenta;
  final String metodoPago; // 'Debito' o 'Credito'

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

/// Alerta proactiva generada por IA.
class AiProactiveAlert {
  final String titulo;
  final String mensaje;
  final String tipo; // 'alerta', 'negativo', 'tip'

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

/// Resumen semanal generado por IA.
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
    return AiWeeklySummary(
      resumen: (json['resumen'] ?? '').toString(),
      variacionPorcentual: (json['variacion_porcentual'] as num? ?? 0)
          .toDouble(),
      categoriaTop:
          (json['categoria_top'] as Map<String, dynamic>?) ??
          {'nombre': 'N/A', 'monto': 0},
      recomendacion: (json['recomendacion'] ?? '').toString(),
    );
  }
}
