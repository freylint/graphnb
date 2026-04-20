import { spawnSync } from 'child_process';
import { existsSync, mkdirSync, rmSync, readdirSync, readFileSync, writeFileSync, chmodSync } from 'fs';
import { join } from 'path';

export const DEBIAN_RELEASE = process.env.DEBIAN_RELEASE || 'testing';
export const DEBOOTSTRAP_VARIANT = 'minbase';
export const DEBOOTSTRAP_MIRROR = 'http://deb.debian.org/debian';
export const LOCAL_DIST_DIR_SRV = join(process.cwd(), 'dist/server/');
export const LOCAL_DIST_DIR_CLIENT = join(process.cwd(), 'dist/client/');
export const LOCAL_BUILD_DIR = join(process.cwd(), 'build/base/');

export type NotebookCell = {
  cell_type: string;
  source: string[] | string;
  id?: string;
  metadata?: Record<string, unknown>;
};

export type NotebookFile = {
  cells: NotebookCell[];
  metadata?: Record<string, unknown>;
  nbformat?: number;
  nbformat_minor?: number;
};

export function sourceLines(source: string[] | string): string[] {
  return Array.isArray(source) ? source : source.split('\n');
}

export function markdownAnchor(text: string): string {
  return text
    .trim()
    .replace(/[\`*_{}[\]()#+.!?:;,\/\\|"']/g, '')
    .replace(/\s+/g, '-');
}

export function updateNotebookToc(notebookPath = 'notebook.ipynb'): void {
  const raw = readFileSync(notebookPath, 'utf-8');
  const notebook = JSON.parse(raw) as NotebookFile;

  const tocCellIndex = notebook.cells.findIndex((cell) => {
    if (cell.cell_type !== 'markdown') {
      return false;
    }
    return sourceLines(cell.source).some((line) => line.trim() === '## Table of Contents');
  });

  if (tocCellIndex === -1) {
    throw new Error('Could not find a markdown cell titled "## Table of Contents".');
  }

  const headings: Array<{ level: number; text: string }> = [];
  for (let i = 0; i < notebook.cells.length; i += 1) {
    if (i === tocCellIndex) {
      continue;
    }

    const cell = notebook.cells[i];
    if (cell.cell_type !== 'markdown') {
      continue;
    }

    for (const line of sourceLines(cell.source)) {
      const match = line.match(/^(#{2,6})\s+(.+?)\s*$/);
      if (!match) {
        continue;
      }

      const level = match[1].length;
      const text = match[2].trim();
      if (text.toLowerCase() === 'table of contents') {
        continue;
      }

      headings.push({ level, text });
    }
  }

  if (headings.length === 0) {
    throw new Error('No markdown headings found to build the table of contents.');
  }

  const minLevel = Math.min(...headings.map((heading) => heading.level));
  const tocLines = [
    '## Table of Contents',
    '',
    ...headings.map((heading) => {
      const depth = Math.max(heading.level - minLevel, 0);
      const indent = '  '.repeat(depth);
      return `${indent}- [${heading.text}](#${markdownAnchor(heading.text)})`;
    }),
  ];

  notebook.cells[tocCellIndex].source = tocLines.map((line) => `${line}\n`);
  writeFileSync(notebookPath, `${JSON.stringify(notebook, null, 4)}\n`, { encoding: 'utf-8' });
}

export function runSyncCommand(command: string, args: string[], cwd?: string) {
  const result = spawnSync(command, args, {
    cwd,
    stdio: 'pipe',
    shell: false,
    encoding: 'utf8',
  });
  if (result.error) {
    throw result.error;
  }

  if (result.stdout) {
    console.log(result.stdout);
  }
  if (result.stderr) {
    console.error(result.stderr);
  }

  if (result.status !== 0) {
    throw new Error(`Command failed: ${command} ${args.join(' ')} (exit ${result.status})`);
  }
}

export function shellQuote(value: string) {
  if (/^[A-Za-z0-9_\/\.-]+$/.test(value)) {
    return value;
  }
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

export function runChrootCommand(chrootPath: string | undefined, command: string, args: string[], cwd?: string) {
  if (!chrootPath) {
    console.log(`Running command without chroot: ${command} ${args.join(' ')}`);
    return runSyncCommand(command, args, cwd);
  }

  checkCommandAvailable('chroot');
  if (!existsSync(chrootPath)) {
    throw new Error(`Chroot path does not exist: ${chrootPath}`);
  }

  const shellPath = join(chrootPath, 'bin/sh');
  if (!existsSync(shellPath)) {
    throw new Error(`Chroot target is missing shell: ${shellPath}`);
  }

  const shellCommand = [command, ...args].map(shellQuote).join(' ');
  console.log(`Running in chroot shell: /bin/sh -c ${shellCommand}`);
  return runSyncCommand('chroot', [chrootPath, '/bin/sh', '-c', shellCommand], cwd);
}

export function ensureDir(path: string) {
  if (!existsSync(path)) {
    mkdirSync(path, { recursive: true });
  }
}

export function isDirEmpty(path: string): boolean {
  if (!existsSync(path)) {
    return true;
  }
  return readdirSync(path).length === 0;
}

export function clearDir(path: string) {
  if (existsSync(path)) {
    rmSync(path, { recursive: true, force: true });
  }
  mkdirSync(path, { recursive: true });
}

export function checkCommandAvailable(command: string) {
  const result = spawnSync('command', ['-v', command], {
    stdio: 'ignore',
    shell: true,
  });
  if (result.status !== 0) {
    throw new Error(`Required command not found: ${command}`);
  }
}

export function addPreCommitHook(): void {
  const hookDir = join('.git', 'hooks');
  const hookPath = join(hookDir, 'pre-commit');

  if (!existsSync('.git')) {
    throw new Error('No .git directory found. Run this from the repository root.');
  }

  if (!existsSync(hookDir)) {
    mkdirSync(hookDir, { recursive: true });
  }

  const hookScript = [
    '#!/usr/bin/env bash',
    'set -euo pipefail',
    '',
    'make README.md',
    '',
    'git add README.md',
  ].join('\n');

  writeFileSync(hookPath, `${hookScript}\n`, { encoding: 'utf-8' });
  chmodSync(hookPath, 0o755);
}
