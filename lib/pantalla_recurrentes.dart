import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'app_settings.dart';

class GestionarRecurrentesScreen extends StatefulWidget {
  final SettingsController settingsController;

  const GestionarRecurrentesScreen({
    super.key,
    required this.settingsController,
  });

  @override
  State<GestionarRecurrentesScreen> createState() =>
      _GestionarRecurrentesScreenState();
}

class _GestionarRecurrentesScreenState
    extends State<GestionarRecurrentesScreen> {
  final _supabase = Supabase.instance.client;
  final _stream = Supabase.instance.client
      .from('gastos_programados')
      .stream(primaryKey: ['id'])
      .order('fecha_proximo_pago', ascending: true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gastos Recurrentes')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'No tienes gastos programados.\nPulsa + para crear uno.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: item['tipo'] == 'Ingreso'
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    child: Icon(
                      item['tipo'] == 'Ingreso'
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      color: item['tipo'] == 'Ingreso'
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                  title: Text(
                    item['item'] ?? 'Sin nombre',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${NumberFormat.simpleCurrency(locale: widget.settingsController.settings.localeCode).currencySymbol}${item['monto']} - ${item['frecuencia']}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'Próximo: ${_formatDate(item['fecha_proximo_pago'])}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: item['activo'] ?? true,
                        onChanged: (val) {
                          _supabase
                              .from('gastos_programados')
                              .update({'activo': val})
                              .eq('id', item['id']);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _mostrarFormulario(item: item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmarEliminar(item),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _mostrarFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _confirmarEliminar(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar recurrencia'),
        content: Text('¿Seguro que deseas eliminar "${item['item']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.from('gastos_programados').delete().eq('id', item['id']);
    }
  }

  void _mostrarFormulario({Map<String, dynamic>? item}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FormularioRecurrente(
        settingsController: widget.settingsController,
        itemParaEditar: item,
      ),
    );
  }
}

class _FormularioRecurrente extends StatefulWidget {
  final SettingsController settingsController;
  final Map<String, dynamic>? itemParaEditar;

  const _FormularioRecurrente({
    required this.settingsController,
    this.itemParaEditar,
  });

  @override
  State<_FormularioRecurrente> createState() => _FormularioRecurrenteState();
}

class _FormularioRecurrenteState extends State<_FormularioRecurrente> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _itemController;
  late TextEditingController _montoController;
  late String _tipo;
  late String _frecuencia;
  late DateTime _fechaProximo;
  late String _categoria;
  late String _cuenta;

  final List<String> _frecuencias = ['Mensual', 'Semanal', 'Anual', 'Unico'];

  @override
  void initState() {
    super.initState();
    final item = widget.itemParaEditar;
    _itemController = TextEditingController(
      text: item?['item']?.toString() ?? '',
    );
    _montoController = TextEditingController(
      text: item?['monto']?.toString() ?? '',
    );
    _tipo = item?['tipo'] ?? 'Gasto';
    _frecuencia = item?['frecuencia'] ?? 'Mensual';
    _fechaProximo = item != null
        ? DateTime.parse(item['fecha_proximo_pago'])
        : DateTime.now();

    // Categorias y Cuentas defaults
    final settings = widget.settingsController.settings;
    final cats = _tipo == 'Gasto'
        ? settings.activeCategories
        : settings.activeIncomeCategories;
    _categoria =
        item?['categoria'] ?? (cats.isNotEmpty ? cats.first : 'Varios');

    final accs = settings.activeAccounts;
    _cuenta =
        item?['cuenta'] ??
        (accs.isNotEmpty ? accs.first : settings.defaultAccount);
    if (!accs.contains(_cuenta) && accs.isNotEmpty) {
      if (!accs.contains(_cuenta)) _cuenta = accs.first;
    }
  }

  @override
  void dispose() {
    _itemController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsController.settings;
    final categorias = _tipo == 'Gasto'
        ? settings.activeCategories
        : settings.activeIncomeCategories;
    // Asegurar que la categoría seleccionada está en la lista o agregarla temporalmente
    if (!categorias.contains(_categoria)) {
      categorias.add(_categoria);
    }

    final cuentas = settings.activeAccounts;
    // Asegurar que la cuenta seleccionada está en la lista
    if (!cuentas.contains(_cuenta)) {
      cuentas.add(_cuenta);
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.itemParaEditar == null
                    ? 'Nuevo Gasto Programado'
                    : 'Editar Recurrencia',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Tipo
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'Gasto',
                    label: Text('Gasto'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                  ButtonSegment(
                    value: 'Ingreso',
                    label: Text('Ingreso'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                ],
                selected: {_tipo},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() {
                    _tipo = newSelection.first;
                    // Reset category on type change
                    final newCats = _tipo == 'Gasto'
                        ? settings.activeCategories
                        : settings.activeIncomeCategories;
                    _categoria = newCats.isNotEmpty ? newCats.first : 'Varios';
                  });
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _itemController,
                decoration: const InputDecoration(
                  labelText: 'Concepto (ej. Netflix)',
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoController,
                decoration: const InputDecoration(labelText: 'Monto'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _frecuencia,
                decoration: const InputDecoration(labelText: 'Frecuencia'),
                items: _frecuencias
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (val) => setState(() => _frecuencia = val!),
              ),
              const SizedBox(height: 12),

              // Fecha Próximo Pago
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Fecha Próximo Pago',
                ),
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fechaProximo,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) setState(() => _fechaProximo = picked);
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_fechaProximo.day}/${_fechaProximo.month}/${_fechaProximo.year}',
                      ),
                      const Icon(Icons.calendar_today),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _categoria,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: categorias
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) => setState(() => _categoria = val!),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _cuenta,
                decoration: const InputDecoration(labelText: 'Cuenta'),
                items: cuentas
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) => setState(() => _cuenta = val!),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _guardar,
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final monto = int.tryParse(_montoController.text) ?? 0;
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final data = {
      'user_id': user.id,
      'item': _itemController.text.trim(),
      'monto': monto,
      'categoria': _categoria,
      'cuenta': _cuenta,
      'tipo': _tipo,
      'frecuencia': _frecuencia,
      'fecha_proximo_pago': _fechaProximo.toIso8601String(),
      'activo': true,
    };

    try {
      if (widget.itemParaEditar != null) {
        await supabase
            .from('gastos_programados')
            .update(data)
            .eq('id', widget.itemParaEditar!['id']);
      } else {
        await supabase.from('gastos_programados').insert(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
