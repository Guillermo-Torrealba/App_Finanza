import '../models/meta_ahorro.dart';

abstract class MetasRepository {
  Stream<List<MetaAhorro>> watchMetas();
  Future<void> upsertMeta(MetaAhorro meta);
  Future<void> abonarMeta({
    required int id,
    required int montoAbono,
    required int montoMeta,
    required int montoActual,
  });
  Future<void> deleteMeta(int id);
}
