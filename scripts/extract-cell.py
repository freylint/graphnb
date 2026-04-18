#!/usr/bin/env python3
import json
import sys

if len(sys.argv) != 2:
    print('Usage: extract-cell.py <marker>', file=sys.stderr)
    sys.exit(1)

marker = sys.argv[1]
notebook_path = 'notebook.ipynb'

with open(notebook_path, 'r', encoding='utf-8') as f:
    notebook = json.load(f)

prelude_cells = []
for cell in notebook.get('cells', []):
    source = cell.get('source', [])
    if isinstance(source, str):
        source = [source]

    joined_source = ''.join(source)
    if marker in joined_source:
        sys.stdout.write(''.join(prelude_cells))
        sys.stdout.write(joined_source)
        sys.exit(0)

    if '// prelude' in joined_source:
        prelude_cells.append(joined_source)

sys.exit(1)
