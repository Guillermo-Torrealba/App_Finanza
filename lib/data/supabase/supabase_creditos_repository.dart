import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/credit_cycle_summary.dart';
import '../../domain/models/movimiento.dart';
import '../../domain/repositories/creditos_repository.dart';
import '../../domain/services/credit_cycle_service.dart';

class SupabaseCreditosRepository implements CreditosRepository {
  SupabaseCreditosRepository({
    SupabaseClient? client,
    CreditCycleService? cycleService,
  }) : _client = client ?? Supabase.instance.client,
       _cycleService = cycleService ?? const CreditCycleService();

  final SupabaseClient _client;
  final CreditCycleService _cycleService;

  @override
  Future<CreditCycleSummary> calcularResumenCiclo({
    required String userId,
    required int billingDay,
    required int dueDay,
    DateTime? now,
  }) async {
    final rows = await _client
        .from('gastos')
        .select(
          'id, user_id, fecha, item, detalle, monto, categoria, cuenta, tipo, metodo_pago',
        )
        .eq('user_id', userId)
        .eq('metodo_pago', 'Credito');
    final movimientos = List<Map<String, dynamic>>.from(rows)
        .map((row) => Movimiento.fromMap(row))
        .toList(growable: false);

    return _cycleService.calcularResumen(
      movimientos: movimientos,
      now: now ?? DateTime.now(),
      billingDay: billingDay,
      dueDay: dueDay,
    );
  }

  @override
  Future<void> registrarAbonoTarjeta({
    required String userId,
    required DateTime fecha,
    required int monto,
    required String cuenta,
    String itemAbono = 'Abono TC',
  }) async {
    final fechaIso = fecha.toIso8601String();
    await _client.from('gastos').insert([
      {
        'user_id': userId,
        'fecha': fechaIso,
        'item': itemAbono,
        'monto': monto,
        'categoria': 'Pago TC',
        'cuenta': cuenta,
        'tipo': 'Ingreso',
        'metodo_pago': 'Credito',
      },
      {
        'user_id': userId,
        'fecha': fechaIso,
        'item': itemAbono,
        'monto': monto,
        'categoria': 'Pago TC',
        'cuenta': cuenta,
        'tipo': 'Gasto',
        'metodo_pago': 'Debito',
      },
    ]);
  }

  @override
  Future<void> registrarPagoCuotaConsumo({
    required String userId,
    required DateTime fecha,
    required String nombreCredito,
    required int numeroCuota,
    required int totalCuotas,
    required int montoCuota,
    required String cuenta,
  }) async {
    await _client.from('gastos').insert({
      'user_id': userId,
      'fecha': fecha.toIso8601String().split('T').first,
      'item': '$nombreCredito (Cuota $numeroCuota/$totalCuotas)',
      'monto': montoCuota,
      'categoria': 'Creditos',
      'cuenta': cuenta,
      'tipo': 'Gasto',
      'metodo_pago': 'Debito',
    });
  }
}
