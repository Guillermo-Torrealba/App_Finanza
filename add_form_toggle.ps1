
$filePath = "lib\pantalla_principal.dart"
$content = [System.IO.File]::ReadAllText((Join-Path (Get-Location) $filePath), [System.Text.Encoding]::UTF8)

# 1. Add esFantasma variable next to esCredito in _mostrarFormulario
$oldVar = "    bool esCredito = false;`r`n    bool esCompartido = false;"
$newVar = "    bool esCredito = false;`r`n    bool esFantasmaForm = false;`r`n    bool esCompartido = false;"
$content = $content.Replace($oldVar, $newVar)

# 2. In edit mode, read estado
$oldEdit = "      final metodo = (itemParaEditar['metodo_pago'] ?? 'Debito').toString();`r`n      esCredito = metodo == 'Credito';"
$newEdit = "      final metodo = (itemParaEditar['metodo_pago'] ?? 'Debito').toString();`r`n      esCredito = metodo == 'Credito';`r`n      esFantasmaForm = (itemParaEditar['estado'] ?? 'real') == 'fantasma';"
$content = $content.Replace($oldEdit, $newEdit)

# 3. Add the toggle widget before the "Guardar" button
$oldGuardar = "                              // Guardar`r`n                              SizedBox(`r`n                                width: double.infinity,`r`n                                child: FilledButton.icon(`r`n                                  onPressed: guardar,"
$newGuardar = "                              // Toggle Proyectado`r`n                              if (!esTransferencia) ...[`r`n                                const SizedBox(height: 4),`r`n                                GestureDetector(`r`n                                  onTap: () => setStateSB(() => esFantasmaForm = !esFantasmaForm),`r`n                                  child: AnimatedContainer(`r`n                                    duration: const Duration(milliseconds: 200),`r`n                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),`r`n                                    decoration: BoxDecoration(`r`n                                      color: esFantasmaForm`r`n                                          ? (isDark ? Colors.purple.shade900.withAlpha(80) : Colors.purple.shade50)`r`n                                          : (isDark ? Colors.white.withAlpha(8) : Colors.grey.shade50),`r`n                                      borderRadius: BorderRadius.circular(12),`r`n                                      border: Border.all(`r`n                                        color: esFantasmaForm`r`n                                            ? (isDark ? Colors.purple.shade600 : Colors.purple.shade200)`r`n                                            : Colors.transparent,`r`n                                      ),`r`n                                    ),`r`n                                    child: Row(`r`n                                      children: [`r`n                                        Text(`r`n                                          '👻 Movimiento proyectado',`r`n                                          style: TextStyle(`r`n                                            fontSize: 14,`r`n                                            fontWeight: FontWeight.w600,`r`n                                            color: esFantasmaForm`r`n                                                ? (isDark ? Colors.purpleAccent.shade100 : Colors.purple.shade800)`r`n                                                : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),`r`n                                          ),`r`n                                        ),`r`n                                        const Spacer(),`r`n                                        Switch.adaptive(`r`n                                          value: esFantasmaForm,`r`n                                          onChanged: (v) => setStateSB(() => esFantasmaForm = v),`r`n                                          activeColor: Colors.purple.shade400,`r`n                                        ),`r`n                                      ],`r`n                                    ),`r`n                                  ),`r`n                                ),`r`n                                const SizedBox(height: 8),`r`n                              ],`r`n`r`n                              // Guardar`r`n                              SizedBox(`r`n                                width: double.infinity,`r`n                                child: FilledButton.icon(`r`n                                  onPressed: guardar,"
$content = $content.Replace($oldGuardar, $newGuardar)

# 4. Add 'estado' to new insert (non-transfer, non-shared path)
$oldInsert = "                        'tipo': tipo,`r`n                        'metodo_pago': metodo,`r`n                      })`r`n                      .select()`r`n                      .single();"
$newInsert = "                        'tipo': tipo,`r`n                        'metodo_pago': metodo,`r`n                        'estado': esFantasmaForm ? 'fantasma' : 'real',`r`n                      })`r`n                      .select()`r`n                      .single();"
$content = $content.Replace($oldInsert, $newInsert)

# 5. Add 'estado' to edit update
$oldUpdate = "                        'metodo_pago': metodo,`r`n                      })`r`n                      .eq('id', itemParaEditar['id'] as int);"
$newUpdate = "                        'metodo_pago': metodo,`r`n                        'estado': esFantasmaForm ? 'fantasma' : 'real',`r`n                      })`r`n                      .eq('id', itemParaEditar['id'] as int);"
$content = $content.Replace($oldUpdate, $newUpdate)

[System.IO.File]::WriteAllText((Join-Path (Get-Location) $filePath), $content, [System.Text.Encoding]::UTF8)
Write-Host "Form ghost toggle added!"
