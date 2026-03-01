import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app_routes.dart';
import 'app_settings.dart';

class OnboardingScreen extends StatefulWidget {
  final SettingsController settingsController;

  const OnboardingScreen({super.key, required this.settingsController});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  // Paso 1: Cuenta Débito
  final _cuentaDebitoController = TextEditingController(text: 'Cta. Corriente');
  final _saldoDebitoController = TextEditingController(text: '0');

  // Paso 2: Tarjeta de Crédito
  bool _usaTarjeta = true;
  final _nombreTarjetaController = TextEditingController(
    text: 'Tarjeta de Crédito',
  );
  final _deudaFacturadaController = TextEditingController(text: '0');
  final _deudaNoFacturadaController = TextEditingController(text: '0');
  int _diaFacturacion = 25;
  int _diaVencimiento = 5;

  // Paso 3: Presupuesto Global
  final _presupuestoController = TextEditingController(text: '0');

  @override
  void dispose() {
    _pageController.dispose();
    _cuentaDebitoController.dispose();
    _saldoDebitoController.dispose();
    _nombreTarjetaController.dispose();
    _deudaFacturadaController.dispose();
    _deudaNoFacturadaController.dispose();
    _presupuestoController.dispose();
    super.dispose();
  }

  void _nextPage() {
    FocusScope.of(context).unfocus();
    if (_currentPage == 1 && !_usaTarjeta) {
      // Saltar paso de detalles de tarjeta si no la usa y estamos en el paso de tarjeta
      _pageController.animateToPage(
        3,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    FocusScope.of(context).unfocus();
    if (_currentPage == 3 && !_usaTarjeta) {
      // Volver a la pregunta de si usa tarjeta si no la usa
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finalizarOnboarding() async {
    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser!.id;
    final now = DateTime.now();
    // Use yesterday for initial balances so they don't mess up today's daily cash flow calculations
    final yesterday = now.subtract(const Duration(days: 1));

    try {
      final cuentaDebito = _cuentaDebitoController.text.trim().isEmpty
          ? 'Cta. Corriente'
          : _cuentaDebitoController.text.trim();
      final saldoDebito = int.tryParse(_saldoDebitoController.text) ?? 0;

      // 1. Configurar y Guardar Cuenta Débito (Saldo Inicial)
      if (saldoDebito != 0) {
        await supabase.from('gastos').insert({
          'user_id': userId,
          'fecha': yesterday.toIso8601String(),
          'item': 'Saldo Inicial',
          'detalle': 'Ajuste automático de onboarding',
          'monto': saldoDebito.abs(),
          'categoria': 'Ajuste',
          'cuenta': cuentaDebito,
          'tipo': saldoDebito > 0 ? 'Ingreso' : 'Gasto',
          'metodo_pago': 'Debito',
        });
      }
      widget.settingsController.setDefaultAccount(cuentaDebito);
      widget.settingsController.addAccount(cuentaDebito);

      // 2. Configurar Tarjeta de Crédito
      widget.settingsController.setHasCreditCard(_usaTarjeta);
      if (_usaTarjeta) {
        final nombreReq = _nombreTarjetaController.text.trim().isEmpty
            ? 'Tarjeta de Crédito'
            : _nombreTarjetaController.text.trim();
        final facturado = int.tryParse(_deudaFacturadaController.text) ?? 0;
        final noFacturado = int.tryParse(_deudaNoFacturadaController.text) ?? 0;

        widget.settingsController.setCreditCardBillingDay(_diaFacturacion);
        widget.settingsController.setCreditCardDueDay(_diaVencimiento);

        // Guardar saldos de tarjeta de crédito
        if (facturado > 0 || noFacturado > 0) {
          // Deuda Facturada se guarda como un gasto en el mes anterior
          if (facturado > 0) {
            DateTime lastMonthBillingDate;
            if (now.day > _diaFacturacion) {
              lastMonthBillingDate = DateTime(
                now.year,
                now.month,
                _diaFacturacion,
              );
            } else {
              lastMonthBillingDate = DateTime(
                now.year,
                now.month - 1,
                _diaFacturacion,
              );
            }
            // Add expenditure before the cutoff so it gets strictly billed
            final preCutoff = lastMonthBillingDate.subtract(
              const Duration(days: 2),
            );

            await supabase.from('gastos').insert({
              'user_id': userId,
              'fecha': preCutoff.toIso8601String(),
              'item': 'Saldo Facturado Inicial',
              'detalle': 'Ajuste automático de onboarding',
              'monto': facturado,
              'categoria': 'Ajuste',
              'cuenta': nombreReq,
              'tipo': 'Gasto',
              'metodo_pago': 'Credito',
            });
          }
          // Deuda No Facturada se guarda como un gasto en el ciclo actual
          if (noFacturado > 0) {
            await supabase.from('gastos').insert({
              'user_id': userId,
              'fecha': yesterday.toIso8601String(),
              'item': 'Saldo No Facturado Inicial',
              'detalle': 'Ajuste automático de onboarding',
              'monto': noFacturado,
              'categoria': 'Ajuste',
              'cuenta': nombreReq,
              'tipo': 'Gasto',
              'metodo_pago': 'Credito',
            });
          }
        }
      }

      // 3. Configurar Presupuesto
      final presupuestoGlobal = int.tryParse(_presupuestoController.text) ?? 0;
      if (presupuestoGlobal > 0) {
        widget.settingsController.setGlobalMonthlyBudget(presupuestoGlobal);
      }

      // Marcar Onboarding como completado
      widget.settingsController.setHasCompletedOnboarding(true);

      // Navegar a PantallaPrincipal
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al finalizar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool isNumeric = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        inputFormatters: isNumeric
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final isLastPage = _currentPage == 3;
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _currentPage == 0
              ? const SizedBox(width: 48) // Espacio vacío si no hay "Atrás"
              : IconButton(
                  onPressed: _previousPage,
                  icon: const Icon(Icons.arrow_back),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                ),
          ElevatedButton(
            onPressed: isLastPage ? _finalizarOnboarding : _nextPage,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    isLastPage ? 'Finalizar' : 'Siguiente',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Indicador de Progreso
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Row(
                children: List.generate(
                  4,
                  (index) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage >= index
                            ? primary
                            : (isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: [
                  // --- PASO 0: Bienvenida e Introducción ---
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.rocket_launch_rounded,
                          size: 80,
                          color: primary,
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'Bienvenido a\nMis Finanzas Cloud',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Vamos a configurar tu entorno rápidamente para que puedas empezar a tomar el control de tu dinero.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- PASO 1: Cuenta Débito Principal ---
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.account_balance_wallet,
                          size: 64,
                          color: primary,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Cuenta Principal',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ingresa el nombre y saldo actual de tu cuenta o bóveda principal donde guardas efectivo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _buildField(
                          label: 'Nombre de la cuenta',
                          controller: _cuentaDebitoController,
                          icon: Icons.account_balance,
                          isNumeric: false,
                        ),
                        _buildField(
                          label: 'Saldo Actual (\$)',
                          controller: _saldoDebitoController,
                          icon: Icons.attach_money,
                        ),
                      ],
                    ),
                  ),

                  // --- PASO 2: Tarjeta de Crédito ---
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(Icons.credit_card, size: 64, color: primary),
                          const SizedBox(height: 24),
                          const Text(
                            'Tarjeta de Crédito',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '¿Sueles realizar compras con tarjeta de crédito?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 24),
                          SwitchListTile(
                            title: const Text('Uso tarjeta de crédito'),
                            value: _usaTarjeta,
                            activeColor: primary,
                            onChanged: (val) {
                              setState(() => _usaTarjeta = val);
                            },
                          ),
                          if (_usaTarjeta) ...[
                            const SizedBox(height: 16),
                            _buildField(
                              label: 'Nombre de la Tarjeta',
                              controller: _nombreTarjetaController,
                              icon: Icons.credit_card,
                              isNumeric: false,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildField(
                                    label: 'Facturado (\$)',
                                    controller: _deudaFacturadaController,
                                    icon: Icons.money_off,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildField(
                                    label: 'No Fact. (\$)',
                                    controller: _deudaNoFacturadaController,
                                    icon: Icons.pending_actions,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _diaFacturacion,
                                    decoration: InputDecoration(
                                      labelText: 'Día Facturación',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    items: List.generate(31, (i) => i + 1)
                                        .map(
                                          (d) => DropdownMenuItem(
                                            value: d,
                                            child: Text('$d'),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null)
                                        setState(() => _diaFacturacion = val);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _diaVencimiento,
                                    decoration: InputDecoration(
                                      labelText: 'Día Vencimiento',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    items: List.generate(31, (i) => i + 1)
                                        .map(
                                          (d) => DropdownMenuItem(
                                            value: d,
                                            child: Text('$d'),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null)
                                        setState(() => _diaVencimiento = val);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // --- PASO 3: Presupuesto Global ---
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.track_changes, size: 64, color: primary),
                        const SizedBox(height: 24),
                        const Text(
                          'Presupuesto Global',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Establece un límite de gasto mensual para mantener un mejor control de tu dinero.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _buildField(
                          label: 'Presupuesto Inicial Mensual',
                          controller: _presupuestoController,
                          icon: Icons.monetization_on,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Podrás configurar presupuestos separados por categorías más tarde en la app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }
}
