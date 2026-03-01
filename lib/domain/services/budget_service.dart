import '../models/movimiento.dart';

class CategoryBudgetExecution {
  const CategoryBudgetExecution({
    required this.categoria,
    required this.presupuesto,
    required this.gastado,
  });

  final String categoria;
  final int presupuesto;
  final int gastado;

  int get restante => presupuesto - gastado;
  double get porcentaje => presupuesto <= 0 ? 0 : (gastado / presupuesto);
}

class BudgetExecution {
  const BudgetExecution({
    required this.gastoTotal,
    required this.presupuestoGlobal,
    required this.byCategory,
  });

  final int gastoTotal;
  final int presupuestoGlobal;
  final List<CategoryBudgetExecution> byCategory;

  double get porcentajeGlobal =>
      presupuestoGlobal <= 0 ? 0 : (gastoTotal / presupuestoGlobal);
  int get restanteGlobal => presupuestoGlobal - gastoTotal;
}

class BudgetService {
  const BudgetService();

  BudgetExecution calcularEjecucion({
    required List<Movimiento> movimientosDelMes,
    required int presupuestoGlobal,
    required Map<String, int> presupuestosPorCategoria,
  }) {
    var gastoTotal = 0;
    final gastoPorCategoria = <String, int>{};

    for (final mov in movimientosDelMes) {
      if (!mov.esGasto) {
        continue;
      }
      if (mov.categoria == 'Transferencia' || mov.categoria == 'Ajuste') {
        continue;
      }
      gastoTotal += mov.monto;
      gastoPorCategoria[mov.categoria] =
          (gastoPorCategoria[mov.categoria] ?? 0) + mov.monto;
    }

    final byCategory = presupuestosPorCategoria.entries
        .map(
          (entry) => CategoryBudgetExecution(
            categoria: entry.key,
            presupuesto: entry.value,
            gastado: gastoPorCategoria[entry.key] ?? 0,
          ),
        )
        .toList();

    return BudgetExecution(
      gastoTotal: gastoTotal,
      presupuestoGlobal: presupuestoGlobal,
      byCategory: byCategory,
    );
  }
}
