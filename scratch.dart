  Widget _construirPaginaPresupuestos(
    List<Map<String, dynamic>> todosLosDatos,
  ) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase.from('gastos_programados').stream(primaryKey: ['id']).eq('activo', true),
      builder: (context, snapshotProgramados) {
        return AnimatedBuilder(
          animation: widget.settingsController,
          builder: (context, _) {
            final settings = widget.settingsController.settings;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final formatCurrency = NumberFormat.simpleCurrency(locale: settings.localeCode);

            // Calcular ingresos y fijos desde gastos_programados
            int ingresoFijo = 0;
            int gastoFijo = 0;
            int ahorro = 0;
            int cuota = 0;
            
            if (snapshotProgramados.hasData) {
              for (final p in snapshotProgramados.data!) {
                final monto = (p['monto'] as num).toInt();
                final tipo = p['tipo'] as String;
                if (tipo == 'Ingreso') {
                  ingresoFijo += monto;
                } else if (tipo == 'Ahorro') {
                  ahorro += monto;
                } else if (tipo == 'Cuota') {
                  cuota += monto;
                } else {
                  gastoFijo += monto;
                }
              }
            }
            
            final totalComprometido = gastoFijo + ahorro + cuota;
            // Presupuesto base es lo que queda libre o el global si no hay ingresos programados
            final libreParaVariable = ingresoFijo > 0 ? (ingresoFijo - totalComprometido) : (settings.globalMonthlyBudget ?? 0);
            
            // ... I need to write the full implementation here
