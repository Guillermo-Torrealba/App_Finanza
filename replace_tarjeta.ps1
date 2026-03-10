
$filePath = "lib\pantalla_principal.dart"
$content = Get-Content $filePath -Raw -Encoding UTF8

$startMarker = '  Widget _tarjetaTransaccion({'
$endMarker = "  Widget _selectorCuentas() {"

$startIdx = $content.IndexOf($startMarker)
$endIdx = $content.IndexOf($endMarker)

if ($startIdx -lt 0 -or $endIdx -lt 0) {
    Write-Error "Markers not found!"
    exit 1
}

$before = $content.Substring(0, $startIdx)
$after = $content.Substring($endIdx)

$newFunction = @'
  Widget _tarjetaTransaccion({
    required Map<String, dynamic> item,
    required double margin,
    required bool isDark,
  }) {
    final esIngreso = item['tipo'] == 'Ingreso';
    final categoria = (item['categoria'] ?? 'Varios').toString();
    final fechaItem = DateTime.parse(item['fecha']);
    final colorBase = esIngreso ? Colors.teal : Colors.red;
    final esFantasma = (item['estado'] ?? 'real') == 'fantasma';

    Widget card = InkWell(
      onTap: () => _mostrarDialogo(itemParaEditar: item),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: esFantasma
              ? []
              : [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 30 : 8),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
        ),
        child: Row(
          children: [
            Hero(
              tag: 'mov_${item['id']}',
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: esFantasma
                      ? Colors.grey.withAlpha(isDark ? 40 : 25)
                      : colorBase.withAlpha(isDark ? 40 : 25),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: esIngreso
                      ? Icon(
                          Icons.add_chart_rounded,
                          color: esFantasma
                              ? (isDark ? Colors.grey.shade400 : Colors.grey.shade500)
                              : (isDark ? Colors.tealAccent.shade400 : Colors.teal.shade700),
                          size: 24,
                        )
                      : _iconoCategoria(
                          categoria,
                          color: esFantasma
                              ? (isDark ? Colors.grey.shade400 : Colors.grey.shade500)
                              : (isDark ? Colors.redAccent.shade100 : Colors.red.shade700),
                          size: 24,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          (item['item'] ?? 'Sin nombre').toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (esFantasma) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.purple.shade900.withAlpha(100)
                                : Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isDark
                                  ? Colors.purple.shade700.withAlpha(120)
                                  : Colors.purple.shade200,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'PROYECTADO',
                            style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: isDark
                                  ? Colors.purpleAccent.shade100
                                  : Colors.purple.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${fechaItem.day} ${obtenerNombreMes(fechaItem.month).substring(0, 3)} · ${(item['cuenta'] ?? '-').toString()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _textoMonto(item['monto'] as num),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: esFantasma
                        ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
                        : (esIngreso
                              ? (isDark ? Colors.tealAccent.shade400 : Colors.teal.shade700)
                              : (isDark ? Colors.redAccent.shade100 : Colors.red.shade700)),
                  ),
                ),
                if ((item['metodo_pago'] ?? 'Debito') == 'Credito')
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.orangeAccent.withAlpha(40)
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CREDITO',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.orangeAccent : Colors.orange.shade800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (esFantasma) {
      card = CustomPaint(
        painter: _DashedBorderPainter(
          color: isDark
              ? Colors.purple.shade700.withAlpha(160)
              : Colors.purple.shade300,
          borderRadius: 16,
          dashWidth: 6,
          dashSpace: 4,
          strokeWidth: 1.2,
        ),
        child: card,
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin, vertical: 6),
      child: Opacity(
        opacity: esFantasma ? 0.72 : 1.0,
        child: Dismissible(
          key: Key('dismiss_${item['id']}'),
          direction: esFantasma
              ? DismissDirection.horizontal
              : DismissDirection.endToStart,
          secondaryBackground: Container(
            decoration: BoxDecoration(
              color: Colors.red.shade400,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          background: esFantasma
              ? Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.teal.shade500],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Confirmar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd && esFantasma) {
              await supabase
                  .from('gastos')
                  .update({'estado': 'real'})
                  .eq('id', item['id']);
              if (mounted) _mostrarSnack('Movimiento confirmado ✓');
              return false;
            }
            return true;
          },
          onDismissed: (_) async {
            await supabase.from('gastos').delete().eq('id', item['id']);
          },
          child: card,
        ),
      ),
    );
  }

'@

$newContent = $before + $newFunction + $after
[System.IO.File]::WriteAllText((Join-Path (Get-Location) $filePath), $newContent, [System.Text.Encoding]::UTF8)
Write-Host "Done!"
