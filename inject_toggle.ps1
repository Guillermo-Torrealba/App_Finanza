
$filePath = "lib\pantalla_principal.dart"
$lines = [System.IO.File]::ReadAllLines((Join-Path (Get-Location) $filePath), [System.Text.Encoding]::UTF8)

# Find the line with "// Boton guardar" in the second _mostrarFormulario
$insertBefore = -1
$formCount = 0
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match "void _mostrarFormulario\(") {
        $formCount++
    }
    if ($formCount -eq 2 -and $lines[$i] -match "// Bot.n guardar") {
        $insertBefore = $i
        break
    }
}

if ($insertBefore -lt 0) {
    Write-Error "Could not find insertion point!"
    exit 1
}

Write-Host "Inserting before line $($insertBefore + 1)"

$toggleLines = @(
    '                      // Toggle: Movimiento Proyectado',
    '                      if (!esTransferencia) ...[',
    '                        GestureDetector(',
    '                          onTap: () => setStateSB(() => esFantasmaForm = !esFantasmaForm),',
    '                          child: AnimatedContainer(',
    '                            duration: const Duration(milliseconds: 200),',
    '                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),',
    '                            decoration: BoxDecoration(',
    '                              color: esFantasmaForm',
    '                                  ? (isDark ? Colors.purple.shade900.withAlpha(80) : Colors.purple.shade50)',
    '                                  : (isDark ? Colors.white.withAlpha(8) : Colors.grey.shade50),',
    '                              borderRadius: BorderRadius.circular(12),',
    '                              border: Border.all(',
    '                                color: esFantasmaForm',
    '                                    ? (isDark ? Colors.purple.shade600 : Colors.purple.shade200)',
    '                                    : Colors.transparent,',
    '                              ),',
    '                            ),',
    '                            child: Row(',
    '                              children: [',
    "                                Text('Movimiento proyectado',",
    '                                  style: TextStyle(',
    '                                    fontSize: 14,',
    '                                    fontWeight: FontWeight.w600,',
    '                                    color: esFantasmaForm',
    '                                        ? (isDark ? Colors.purpleAccent.shade100 : Colors.purple.shade800)',
    '                                        : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),',
    '                                  ),',
    '                                ),',
    '                                const Spacer(),',
    '                                Switch.adaptive(',
    '                                  value: esFantasmaForm,',
    '                                  onChanged: (v) => setStateSB(() => esFantasmaForm = v),',
    '                                  activeColor: Colors.purple.shade400,',
    '                                ),',
    '                              ],',
    '                            ),',
    '                          ),',
    '                        ),',
    '                        const SizedBox(height: 12),',
    '                      ],'
)

$newLines = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($i -eq $insertBefore) {
        foreach ($tl in $toggleLines) {
            $newLines.Add($tl)
        }
    }
    $newLines.Add($lines[$i])
}

[System.IO.File]::WriteAllLines((Join-Path (Get-Location) $filePath), $newLines, [System.Text.Encoding]::UTF8)
Write-Host "Toggle widget inserted before line $($insertBefore + 1) successfully!"
