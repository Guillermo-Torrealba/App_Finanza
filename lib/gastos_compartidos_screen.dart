import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GastosCompartidosScreen extends StatefulWidget {
  final List<Map<String, dynamic>> movimientos;

  const GastosCompartidosScreen({super.key, required this.movimientos});

  @override
  State<GastosCompartidosScreen> createState() =>
      _GastosCompartidosScreenState();
}

class _GastosCompartidosScreenState extends State<GastosCompartidosScreen> {
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
    final bool marcar =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Marcar como pagado?'),
            content: Text(
              'Al confirmar, se registrará un ingreso de \$${deuda['monto']} en la cuenta asociada a este gasto.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ) ??
        false;

    if (!marcar) return;

    setState(() => _isLoading = true);
    try {
      // 1. Marcar como pagado en gastos_compartidos
      await supabase
          .from('gastos_compartidos')
          .update({'pagado': true})
          .eq('id', deuda['id']);

      // 2. Insertar transacción de ingreso
      final gastoOrignal = deuda['gastos'];
      final cuenta = gastoOrignal != null ? gastoOrignal['cuenta'] : 'Otra';

      await supabase.from('gastos').insert({
        'user_id': supabase.auth.currentUser!.id,
        'fecha': DateTime.now().toIso8601String(),
        'item': 'Pago de ${deuda['persona']} (Compartido)',
        'detalle':
            'Reembolso asociado al gasto: ${gastoOrignal?['item'] ?? 'Gasto'}',
        'monto': deuda['monto'],
        'categoria': 'Otros Ingresos', // Asumiendo que esta es una cat válida
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _deudas.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final pendientes = _deudas.where((d) => d['pagado'] == false).toList();
    final pagados = _deudas.where((d) => d['pagado'] == true).toList();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Pendientes'),
              Tab(text: 'Pagados'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildListaDeudas(pendientes, false),
                _buildListaDeudas(pagados, true),
              ],
            ),
          ),
        ],
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: deudas.length,
      itemBuilder: (context, index) {
        final d = deudas[index];
        final gasto = d['gastos'];
        final Color cardColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.grey.shade900
            : Colors.white;

        return Card(
          elevation: 2,
          color: cardColor,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: esPagado
                  ? Colors.green.shade100
                  : Colors.red.shade100,
              child: Icon(
                Icons.person,
                color: esPagado ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
            title: Text(
              d['persona'],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(gasto?['item'] ?? 'Transacción eliminada'),
                if (gasto != null)
                  Text(
                    'Cuenta: ${gasto['cuenta']}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${d['monto']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (!esPagado)
                  InkWell(
                    onTap: () => _marcarComoPagado(d),
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Text(
                        'Marcar Pagado',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (esPagado)
                  const Text(
                    'Pagado',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
