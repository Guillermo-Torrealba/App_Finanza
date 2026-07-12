import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'receipt_scanner_service.dart';

class DivisorCuentaScreen extends StatefulWidget {
  final File receiptImage;
  final ReceiptSharedData sharedData;
  final String? boletaUrl; // Se pasa si ya se subió la imagen, o se sube en 2do plano

  const DivisorCuentaScreen({
    super.key,
    required this.receiptImage,
    required this.sharedData,
    this.boletaUrl,
  });

  @override
  State<DivisorCuentaScreen> createState() => _DivisorCuentaScreenState();
}

class _DivisorCuentaScreenState extends State<DivisorCuentaScreen> {
  final List<String> _participantes = [];
  final Map<int, List<String>> _asignaciones = {}; // index del item -> lista de nombres
  bool _incluirPropina = false;
  String? _boletaUrlFinal;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _boletaUrlFinal = widget.boletaUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pedirParticipantes();
    });
  }

  void _pedirParticipantes() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('¿Quiénes comparten la cuenta?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Ingresa un nombre y presiona Enter',
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty && !_participantes.contains(val.trim())) {
                        setStateDialog(() {
                          _participantes.add(val.trim());
                        });
                        controller.clear();
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: _participantes
                        .map((p) => Chip(
                              label: Text(p),
                              onDeleted: () {
                                setStateDialog(() {
                                  _participantes.remove(p);
                                });
                              },
                            ))
                        .toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (_participantes.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Agrega al menos una persona')),
                      );
                      return;
                    }
                    Navigator.pop(context);
                    setState(() {}); // refresh main screen
                  },
                  child: const Text('Continuar'),
                )
              ],
            );
          }
        );
      },
    );
  }

  Map<String, double> _calcularDeudas() {
    Map<String, double> deudas = {};
    for (var p in _participantes) {
      deudas[p] = 0.0;
    }

    for (int i = 0; i < widget.sharedData.items.length; i++) {
      final item = widget.sharedData.items[i];
      final asignados = _asignaciones[i] ?? [];
      if (asignados.isNotEmpty) {
        final costoPorPersona = item.precio / asignados.length;
        for (var persona in asignados) {
          deudas[persona] = (deudas[persona] ?? 0.0) + costoPorPersona;
        }
      }
    }

    if (_incluirPropina) {
      for (var p in _participantes) {
        deudas[p] = deudas[p]! * 1.10; // suma 10%
      }
    }

    return deudas;
  }

  Future<void> _generarCobro() async {
    final deudas = _calcularDeudas();
    String mensaje = "¡Hola! Aquí está el detalle de la cuenta:\n\n";
    
    deudas.forEach((persona, monto) {
      mensaje += "- $persona: \$${monto.toStringAsFixed(0)}\n";
    });
    
    if (_incluirPropina) {
      mensaje += "\n(Incluye 10% de propina)";
    }
    
    final uri = Uri.parse("whatsapp://send?text=${Uri.encodeComponent(mensaje)}");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp')),
        );
      }
    }
  }

  Future<void> _guardarMiParte() async {
    if (_participantes.isEmpty) return;
    
    // Asumimos que el usuario es el primero en la lista o pedimos quién es
    // Para simplificar, le mostraremos un diálogo para elegir cuál de los participantes es él
    String? yo;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('¿Cuál eres tú?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _participantes.map((p) => ListTile(
              title: Text(p),
              onTap: () {
                yo = p;
                Navigator.pop(context);
              },
            )).toList(),
          ),
        );
      }
    );

    if (yo == null) return;

    final miDeuda = _calcularDeudas()[yo] ?? 0.0;
    if (miDeuda == 0) return;

    setState(() => _guardando = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception("No estás autenticado");

      // Subir imagen si no se ha subido
      if (_boletaUrlFinal == null) {
        final scanner = ReceiptScannerService();
        _boletaUrlFinal = await scanner.uploadReceiptImage(widget.receiptImage);
      }

      await Supabase.instance.client.from('gastos').insert({
        'user_id': userId,
        'tipo': 'Gasto',
        'monto': miDeuda,
        'item': 'Mi parte de la cuenta (Salida)',
        'categoria': 'Restaurante', // O sugerida
        'fecha': DateTime.now().toString().substring(0, 10),
        'boleta_url': _boletaUrlFinal,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gasto guardado con éxito')),
        );
        Navigator.pop(context); // Volver
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deudas = _calcularDeudas();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dividir Cuenta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: _pedirParticipantes,
            tooltip: 'Participantes',
          ),
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Asignar todo a todos',
            onPressed: () {
              if (_participantes.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Primero agrega participantes')),
                );
                return;
              }
              setState(() {
                for (int i = 0; i < widget.sharedData.items.length; i++) {
                  _asignaciones[i] = List.from(_participantes);
                }
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Todos los ítems asignados a todos')),
              );
            },
          )
        ],
      ),
      body: _participantes.isEmpty
          ? const Center(child: Text('Agrega participantes para comenzar'))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.sharedData.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.sharedData.items[index];
                      final asignados = _asignaciones[index] ?? [];

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.nombrePlato,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                  Text(
                                    '\$${item.precio.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                children: _participantes.map((p) {
                                  final isSelected = asignados.contains(p);
                                  return ChoiceChip(
                                    label: Text(p),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _asignaciones.putIfAbsent(index, () => []).add(p);
                                        } else {
                                          _asignaciones[index]?.remove(p);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Incluir 10% de Propina'),
                        value: _incluirPropina,
                        onChanged: (val) => setState(() => _incluirPropina = val),
                      ),
                      const Divider(),
                      const Text('Total por Persona:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        children: deudas.entries.map((e) => Text(
                          '${e.key}: \$${e.value.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 14),
                        )).toList(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.share),
                              label: const Text('Cobrar'),
                              onPressed: _generarCobro,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton.icon(
                              icon: _guardando
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.save),
                              label: const Text('Guardar'),
                              onPressed: _guardando ? null : _guardarMiParte,
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                )
              ],
            ),
    );
  }
}
