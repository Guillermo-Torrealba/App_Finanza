import os
import re

def modify_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    def replacer(match):
        # don't add it if it's already there
        return 'TextField(\ntextInputAction: TextInputAction.done,'

    new_content = re.sub(r'TextField\(', replacer, content)

    with open(filepath, 'w') as f:
        f.write(new_content)

for root, _, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart') and file != 'pantalla_principal.dart':
            modify_file(os.path.join(root, file))
