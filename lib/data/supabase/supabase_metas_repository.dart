import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/meta_ahorro.dart';
import '../../domain/repositories/metas_repository.dart';

class SupabaseMetasRepository implements MetasRepository {
  SupabaseMetasRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Stream<List<MetaAhorro>> watchMetas() {
    return _client
        .from('metas_ahorro')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map((row) => MetaAhorro.fromMap(row)).toList());
  }

  @override
  Future<void> upsertMeta(MetaAhorro meta) async {
    final payload = meta.toMap();
    final id = meta.id;
    if (id != null) {
      payload.remove('id');
      await _client.from('metas_ahorro').update(payload).eq('id', id);
      return;
    }
    await _client.from('metas_ahorro').insert(payload);
  }

  @override
  Future<void> abonarMeta({
    required int id,
    required int montoAbono,
    required int montoMeta,
    required int montoActual,
  }) async {
    final nuevoMonto = montoActual + montoAbono;
    await _client
        .from('metas_ahorro')
        .update({
          'monto_actual': nuevoMonto,
          'completada': nuevoMonto >= montoMeta,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  @override
  Future<void> deleteMeta(int id) async {
    await _client.from('metas_ahorro').delete().eq('id', id);
  }
}
