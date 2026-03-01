import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/recurrente_programado.dart';
import '../../domain/repositories/recurrentes_repository.dart';

class SupabaseRecurrentesRepository implements RecurrentesRepository {
  SupabaseRecurrentesRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Stream<List<RecurrenteProgramado>> watchRecurrentes() {
    return _client
        .from('gastos_programados')
        .stream(primaryKey: ['id'])
        .order('fecha_proximo_pago', ascending: true)
        .map(
          (rows) => rows
              .map((row) => RecurrenteProgramado.fromMap(row))
              .toList(growable: false),
        );
  }

  @override
  Future<void> upsertRecurrente(RecurrenteProgramado recurrente) async {
    final id = recurrente.id;
    final payload = recurrente.toMap();
    if (id != null) {
      payload.remove('id');
      await _client.from('gastos_programados').update(payload).eq('id', id);
      return;
    }
    await _client.from('gastos_programados').insert(payload);
  }

  @override
  Future<void> deleteRecurrente(int id) async {
    await _client.from('gastos_programados').delete().eq('id', id);
  }

  @override
  Future<int> ejecutarPendientes({
    required String userId,
    required DateTime fechaEjecucion,
  }) async {
    final response = await _client
        .from('gastos_programados')
        .select()
        .eq('user_id', userId)
        .eq('activo', true)
        .lte('fecha_proximo_pago', fechaEjecucion.toIso8601String());
    final pendientes = List<Map<String, dynamic>>.from(response);
    if (pendientes.isEmpty) {
      return 0;
    }

    for (final p in pendientes) {
      await _client.from('gastos').insert({
        'user_id': userId,
        'fecha': fechaEjecucion.toIso8601String(),
        'item': p['item'],
        'monto': p['monto'],
        'categoria': p['categoria'],
        'cuenta': p['cuenta'],
        'tipo': p['tipo'],
      });

      final fechaActual = DateTime.parse((p['fecha_proximo_pago'] ?? '').toString());
      var nuevaFecha = fechaActual;
      final frecuencia = (p['frecuencia'] ?? '').toString();

      if (frecuencia == 'Mensual') {
        final newMonth = fechaActual.month + 1;
        final year = fechaActual.year + (newMonth > 12 ? 1 : 0);
        final month = newMonth > 12 ? 1 : newMonth;
        final day = fechaActual.day;
        final daysInNextMonth = DateUtils.getDaysInMonth(year, month);
        nuevaFecha = DateTime(year, month, day > daysInNextMonth ? daysInNextMonth : day);
      } else if (frecuencia == 'Semanal') {
        nuevaFecha = fechaActual.add(const Duration(days: 7));
      } else if (frecuencia == 'Anual') {
        nuevaFecha = DateTime(
          fechaActual.year + 1,
          fechaActual.month,
          fechaActual.day,
        );
      } else if (frecuencia == 'Unico') {
        await _client
            .from('gastos_programados')
            .update({'activo': false})
            .eq('id', p['id']);
        continue;
      }

      await _client
          .from('gastos_programados')
          .update({'fecha_proximo_pago': nuevaFecha.toIso8601String()})
          .eq('id', p['id']);
    }

    return pendientes.length;
  }
}
