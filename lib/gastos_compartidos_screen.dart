import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shimmer/shimmer.dart';

class GastosCompartidosScreen extends StatefulWidget {
  final List<Map<String, dynamic>> movimientos;

  const GastosCompartidosScreen({super.key, required this.movimientos});

  @override
  State<GastosCompartidosScreen> createState() =>
      _GastosCompartidosScreenState();
}

class _GastosCompartidosScreenState extends State<GastosCompartidosScreen> {
  static final _currencyFormat = NumberFormat('#,###', 'es_CL');

  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _deudas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarDeudas();
  }

  Future<void> _cargarDeudas() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      final response = await supabase
          .from('gastos_compartidos')
          .select('*, gastos!inner(fecha, item, cuenta)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      setState(() {
        _deudas = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar gastos compartidos: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _marcarComoPagado(Map<String, dynamic> deuda) async {
    final TextEditingController montoController = TextEditingController(
      text: deuda['monto'].toString(),
    );

    final num? montoConfirmado = await showDialog<num>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar Pago'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Verifica o edita el monto recibido:'),
              const SizedBox(height: 16),
              TextField(
                textInputAction: TextInputAction.done,
                controller: montoController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                  // Si es inválido, podrías mostrar un ScaffoldMessenger (ajustado para simplicidad)
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
      // 1. Marcar como pagado en gastos_compartidos (se actualiza también el monto real recibido)
      await supabase
          .from('gastos_compartidos')
          .update({'pagado': true, 'monto': montoConfirmado})
          .eq('id', deuda['id']);

      // 2. Insertar transacción de ingreso con el monto modificado
      final gastoOrignal = deuda['gastos'];
      final cuenta = gastoOrignal != null ? gastoOrignal['cuenta'] : 'Otra';

      await supabase.from('gastos').insert({
        'user_id': supabase.auth.currentUser!.id,
        'fecha': DateTime.now().toIso8601String(),
        'item': 'Pago de ${deuda['persona']} (Compartido)',
        'detalle':
            'Reembolso asociado al gasto: ${gastoOrignal?['item'] ?? 'Gasto'}',
        'monto': montoConfirmado,
        'categoria':
            'Cuentas por Cobrar', // Compensa el préstamo ficticio de la Opción C
        'cuenta': cuenta,
        'tipo': 'Ingreso',
        'metodo_pago':
            'Debito', // El retorno se asume efectivo o débito por defecto
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pago registrado correctamente')),
        );
      }
      _cargarDeudas();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al marcar pago: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _marcarMultiplesComoPagado(
    String persona,
    List<Map<String, dynamic>> deudasGrupo,
  ) async {
    final num total = deudasGrupo.fold(
      0,
      (sum, item) => sum + (item['monto'] as num? ?? 0),
    );
    final TextEditingController montoController = TextEditingController(
      text: total.toString(),
    );

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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al marcar pago: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  void _copiarAlPortapapeles(
    String persona,
    List<Map<String, dynamic>> deudasGrupo,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('detalle:');

    num total = 0;
    for (var d in deudasGrupo) {
      final gasto = d['gastos'];
      final item = gasto?['item'] ?? 'Transacción';
      final monto = d['monto'] ?? 0;
      buffer.writeln('- $item: \$${_currencyFormat.format(monto)}');
      total += (monto as num);
    }

    if (deudasGrupo.length > 1) {
      buffer.writeln('');
      buffer.writeln('Total: \$${_currencyFormat.format(total)}');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Detalle copiado al portapapeles')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _deudas.isEmpty) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        appBar: AppBar(title: const Text('Gastos Compartidos')),
        body: _buildSkeleton(isDark),
      );
    }

    final pendientes = _deudas.where((d) => d['pagado'] == false).toList();
    final pagados = _deudas.where((d) => d['pagado'] == true).toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gastos Compartidos'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pendientes'),
              Tab(text: 'Pagados'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildListaDeudas(pendientes, false),
            _buildListaDeudas(pagados, true),
          ],
        ),
      ),
    );
  }

  Widget _buildListaDeudas(List<Map<String, dynamic>> deudas, bool esPagado) {
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
                  '\$${_currencyFormat.format(totalPendiente)}',
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
                0,
                (sum, item) => sum + (item['monto'] as num? ?? 0),
              );

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
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
                              '\$${_currencyFormat.format(totalGrupo)}',
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
                                onPressed: () =>
                                    _copiarAlPortapapeles(persona, deudasGrupo),
                                icon: const Icon(
                                  Icons.content_copy,
                                  size: 18,
                                  color: Color(0xFF888888),
                                ),
                                label: const Text(
                                  'Copiar detalle',
                                  style: TextStyle(color: Color(0xFF888888)),
                                ),
                              ),
                              if (deudasGrupo.length > 1)
                                FilledButton.icon(
                                  onPressed: () => _marcarMultiplesComoPagado(
                                    persona,
                                    deudasGrupo,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(
                                      0xFF00E5A0,
                                    ).withAlpha(20),
                                    foregroundColor: const Color(0xFF00E5A0),
                                    side: BorderSide(
                                      color: const Color(
                                        0xFF00E5A0,
                                      ).withAlpha(70),
                                    ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Color(0xFF232323)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        gasto?['item'] ??
                                            'Transacción eliminada',
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
                                      '\$${_currencyFormat.format(d['monto'])}',
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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF00E5A0,
                                            ).withAlpha(18),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: const Color(
                                                0xFF00E5A0,
                                              ).withAlpha(70),
                                            ),
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

  // --- Skeleton Loader ---
  Widget _buildSkeleton(bool isDark) {
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
      highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
      child: Column(
        children: [
          // TabBar Skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Container(width: 100, height: 20, color: Colors.white),
                Container(width: 100, height: 20, color: Colors.white),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // List Items Skeleton
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 5,
              itemBuilder: (context, index) {
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 120,
                                height: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: 80,
                                height: 12,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                        Container(width: 60, height: 20, color: Colors.white),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
} // End of State
