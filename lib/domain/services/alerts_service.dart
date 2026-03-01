import '../models/financial_alert.dart';
import '../models/movimiento.dart';

class AlertsService {
  const AlertsService();

  List<FinancialAlert> generarAlertas({
    required List<Movimiento> movimientosDelMes,
    required int? presupuestoGlobal,
    required double umbralPresupuesto,
  }) {
    final alerts = <FinancialAlert>[];

    var ingresos = 0;
    var gastos = 0;
    for (final mov in movimientosDelMes) {
      if (mov.categoria == 'Transferencia' || mov.categoria == 'Ajuste') {
        continue;
      }
      if (mov.esIngreso) {
        ingresos += mov.monto;
      } else if (mov.esGasto) {
        gastos += mov.monto;
      }
    }

    if (ingresos - gastos < 0) {
      alerts.add(
        const FinancialAlert(
          title: 'Flujo negativo',
          message: 'Tus gastos superan tus ingresos en el mes actual.',
          severity: FinancialAlertSeverity.warning,
        ),
      );
    }

    if (presupuestoGlobal != null && presupuestoGlobal > 0) {
      final consumo = (gastos / presupuestoGlobal) * 100;
      if (consumo >= umbralPresupuesto) {
        alerts.add(
          FinancialAlert(
            title: 'Presupuesto alto',
            message:
                'Llevas ${consumo.toStringAsFixed(1)}% del presupuesto mensual.',
            severity: FinancialAlertSeverity.critical,
          ),
        );
      }
    }

    return alerts;
  }
}
