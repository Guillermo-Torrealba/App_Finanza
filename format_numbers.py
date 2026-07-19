import re

with open('lib/gastos_compartidos_screen.dart', 'r') as f:
    content = f.read()

# Add import
content = content.replace(
    "import 'package:flutter/services.dart';",
    "import 'package:flutter/services.dart';\nimport 'package:intl/intl.dart';"
)

# Add formatter to class
class_def = "class _GastosCompartidosScreenState extends State<GastosCompartidosScreen> {"
formatter_def = class_def + "\n  static final _currencyFormat = NumberFormat('#,###', 'es_CL');\n"
content = content.replace(class_def, formatter_def)

# Replace instances in _copiarAlPortapapeles
content = content.replace(
    "buffer.writeln('- $item: \\$$monto');",
    "buffer.writeln('- $item: \\$${_currencyFormat.format(monto)}');"
)
content = content.replace(
    "buffer.writeln('Total: \\$$total');",
    "buffer.writeln('Total: \\$${_currencyFormat.format(total)}');"
)

# Replace instances in _buildListaDeudas
content = content.replace(
    "'\\$$totalPendiente',",
    "'\\$${_currencyFormat.format(totalPendiente)}',"
)
content = content.replace(
    "'\\$$totalGrupo',",
    "'\\$${_currencyFormat.format(totalGrupo)}',"
)
content = content.replace(
    "'\\$${d['monto']}',",
    "'\\$${_currencyFormat.format(d['monto'])}',"
)

with open('lib/gastos_compartidos_screen.dart', 'w') as f:
    f.write(content)

print("Done formatting numbers")

