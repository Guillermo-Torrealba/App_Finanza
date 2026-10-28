import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

class ReceiptImage extends StatefulWidget {
  const ReceiptImage({super.key, required this.reference});

  final String reference;

  @override
  State<ReceiptImage> createState() => _ReceiptImageState();
}

class _ReceiptImageState extends State<ReceiptImage> {
  late Future<String> _url;

  @override
  void initState() {
    super.initState();
    _url = _resolve(widget.reference);
  }

  @override
  void didUpdateWidget(covariant ReceiptImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) {
      _url = _resolve(widget.reference);
    }
  }

  Future<String> _resolve(String reference) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || !AppConfig.isConfigured) {
      throw const FormatException('La sesión no es válida.');
    }
    final uri = Uri.tryParse(reference);
    final project = Uri.tryParse(AppConfig.supabaseUrl);
    if (uri == null ||
        project == null ||
        uri.scheme != 'https' ||
        uri.origin != project.origin) {
      throw const FormatException('La boleta no pertenece a este proyecto.');
    }
    final segments = uri.pathSegments;
    if (segments.length < 6 ||
        segments[0] != 'storage' ||
        segments[1] != 'v1' ||
        segments[2] != 'object' ||
        segments[3] != 'public' ||
        segments[4] != 'boletas') {
      throw const FormatException('La referencia de boleta no es válida.');
    }

    final objectSegments = segments.sublist(5);
    if (objectSegments.length == 2 && objectSegments.first == user.id) {
      final filename = objectSegments.last;
      if (!RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\.jpg$',
      ).hasMatch(filename)) {
        throw const FormatException('La ruta de boleta no es válida.');
      }
      final path = objectSegments.join('/');
      final signedUrl = await Supabase.instance.client.storage
          .from('boletas')
          .createSignedUrl(path, 600);
      if (Supabase.instance.client.auth.currentUser?.id != user.id) {
        throw const FormatException(
          'La sesión cambió mientras se abría la boleta.',
        );
      }
      return signedUrl;
    }

    // Flat public URLs are legacy references. Keep them readable only during
    // the compatibility period; the private-bucket cutover must migrate them.
    if (objectSegments.length == 1 &&
        RegExp(r'^boleta_[0-9]+\.jpg$').hasMatch(objectSegments.single)) {
      return reference;
    }
    throw const FormatException('No tienes acceso a esta boleta.');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return const Center(child: Text('No se pudo abrir la boleta.'));
          }
          return const Center(child: CircularProgressIndicator());
        }
        return Image.network(
          snapshot.data!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              const Center(child: Text('No se pudo abrir la boleta.')),
        );
      },
    );
  }
}
