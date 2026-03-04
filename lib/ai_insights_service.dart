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
}
