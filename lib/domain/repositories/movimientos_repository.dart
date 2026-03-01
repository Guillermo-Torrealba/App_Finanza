import '../models/movimiento.dart';

abstract class MovimientosRepository {
  Stream<List<Movimiento>> watchMovimientos();
  Future<void> createMovimiento(Movimiento movimiento);
  Future<void> updateMovimiento(Movimiento movimiento);
  Future<void> deleteMovimiento(int id);
  Future<void> transferirEntreCuentas({
    required String userId,
    required DateTime fecha,
    required int monto,
    required String cuentaOrigen,
    required String cuentaDestino,
    String detalle,
  });
}
