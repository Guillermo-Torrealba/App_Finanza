import '../models/credit_cycle_summary.dart';
import '../models/movimiento.dart';

class CreditCycleWindow {
  const CreditCycleWindow({
    required this.cycleStart,
    required this.cycleEnd,
    required this.lastCycleStart,
    required this.lastCycleEnd,
    required this.dueDate,
  });

  final DateTime cycleStart;
  final DateTime cycleEnd;
  final DateTime lastCycleStart;
  final DateTime lastCycleEnd;
  final DateTime dueDate;
}

class CreditCycleService {
  const CreditCycleService();

  CreditCycleWindow resolveWindow({
    required DateTime now,
    required int billingDay,
    required int dueDay,
  }) {
    final effectiveBillingDay = billingDay.clamp(1, 31);
    final cutoffThisMonth = DateTime(now.year, now.month, effectiveBillingDay);

    late final DateTime cycleStart;
    late final DateTime cycleEnd;
    late final DateTime lastCycleStart;
    late final DateTime lastCycleEnd;

    if (now.isAfter(cutoffThisMonth)) {
      cycleStart = cutoffThisMonth.add(const Duration(days: 1));
      cycleEnd = DateTime(now.year, now.month + 1, effectiveBillingDay);
      lastCycleEnd = cutoffThisMonth;
      lastCycleStart = DateTime(
        now.year,
        now.month - 1,
        effectiveBillingDay,
      ).add(const Duration(days: 1));
    } else {
      cycleEnd = cutoffThisMonth;
      cycleStart = DateTime(
        now.year,
        now.month - 1,
        effectiveBillingDay,
      ).add(const Duration(days: 1));
      lastCycleEnd = cycleStart.subtract(const Duration(days: 1));
      lastCycleStart = DateTime(
        now.year,
        now.month - 2,
        effectiveBillingDay,
      ).add(const Duration(days: 1));
    }

    final effectiveDueDay = dueDay.clamp(1, 31);
    final dueDate = now.day <= effectiveDueDay
        ? DateTime(now.year, now.month, effectiveDueDay)
        : DateTime(now.year, now.month + 1, effectiveDueDay);

    return CreditCycleWindow(
      cycleStart: DateTime(cycleStart.year, cycleStart.month, cycleStart.day),
      cycleEnd: DateTime(cycleEnd.year, cycleEnd.month, cycleEnd.day, 23, 59, 59),
      lastCycleStart: DateTime(
        lastCycleStart.year,
        lastCycleStart.month,
        lastCycleStart.day,
      ),
      lastCycleEnd: DateTime(
        lastCycleEnd.year,
        lastCycleEnd.month,
        lastCycleEnd.day,
        23,
        59,
        59,
      ),
      dueDate: DateTime(dueDate.year, dueDate.month, dueDate.day),
    );
  }

  CreditCycleSummary calcularResumen({
    required List<Movimiento> movimientos,
    required DateTime now,
    required int billingDay,
    required int dueDay,
  }) {
    final window = resolveWindow(now: now, billingDay: billingDay, dueDay: dueDay);
    final nowEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final gastosCredito = movimientos
        .where((m) => m.esCredito && m.esGasto)
        .toList();
    final abonosCredito = movimientos
        .where((m) => m.esCredito && m.esIngreso)
        .toList();

    int sumInRange(List<Movimiento> source, DateTime start, DateTime end) {
      var total = 0;
      for (final m in source) {
        if (!m.fecha.isBefore(start) && !m.fecha.isAfter(end)) {
          total += m.monto;
        }
      }
      return total;
    }

    final porFacturarBruto = sumInRange(
      gastosCredito,
      window.cycleStart,
      window.cycleEnd,
    );
    final facturadoBruto = sumInRange(
      gastosCredito,
      window.lastCycleStart,
      window.lastCycleEnd,
    );
    final pagosPeriodo = sumInRange(
      abonosCredito,
      window.lastCycleStart,
      nowEnd,
    );

    final pagoAFacturado = pagosPeriodo > facturadoBruto
        ? facturadoBruto
        : pagosPeriodo;
    final pagoRestante = pagosPeriodo - pagoAFacturado;
    final facturadoPendiente = facturadoBruto - pagoAFacturado;
    final porFacturarPendiente = (porFacturarBruto - pagoRestante)
        .clamp(0, 1 << 31)
        .toInt();

    return CreditCycleSummary(
      cycleStart: window.cycleStart,
      cycleEnd: window.cycleEnd,
      lastCycleStart: window.lastCycleStart,
      lastCycleEnd: window.lastCycleEnd,
      dueDate: window.dueDate,
      facturadoPendiente: facturadoPendiente,
      porFacturarPendiente: porFacturarPendiente,
      pagosPeriodo: pagosPeriodo,
    );
  }
}
