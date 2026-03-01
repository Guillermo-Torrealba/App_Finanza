import '../models/credit_cycle_summary.dart';

abstract class CreditosRepository {
  Future<CreditCycleSummary> calcularResumenCiclo({
    required String userId,
    required int billingDay,
    required int dueDay,
    DateTime? now,
  });

  Future<void> registrarAbonoTarjeta({
    required String userId,
    required DateTime fecha,
    required int monto,
    required String cuenta,
    String itemAbono,
  });

  Future<void> registrarPagoCuotaConsumo({
    required String userId,
    required DateTime fecha,
    required String nombreCredito,
    required int numeroCuota,
    required int totalCuotas,
    required int montoCuota,
    required String cuenta,
  });
}
