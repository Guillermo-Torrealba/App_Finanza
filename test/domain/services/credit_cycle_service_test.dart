import 'package:app_finanzas/domain/models/movimiento.dart';
import 'package:app_finanzas/domain/services/credit_cycle_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calcularResumen separa facturado y por facturar', () {
    const service = CreditCycleService();
    final now = DateTime(2026, 3, 20);

    final movimientos = [
      Movimiento(
        fecha: DateTime(2026, 2, 18),
        item: 'Compra 1',
        monto: 100000,
        categoria: 'Comida',
        cuenta: 'TC',
        tipo: 'Gasto',
        metodoPago: 'Credito',
      ),
      Movimiento(
        fecha: DateTime(2026, 3, 10),
        item: 'Compra 2',
        monto: 50000,
        categoria: 'Ropa',
        cuenta: 'TC',
        tipo: 'Gasto',
        metodoPago: 'Credito',
      ),
      Movimiento(
        fecha: DateTime(2026, 3, 15),
        item: 'Abono TC',
        monto: 30000,
        categoria: 'Pago TC',
        cuenta: 'TC',
        tipo: 'Ingreso',
        metodoPago: 'Credito',
      ),
    ];

    final result = service.calcularResumen(
      movimientos: movimientos,
      now: now,
      billingDay: 5,
      dueDay: 15,
    );

    expect(result.facturadoPendiente, 70000);
    expect(result.porFacturarPendiente, 50000);
    expect(result.totalUtilizado, 120000);
  });
}
