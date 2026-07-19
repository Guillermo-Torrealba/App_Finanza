import re

with open('lib/gastos_compartidos_screen.dart', 'r') as f:
    content = f.read()

# Add import
content = content.replace(
    "import 'package:flutter/material.dart';",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';"
)

new_methods = """
  Future<void> _marcarMultiplesComoPagado(String persona, List<Map<String, dynamic>> deudasGrupo) async {
    final num total = deudasGrupo.fold(0, (sum, item) => sum + (item['monto'] as num? ?? 0));
    final TextEditingController montoController = TextEditingController(text: total.toString());

    final num? montoConfirmado = await showDialog<num>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Confirmar Pago de $persona'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Verifica o edita el monto total recibido:'),
              const SizedBox(height: 16),
              TextField(
                textInputAction: TextInputAction.done,
                controller: montoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto recibido',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final num? amount = num.tryParse(montoController.text);
                if (amount != null && amount > 0) {
                  Navigator.pop(context, amount);
                } else {
                  Navigator.pop(context, null);
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    montoController.dispose();

    if (montoConfirmado == null) return;

    setState(() => _isLoading = true);
    try {
      for (var deuda in deudasGrupo) {
         await supabase
             .from('gastos_compartidos')
             .update({'pagado': true})
             .eq('id', deuda['id']);
      }

      await supabase.from('gastos').insert({
        'user_id': supabase.auth.currentUser!.id,
        'fecha': DateTime.now().toIso8601String(),
        'item': 'Pago múltiple de $persona',
        'detalle': 'Reembolso por ${deudasGrupo.length} gastos compartidos',
        'monto': montoConfirmado,
        'categoria': 'Cuentas por Cobrar',
        'cuenta': 'Otra',
        'tipo': 'Ingreso',
        'metodo_pago': 'Debito',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pagos registrados correctamente')),
        );
      }
      _cargarDeudas();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al marcar pago: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  void _copiarAlPortapapeles(String persona, List<Map<String, dynamic>> deudasGrupo) {
    final buffer = StringBuffer();
    buffer.writeln('detalle:');
    
    num total = 0;
    for (var d in deudasGrupo) {
      final gasto = d['gastos'];
      final item = gasto?['item'] ?? 'Transacción';
      final monto = d['monto'] ?? 0;
      buffer.writeln('- $item: \\$$monto');
      total += (monto as num);
    }
    
    if (deudasGrupo.length > 1) {
      buffer.writeln('');
      buffer.writeln('Total: \\$$total');
    }
    
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Detalle copiado al portapapeles')),
    );
  }

  @override
"""

content = content.replace("  @override\n  Widget build(BuildContext context) {", new_methods + "  Widget build(BuildContext context) {")

# Now replace _buildListaDeudas
# I will find the start of _buildListaDeudas and the end, which is before _buildSkeleton
start_idx = content.find("  Widget _buildListaDeudas(")
end_idx = content.find("  // --- Skeleton Loader ---")

new_build_lista_deudas = """  Widget _buildListaDeudas(List<Map<String, dynamic>> deudas, bool esPagado) {
    if (deudas.isEmpty) {
      return Center(
        child: Text(
          esPagado ? 'No hay deudas pagadas' : 'No hay deudas pendientes',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    final groupedDeudas = <String, List<Map<String, dynamic>>>{};
    num totalPendiente = 0;
    for (var d in deudas) {
      final persona = d['persona'] as String? ?? 'Desconocido';
      groupedDeudas.putIfAbsent(persona, () => []).add(d);
      if (!esPagado) {
        totalPendiente += (d['monto'] as num? ?? 0);
      }
    }

    return Column(
      children: [
        if (!esPagado && totalPendiente > 0)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            width: double.infinity,
            color: const Color(0xFF141414),
            child: Column(
              children: [
                const Text(
                  'Total por cobrar',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  '\\$$totalPendiente',
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groupedDeudas.keys.length,
            itemBuilder: (context, index) {
              final persona = groupedDeudas.keys.elementAt(index);
              final deudasGrupo = groupedDeudas[persona]!;
              final totalGrupo = deudasGrupo.fold<num>(
                  0, (sum, item) => sum + (item['monto'] as num? ?? 0));

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: esPagado
                            ? const Color(0xFF00E5A0).withAlpha(20)
                            : const Color(0xFFFF4D6A).withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: esPagado
                              ? const Color(0xFF00E5A0).withAlpha(50)
                              : const Color(0xFFFF4D6A).withAlpha(50),
                        ),
                      ),
                      child: Icon(
                        Icons.person,
                        size: 20,
                        color: esPagado
                            ? const Color(0xFF00E5A0)
                            : const Color(0xFFFF4D6A),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                persona,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: Color(0xFFF5F5F5),
                                ),
                              ),
                              if (deudasGrupo.length > 1)
                                Text(
                                  '${deudasGrupo.length} gastos',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF888888),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\\$$totalGrupo',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Color(0xFFF5F5F5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    children: [
                      const Divider(color: Color(0xFF2A2A2A), height: 1),
                      if (!esPagado)
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                onPressed: () => _copiarAlPortapapeles(persona, deudasGrupo),
                                icon: const Icon(Icons.content_copy, size: 18, color: Color(0xFF888888)),
                                label: const Text('Copiar detalle', style: TextStyle(color: Color(0xFF888888))),
                              ),
                              if (deudasGrupo.length > 1)
                                FilledButton.icon(
                                  onPressed: () => _marcarMultiplesComoPagado(persona, deudasGrupo),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF00E5A0).withAlpha(20),
                                    foregroundColor: const Color(0xFF00E5A0),
                                    side: BorderSide(color: const Color(0xFF00E5A0).withAlpha(70)),
                                  ),
                                  icon: const Icon(Icons.check, size: 18),
                                  label: const Text('Pagar todos'),
                                ),
                            ],
                          ),
                        ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: deudasGrupo.length,
                        itemBuilder: (context, idx) {
                          final d = deudasGrupo[idx];
                          final gasto = d['gastos'];
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: Color(0xFF232323))),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        gasto?['item'] ?? 'Transacción eliminada',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFFE0E0E0),
                                        ),
                                      ),
                                      if (gasto != null)
                                        Text(
                                          'Cuenta: ${gasto['cuenta']}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF666666),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '\\$${d['monto']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: Color(0xFFE0E0E0),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (!esPagado)
                                      InkWell(
                                        onTap: () => _marcarComoPagado(d),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF00E5A0).withAlpha(18),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF00E5A0).withAlpha(70)),
                                          ),
                                          child: const Text(
                                            'Pagado',
                                            style: TextStyle(
                                              color: Color(0xFF00E5A0),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

"""

if start_idx != -1 and end_idx != -1:
    content = content[:start_idx] + new_build_lista_deudas + content[end_idx:]
else:
    print("Could not find start or end index for replacement")

with open('lib/gastos_compartidos_screen.dart', 'w') as f:
    f.write(content)

print("Done")

