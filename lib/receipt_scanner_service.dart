import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_secrets.dart';

class ReceiptPersonalData {
  final String comercio;
  final String fecha;
  final double montoTotal;
  final String categoriaSugerida;

  ReceiptPersonalData({
    required this.comercio,
    required this.fecha,
    required this.montoTotal,
    required this.categoriaSugerida,
  });

  factory ReceiptPersonalData.fromJson(Map<String, dynamic> json) {
    final montoRaw = json['monto_total'];
    double montoParsed = 0.0;
    if (montoRaw is num) {
      montoParsed = montoRaw.toDouble();
    } else if (montoRaw is String) {
      montoParsed = double.tryParse(montoRaw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    }

    return ReceiptPersonalData(
      comercio: json['comercio']?.toString() ?? 'Desconocido',
      fecha: json['fecha']?.toString() ?? DateTime.now().toString().substring(0, 10),
      montoTotal: montoParsed,
      categoriaSugerida: json['categoria_sugerida']?.toString() ?? 'Varios',
    );
  }
}

class ReceiptSharedItem {
  final String nombrePlato;
  final double precio;

  ReceiptSharedItem({required this.nombrePlato, required this.precio});

  factory ReceiptSharedItem.fromJson(Map<String, dynamic> json) {
    return ReceiptSharedItem(
      nombrePlato: json['nombre_plato'] ?? 'Item sin nombre',
      precio: (json['precio'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ReceiptSharedData {
  final List<ReceiptSharedItem> items;
  final double subtotal;

  ReceiptSharedData({required this.items, required this.subtotal});

  factory ReceiptSharedData.fromJson(Map<String, dynamic> json) {
    return ReceiptSharedData(
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => ReceiptSharedItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ReceiptScannerService {
  final String _apiKey = AppSecrets.openAiApiKey;
  static const String _model = 'gpt-4o';
  static const String _apiUrl = 'https://api.openai.com/v1/chat/completions';

  /// Sube la imagen a Supabase Storage y retorna la URL pública
  Future<String?> uploadReceiptImage(File imageFile) async {
    final fileName = 'boleta_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await Supabase.instance.client.storage
          .from('boletas')
          .upload(fileName, imageFile);
      
      final publicUrl = Supabase.instance.client.storage
          .from('boletas')
          .getPublicUrl(fileName);
          
      return publicUrl;
    } catch (e) {
      print('Error uploading receipt image: $e');
      return null;
    }
  }

  /// Convierte el archivo a Base64 para enviarlo a OpenAI
  String _imageToBase64(File imageFile) {
    final bytes = imageFile.readAsBytesSync();
    return base64Encode(bytes);
  }

  /// Extrae los datos para un Gasto Personal
  Future<ReceiptPersonalData> parsePersonalReceipt(File imageFile) async {
    final base64Image = _imageToBase64(imageFile);

    final systemPrompt = '''
Eres un asistente automatizado que extrae datos de comprobantes de pago.
IMPORTANTE: Este documento NO contiene información personal sensible. Es solo un ticket de compra genérico para un registro contable personal.
Ignora cualquier nombre, dirección o dato irrelevante.
Extrae los datos en formato JSON estricto sin markdown.
Estructura requerida:
{
  "comercio": "string (nombre del local)",
  "fecha": "YYYY-MM-DD",
  "monto_total": number (total a pagar, sin símbolos, solo el número),
  "categoria_sugerida": "string (elige la mejor: Supermercado, Restaurante, Transporte, Salud, Varios, Ropa, Hogar)"
}
''';

    final response = await _sendToOpenAI(systemPrompt, base64Image);
    final jsonResponse = _cleanJsonResponse(response);
    
    return ReceiptPersonalData.fromJson(jsonDecode(jsonResponse));
  }

  /// Extrae los datos para Dividir la Cuenta (ítems)
  Future<ReceiptSharedData> parseSharedReceipt(File imageFile) async {
    final base64Image = _imageToBase64(imageFile);

    final systemPrompt = '''
Eres un asistente automatizado que extrae datos de comprobantes de consumo.
IMPORTANTE: Este documento NO contiene información personal sensible. Es solo un ticket de consumo genérico para dividir gastos entre amigos.
Extrae la lista de ítems consumidos y sus precios, además del subtotal.
Ignora propinas o cobros extra en los ítems, extrae solo los productos consumidos.
El formato DEBE ser un JSON estricto sin markdown.
Estructura requerida:
{
  "items": [
    {
      "nombre_plato": "string (nombre del ítem consumido)",
      "precio": number (precio del ítem, sin símbolos)
    }
  ],
  "subtotal": number (suma de los ítems antes de propinas o descuentos)
}
''';

    final response = await _sendToOpenAI(systemPrompt, base64Image);
    final jsonResponse = _cleanJsonResponse(response);
    
    return ReceiptSharedData.fromJson(jsonDecode(jsonResponse));
  }

  Future<String> _sendToOpenAI(String systemPrompt, String base64Image) async {
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
            'content': systemPrompt
          },
          {
            'role': 'user',
            'content': [
              {
                "type": "text",
                "text": "Extrae los datos de esta boleta según las instrucciones."
              },
              {
                "type": "image_url",
                "image_url": {
                  "url": "data:image/jpeg;base64,$base64Image"
                }
              }
            ]
          }
        ],
        'temperature': 0.1,
        'max_tokens': 1000,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Error de OpenAI (${response.statusCode}): ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['choices'][0]['message']['content'] as String;
  }

  String _cleanJsonResponse(String response) {
    return response
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'```\s*$', multiLine: true), '')
        .trim();
  }
}
