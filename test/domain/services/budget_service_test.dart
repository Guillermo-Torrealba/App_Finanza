import 'package:app_finanzas/domain/models/movimiento.dart';
import 'package:app_finanzas/domain/services/budget_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calcularEjecucion entrega gasto total y por categoria', () {
    const service = BudgetService();
    final movimientos = [
      Movimiento(
        fecha: DateTime(2026, 2, 1),
        item: 'Super',
        monto: 100000,
        categoria: 'Comida',
        cuenta: 'Banco',
        tipo: 'Gasto',
      ),
      Movimiento(
        fecha: DateTime(2026, 2, 2),
        item: 'Bencina',
        monto: 40000,
        categoria: 'Transporte',
        cuenta: 'Banco',
        tipo: 'Gasto',
      ),
      Movimiento(
        fecha: DateTime(2026, 2, 3),
        item: 'Sueldo',
        monto: 900000,
        categoria: 'Sueldo',
        cuenta: 'Banco',
        tipo: 'Ingreso',
      ),
    ];

    final result = service.calcularEjecucion(
      movimientosDelMes: movimientos,
      presupuestoGlobal: 300000,
      presupuestosPorCategoria: const {'Comida': 150000, 'Transporte': 50000},
    );

    expect(result.gastoTotal, 140000);
    expect(result.restanteGlobal, 160000);
    final comida = result.byCategory.firstWhere((x) => x.categoria == 'Comida');
    expect(comida.gastado, 100000);
    expect(comida.restante, 50000);
  });
}
