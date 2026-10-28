import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

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
    final raw = json['monto_total'];
    final amount = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0;
    return ReceiptPersonalData(
      comercio: json['comercio']?.toString() ?? 'Desconocido',
      fecha: json['fecha']?.toString() ?? '',
      montoTotal: amount,
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
      nombrePlato: json['nombre_plato']?.toString() ?? 'Item sin nombre',
      precio: (json['precio'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ReceiptSharedData {
  final List<ReceiptSharedItem> items;
  final double subtotal;

  ReceiptSharedData({required this.items, required this.subtotal});

  factory ReceiptSharedData.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ReceiptSharedData(
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => ReceiptSharedItem.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ReceiptScannerService {
  static const _bucket = 'boletas';
  static const _maxImageBytes = 5_900_000;
  static final _secureRandom = Random.secure();

  /// Sube el archivo bajo el UUID del usuario y devuelve una referencia estable.
  Future<String?> uploadReceiptImage(File imageFile) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return null;

      final path = '${user.id}/${_newUUID()}.jpg';
      await client.storage
          .from(_bucket)
          .upload(
            path,
            imageFile,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      if (client.auth.currentUser?.id != user.id) {
        // Never return a reference for a user who is no longer signed in.
        // Any confirmed orphan remains owner-prefixed and inaccessible to others.
        return null;
      }
      return client.storage.from(_bucket).getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  String _newUUID() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<Map<String, dynamic>> _parseReceipt(File imageFile, String mode) async {
    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty || bytes.length > _maxImageBytes) {
      throw const FormatException('La imagen excede el tamaño permitido.');
    }
    final response = await Supabase.instance.client.functions.invoke(
      'receipt_scan',
      body: {'mode': mode, 'image_base64': base64Encode(bytes)},
    );
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw const FormatException('El servicio devolvió una respuesta inválida.');
  }

  Future<ReceiptPersonalData> parsePersonalReceipt(File imageFile) async =>
      ReceiptPersonalData.fromJson(await _parseReceipt(imageFile, 'personal'));

  Future<ReceiptSharedData> parseSharedReceipt(File imageFile) async =>
      ReceiptSharedData.fromJson(await _parseReceipt(imageFile, 'shared'));
}
