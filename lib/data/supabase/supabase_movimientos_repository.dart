import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/movimiento.dart';
import '../../domain/repositories/movimientos_repository.dart';

class SupabaseMovimientosRepository implements MovimientosRepository {
  SupabaseMovimientosRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Stream<List<Movimiento>> watchMovimientos() {
    return _client
        .from('gastos')
        .stream(primaryKey: ['id'])
        .order('fecha', ascending: false)
        .map(
          (rows) =>
              rows.map((row) => Movimiento.fromMap(row)).toList(growable: false),
        );
  }

  @override
  Future<void> createMovimiento(Movimiento movimiento) async {
    await _client.from('gastos').insert(movimiento.toMap());
  }

  @override
  Future<void> updateMovimiento(Movimiento movimiento) async {
    final id = movimiento.id;
    if (id == null) {
      throw ArgumentError('No se puede actualizar un movimiento sin id');
    }
    final payload = movimiento.toMap()..remove('id')..remove('user_id');
    await _client.from('gastos').update(payload).eq('id', id);
  }

  @override
  Future<void> deleteMovimiento(int id) async {
    await _client.from('gastos').delete().eq('id', id);
  }

  @override
  Future<void> transferirEntreCuentas({
    required String userId,
    required DateTime fecha,
    required int monto,
    required String cuentaOrigen,
    required String cuentaDestino,
    String detalle = '',
  }) async {
    final fechaIso = fecha.toIso8601String();
    await _client.from('gastos').insert([
      {
        'user_id': userId,
        'fecha': fechaIso,
        'item': 'Transf. a $cuentaDestino',
        'detalle': detalle,
        'monto': monto,
        'categoria': 'Transferencia',
        'cuenta': cuentaOrigen,
        'tipo': 'Gasto',
        'metodo_pago': 'Debito',
      },
      {
        'user_id': userId,
        'fecha': fechaIso,
        'item': 'Transf. desde $cuentaOrigen',
        'detalle': detalle,
        'monto': monto,
        'categoria': 'Transferencia',
        'cuenta': cuentaDestino,
        'tipo': 'Ingreso',
        'metodo_pago': 'Debito',
      },
    ]);
  }
}
