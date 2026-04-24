#!/usr/bin/env python3
import sys
from pathlib import Path

if len(sys.argv) != 2:
    print('Usage: wrap-output-spoilers.py <markdown-or-html-file>', file=sys.stderr)
    sys.exit(1)

path = Path(sys.argv[1])
if not path.exists():
    print(f'Missing file: {path}', file=sys.stderr)
    sys.exit(1)

text = path.read_text(encoding='utf-8')

if path.suffix.lower() == '.md':
    import re

    text = re.sub(r'<a\s+class="anchor-link"[^>]*>¶<\/a>', '', text)
    list_item_pattern = re.compile(r'^\s{4,}(?:[-+*]\s|\d+\.\s)')
    lines = text.splitlines()
    output_lines = []
    idx = 0

    while idx < len(lines):
        line = lines[idx]

        if line.startswith('```'):
            fence_marker = line[: len(line) - len(line.lstrip('`')) ]
            output_lines.append(line)
            idx += 1

            while idx < len(lines):
                output_lines.append(lines[idx])
                if lines[idx].strip() == fence_marker:
                    break
                idx += 1

            idx += 1
            while idx < len(lines) and lines[idx] == '':
                idx += 1

            if idx < len(lines) and lines[idx].startswith('    '):
                if output_lines[-1] != '':
                    output_lines.append('')
                output_lines.extend([
                    '<details class="output-spoiler">',
                    '<summary>Output</summary>',
                    '',
                    '```text',
                ])

                while idx < len(lines) and lines[idx].startswith('    '):
                    output_lines.append(lines[idx][4:])
                    idx += 1

                output_lines.extend([
                    '```',
                    '</details>',
                ])

                if idx < len(lines) and lines[idx] == '':
                    output_lines.append('')
                    idx += 1
            continue

        if line.startswith('    ') and not list_item_pattern.match(line):
            if idx == 0 or lines[idx - 1] == '':
                output_lines.append('')
                output_lines.extend([
                    '<details class="output-spoiler">',
                    '<summary>Output</summary>',
                    '',
                    '```text',
                ])
                while idx < len(lines) and lines[idx].startswith('    '):
                    output_lines.append(lines[idx][4:])
                    idx += 1
                output_lines.extend([
                    '```',
                    '</details>',
                ])
                if idx < len(lines) and lines[idx] == '':
                    output_lines.append('')
                    idx += 1
                continue

        output_lines.append(line)
        idx += 1

    path.write_text('\n'.join(output_lines) + '\n', encoding='utf-8')
elif path.suffix.lower() == '.html':
    def find_matching_closing_div(content: str, start_index: int) -> int:
        depth = 0
        pos = start_index
        while True:
            next_open = content.find('<div', pos)
            next_close = content.find('</div>', pos)
            if next_close == -1:
                return -1
            if next_open != -1 and next_open < next_close:
                depth += 1
                pos = next_open + 4
                continue
            depth -= 1
            pos = next_close + 6
            if depth == 0:
                return next_close
        return -1

    output = []
    idx = 0
    while True:
        start = text.find('<div class="output_wrapper"', idx)
        if start == -1:
            output.append(text[idx:])
            break

        output.append(text[idx:start])
        end = find_matching_closing_div(text, start)
        if end == -1:
            output.append(text[start:])
            break

        output.append('<details class="output_wrapper output-spoiler"><summary>Output</summary>')
        output.append(text[start:end + len('</div>')])
        output.append('</details>')
        idx = end + len('</div>')

    path.write_text(''.join(output), encoding='utf-8')
else:
    print(f'Unsupported file type: {path.suffix}', file=sys.stderr)
    sys.exit(1)
