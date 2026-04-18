#!/usr/bin/env python3
from pathlib import Path
import sys

args = sys.argv[1:]
if len(args) not in (0, 3):
    print('Usage: style-embed.py [index.html style.css notebook.html]', file=sys.stderr)
    sys.exit(1)

index_path = Path(args[0] if len(args) == 3 else 'build/index.html')
style_path = Path(args[1] if len(args) == 3 else 'public/style.css')
notebook_path = Path(args[2] if len(args) == 3 else 'build/notebook.html')

for path in (index_path, style_path, notebook_path):
    if not path.exists():
        print(f'Missing file: {path}', file=sys.stderr)
        sys.exit(1)

page = index_path.read_text(encoding='utf-8')
style = style_path.read_text(encoding='utf-8').rstrip()
notebook = notebook_path.read_text(encoding='utf-8')

page = page.replace('<!-- NBSTYLE ---->', f'<style>\n{style}\n</style>')
page = page.replace('<!-- NBNOTEBOOK -->', notebook)
index_path.write_text(page, encoding='utf-8')
