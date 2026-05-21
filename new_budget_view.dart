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
            final libreParaVariable = ingresoFijo > 0 
                ? (ingresoFijo - totalComprometido) 
                : (settings.globalMonthlyBudget ?? 0);

            final datosDelMes = todosLosDatos.where((mov) {
              final fechaMov = DateTime.parse((mov['fecha'] ?? '').toString());
              return fechaMov.year == _mesVisualizado.year &&
                  fechaMov.month == _mesVisualizado.month;
            }).toList();

            int gastoTotalVariable = 0;
            for (final m in datosDelMes) {
               if (m['tipo'] == 'Gasto' && m['categoria'] != 'Ajuste' && m['categoria'] != 'Transferencia') {
                   // Exclude if it's already counted as Fixed Expense (we assume recurrents are handled, but here we just show what was actually spent)
                   gastoTotalVariable += (m['monto'] as num).toInt();
               }
            }

            final progresoLibre = libreParaVariable > 0 ? (gastoTotalVariable / libreParaVariable).clamp(0.0, 1.0) : 0.0;
            final excedidoLibre = gastoTotalVariable > libreParaVariable && libreParaVariable > 0;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Planificador Mensual',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  // Resumen Embudo
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2433) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(isDark ? 50 : 12),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _filaResumenEmbudo('Ingresos Fijos', ingresoFijo, Colors.green, isDark),
                        const Divider(height: 24),
                        _filaResumenEmbudo('Gastos Fijos', -gastoFijo, Colors.red, isDark),
                        _filaResumenEmbudo('Metas de Ahorro', -ahorro, Colors.blue, isDark),
                        _filaResumenEmbudo('Cuotas Programadas', -cuota, Colors.orange, isDark),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Libre para gastar:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              _textoMonto(libreParaVariable, ocultable: false),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: libreParaVariable >= 0 ? Colors.teal : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  const Text(
                    'Consumo del Libre (Gastos Variables)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  
                  // Progreso Global del Variable
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Gastado: ${_textoMonto(gastoTotalVariable)}'),
                          Text(libreParaVariable > 0 ? '${(progresoLibre * 100).toStringAsFixed(1)}%' : 'Sin limite'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: excedidoLibre ? 1.0 : progresoLibre,
                          minHeight: 12,
                          backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                          color: excedidoLibre ? Colors.red : Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       const Text(
                        'Presupuestos Variables',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _editarPresupuestoGlobal, // We reuse the edit button logic if needed, or remove it. Let's keep it simply calling a modal or removing it.
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Listado de Categorias Variables y Subcategorias
                  ...settings.activeCategories.map((categoria) {
                    final presupuestoCat = settings.categoryBudgets[categoria] ?? 0;
                    
                    // Solo mostramos si tiene presupuesto asignado o si hay gastos
                    final gastosCat = datosDelMes.where((m) => m['tipo'] == 'Gasto' && m['categoria'] == categoria).toList();
                    final gastadoCat = gastosCat.fold<int>(0, (sum, m) => sum + (m['monto'] as num).toInt());
                    
                    final subs = settings.activeSubcategories[categoria] ?? [];
                    
                    if (presupuestoCat == 0 && gastadoCat == 0 && subs.isEmpty) return const SizedBox();
                    
                    final pct = presupuestoCat > 0 ? (gastadoCat / presupuestoCat).clamp(0.0, 1.0) : 0.0;
                    final iconCat = settings.categoryEmojis[categoria] ?? '📌';
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: isDark ? const Color(0xFF1E2433) : Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(iconCat, style: const TextStyle(fontSize: 20)),
                                    const SizedBox(width: 8),
                                    Text(categoria, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  ],
                                ),
                                Text('${_textoMonto(gastadoCat)} / ${presupuestoCat > 0 ? _textoMonto(presupuestoCat) : '∞'}'),
                              ],
                            ),
                            if (presupuestoCat > 0) ...[
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: pct,
                                backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                                color: pct >= 1 ? Colors.red : Colors.teal,
                              ),
                            ],
                            
                            // Subcategorias
                            if (subs.isNotEmpty) ...[
                               const SizedBox(height: 12),
                               ...subs.map((sub) {
                                  final presupuestoSub = settings.subcategoryBudgets['${categoria}_$sub'] ?? 0;
                                  final gastosSub = gastosCat.where((m) => m['etiquetas'] != null && (m['etiquetas'] as List).contains(sub)).toList();
                                  final gastadoSub = gastosSub.fold<int>(0, (sum, m) => sum + (m['monto'] as num).toInt());
                                  
                                  if (presupuestoSub == 0 && gastadoSub == 0) return const SizedBox();
                                  
                                  final pctSub = presupuestoSub > 0 ? (gastadoSub / presupuestoSub).clamp(0.0, 1.0) : 0.0;
                                  
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 16, top: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('↳ $sub', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                            Text('${_textoMonto(gastadoSub)} / ${presupuestoSub > 0 ? _textoMonto(presupuestoSub) : '∞'}', style: const TextStyle(fontSize: 12)),
                                          ],
                                        ),
                                        if (presupuestoSub > 0) ...[
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(
                                            value: pctSub,
                                            minHeight: 4,
                                            backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                                            color: pctSub >= 1 ? Colors.red : Colors.blue,
                                          ),
                                        ]
                                      ],
                                    ),
                                  );
                               })
                            ]
                          ],
                        ),
                      ),
                    );
                  })
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _filaResumenEmbudo(String titulo, int monto, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(titulo, style: TextStyle(color: isDark ? Colors.grey.shade300 : Colors.grey.shade700)),
          Text(
            _textoMonto(monto, ocultable: false),
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
