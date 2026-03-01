import '../models/recurrente_programado.dart';

abstract class RecurrentesRepository {
  Stream<List<RecurrenteProgramado>> watchRecurrentes();
  Future<void> upsertRecurrente(RecurrenteProgramado recurrente);
  Future<int> ejecutarPendientes({
    required String userId,
    required DateTime fechaEjecucion,
  });
  Future<void> deleteRecurrente(int id);
}
