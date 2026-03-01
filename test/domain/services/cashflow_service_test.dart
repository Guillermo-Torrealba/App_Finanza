import 'package:app_finanzas/domain/models/movimiento.dart';
import 'package:app_finanzas/domain/services/cashflow_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resumenDelMes calcula ingresos, gastos y flujo', () {
    const service = CashflowService();
    final movimientos = [
      Movimiento(
        fecha: DateTime(2026, 2, 3),
        item: 'Sueldo',
        monto: 1500000,
        categoria: 'Sueldo',
        cuenta: 'Banco',
        tipo: 'Ingreso',
      ),
      Movimiento(
        fecha: DateTime(2026, 2, 10),
        item: 'Super',
        monto: 120000,
        categoria: 'Comida',
        cuenta: 'Banco',
        tipo: 'Gasto',
      ),
      Movimiento(
        fecha: DateTime(2026, 2, 11),
        item: 'Transferencia',
        monto: 50000,
        categoria: 'Transferencia',
        cuenta: 'Banco',
        tipo: 'Gasto',
      ),
    ];

    final resumen = service.resumenDelMes(movimientos, DateTime(2026, 2, 1));

    expect(resumen.ingresos, 1500000);
    expect(resumen.gastos, 120000);
    expect(resumen.flujo, 1380000);
  });
}
