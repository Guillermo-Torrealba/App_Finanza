enum FinancialAlertSeverity { info, warning, critical }

class FinancialAlert {
  const FinancialAlert({
    required this.title,
    required this.message,
    this.severity = FinancialAlertSeverity.info,
  });

  final String title;
  final String message;
  final FinancialAlertSeverity severity;
}
