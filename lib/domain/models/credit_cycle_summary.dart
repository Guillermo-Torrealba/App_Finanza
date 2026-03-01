class CreditCycleSummary {
  const CreditCycleSummary({
    required this.cycleStart,
    required this.cycleEnd,
    required this.lastCycleStart,
    required this.lastCycleEnd,
    required this.dueDate,
    required this.facturadoPendiente,
    required this.porFacturarPendiente,
    required this.pagosPeriodo,
  });

  final DateTime cycleStart;
  final DateTime cycleEnd;
  final DateTime lastCycleStart;
  final DateTime lastCycleEnd;
  final DateTime dueDate;
  final int facturadoPendiente;
  final int porFacturarPendiente;
  final int pagosPeriodo;

  int get totalUtilizado => facturadoPendiente + porFacturarPendiente;
  int diasAlVencimientoDesde(DateTime referenceDate) {
    final base = DateTime(referenceDate.year, referenceDate.month, referenceDate.day);
    return dueDate.difference(base).inDays;
  }
}
