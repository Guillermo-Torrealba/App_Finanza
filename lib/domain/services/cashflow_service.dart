import '../models/movimiento.dart';

class CashflowMonthSummary {
  const CashflowMonthSummary({
    required this.ingresos,
    required this.gastos,
  });

  final int ingresos;
  final int gastos;

  int get flujo => ingresos - gastos;
}

class CashflowPoint {
  const CashflowPoint({
    required this.month,
    required this.year,
    required this.flujo,
  });

  final int month;
  final int year;
  final int flujo;
}

class CashflowService {
  const CashflowService();

  CashflowMonthSummary resumenDelMes(
    List<Movimiento> movimientos,
    DateTime mes, {
    Set<String>? cuentasIncluidas,
  }) {
    var ingresos = 0;
    var gastos = 0;

    for (final mov in movimientos) {
      if (mov.fecha.year != mes.year || mov.fecha.month != mes.month) {
        continue;
      }
      if (cuentasIncluidas != null && !cuentasIncluidas.contains(mov.cuenta)) {
        continue;
      }
      if (mov.categoria == 'Transferencia' || mov.categoria == 'Ajuste') {
        continue;
      }
      if (mov.esIngreso) {
        ingresos += mov.monto;
      } else if (mov.esGasto) {
        gastos += mov.monto;
      }
    }

    return CashflowMonthSummary(ingresos: ingresos, gastos: gastos);
  }

  List<CashflowPoint> serieFlujo(
    List<Movimiento> movimientos, {
    required DateTime desdeMes,
    required int meses,
    Set<String>? cuentasIncluidas,
  }) {
    final output = <CashflowPoint>[];
    for (var i = 0; i < meses; i++) {
      final mes = DateTime(desdeMes.year, desdeMes.month + i, 1);
      final resumen = resumenDelMes(
        movimientos,
        mes,
        cuentasIncluidas: cuentasIncluidas,
      );
      output.add(
        CashflowPoint(month: mes.month, year: mes.year, flujo: resumen.flujo),
      );
    }
    return output;
  }
}
