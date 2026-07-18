import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pantalla que muestra los gastos capturados automáticamente por el Atajo
/// de iOS (Apple Pay) con estado == 'pendiente', permitiendo al usuario
/// revisarlos, editarlos y confirmarlos o rechazarlos.
class GastosPendientesScreen extends StatelessWidget {
  /// Callback que se invoca cuando el usuario toca "Confirmar" un gasto.
  /// Recibe el [Map] completo del gasto pendiente para que la pantalla
  /// padre pueda abrir el formulario pre-rellenado.
  final void Function(Map<String, dynamic> gastoPendiente) onAprobar;

  const GastosPendientesScreen({super.key, required this.onAprobar});

  static final _supabase = Supabase.instance.client;
  static final _currencyFormat = NumberFormat('#,###', 'es_CL');

  Future<void> _rechazarGasto(
    BuildContext context,
    Map<String, dynamic> gasto,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Rechazar gasto',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Se eliminará "${gasto['item'] ?? 'Sin nombre'}" de los pendientes. No se guardará en tu historial.',
          style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Color(0xFF888888)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Rechazar',
              style: TextStyle(
                color: Color(0xFFFF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase
          .from('gastos')
          .update({'estado': 'eliminado'})
          .eq('id', gasto['id'] as int);

      if (context.mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Gasto rechazado'),
            backgroundColor: const Color(0xFF1C1C1C),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al rechazar: $e')),
        );
      }
    }
  }

  String _formatearFecha(String? fechaStr) {
    if (fechaStr == null) return '—';
    try {
      final fecha = DateTime.parse(fechaStr);
      return DateFormat('d MMM, HH:mm', 'es').format(fecha);
    } catch (_) {
      return fechaStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Buzón de Gastos',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('gastos')
            .stream(primaryKey: ['id'])
            .eq('estado', 'pendiente')
            .order('fecha', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildError(snapshot.error.toString());
          }

          if (!snapshot.hasData) {
            return _buildLoading();
          }

          final pendientes = snapshot.data!;

          if (pendientes.isEmpty) {
            return _buildEmpty();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(pendientes.length),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: pendientes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _buildPendienteCard(context, pendientes[index]);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withAlpha(30),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFF9500).withAlpha(80),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFFFF9500),
                  size: 13,
                ),
                const SizedBox(width: 5),
                Text(
                  '$count pendiente${count != 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: Color(0xFFFF9500),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Desliza ← para rechazar',
            style: TextStyle(color: Color(0xFF555555), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPendienteCard(
    BuildContext context,
    Map<String, dynamic> gasto,
  ) {
    final monto = (gasto['monto'] as num? ?? 0).toInt();
    final comercio = (gasto['item'] ?? 'Sin nombre').toString();
    final fecha = _formatearFecha(gasto['fecha']?.toString());
    final cuenta = (gasto['cuenta'] ?? '—').toString();

    return Dismissible(
      key: ValueKey(gasto['id']),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _rechazarGasto(context, gasto);
        return false; // El stream actualiza la lista automáticamente
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFF4444).withAlpha(30),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFF4444).withAlpha(60)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Color(0xFFFF4444), size: 22),
            SizedBox(height: 4),
            Text(
              'Rechazar',
              style: TextStyle(
                color: Color(0xFFFF4444),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onAprobar(gasto);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500).withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFF9500).withAlpha(50),
                  ),
                ),
                child: const Icon(
                  Icons.contactless_rounded,
                  color: Color(0xFFFF9500),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comercio,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 12,
                          color: Color(0xFF555555),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          fecha,
                          style: const TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 12,
                          color: Color(0xFF555555),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            cuenta,
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${_currencyFormat.format(monto)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5A0).withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00E5A0).withAlpha(60),
                      ),
                    ),
                    child: const Text(
                      'Confirmar →',
                      style: TextStyle(
                        color: Color(0xFF00E5A0),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF00E5A0),
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '¡Todo al día!',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'No hay gastos pendientes\nde Apple Pay por revisar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF555555), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Color(0xFFFF9500),
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Error al cargar: $error',
          style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
