#!/usr/bin/env python3

# GRAPHNB notebook tag synchronizer
# This script scans the notebook for special comment markers and updates the cell metadata tags accordingly.
# Markers and their corresponding tags:
# - "// hide-on-readme" or "# hide-on-readme" => "hide-on-readme"
# - "// hide-on-publish" or "# hide-on-publish" => "hide-on-publish"
# Usage: sync-notebook-tags.py <notebook.ipynb> 

import json
import sys
from pathlib import Path

MARKER_TO_TAG = {
    '// hide-on-readme': 'hide-on-readme',
    '# hide-on-readme': 'hide-on-readme',
    '// hide-on-publish': 'hide-on-publish',
    '# hide-on-publish': 'hide-on-publish',
}

if len(sys.argv) != 2:
    print('Usage: sync-notebook-tags.py <notebook.ipynb>', file=sys.stderr)
    sys.exit(1)

notebook_path = Path(sys.argv[1])
if not notebook_path.exists():
    print(f'Notebook not found: {notebook_path}', file=sys.stderr)
    sys.exit(1)

with notebook_path.open('r', encoding='utf-8') as f:
    notebook = json.load(f)

if 'nbformat' not in notebook:
    notebook['nbformat'] = 4
    changed = True
else:
    changed = False

if 'nbformat_minor' not in notebook:
    notebook['nbformat_minor'] = 4
    changed = True

if 'metadata' not in notebook:
    notebook['metadata'] = {}
    changed = True

for cell in notebook.get('cells', []):
    if 'id' in cell:
        del cell['id']
        changed = True

    source = cell.get('source', [])
    if isinstance(source, str):
        source = [source]

    joined_source = ''.join(source)
    metadata = cell.setdefault('metadata', {})
    tags = metadata.get('tags')
    if tags is None:
        metadata['tags'] = []
        tags = metadata['tags']

    if not isinstance(tags, list):
        continue

    for marker, tag in MARKER_TO_TAG.items():
        if marker in joined_source and tag not in tags:
            tags.append(tag)
            changed = True

if changed:
    with notebook_path.open('w', encoding='utf-8') as f:
        json.dump(notebook, f, indent=4, ensure_ascii=False)
        f.write('\n')

sys.exit(0)
