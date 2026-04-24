import { spawnSync, SpawnSyncOptionsWithStringEncoding, SpawnSyncReturns } from 'child_process';
import { existsSync, mkdirSync, rmSync, readdirSync, readFileSync, writeFileSync, chmodSync } from 'fs';
import { join } from 'path';

export const DEBIAN_RELEASE = process.env.DEBIAN_RELEASE || 'testing';
export const DEBOOTSTRAP_VARIANT = 'minbase';
export const DEBOOTSTRAP_MIRROR = 'http://deb.debian.org/debian';
export const LOCAL_DIST_DIR_SRV = join(process.cwd(), 'dist/server/');
export const LOCAL_DIST_DIR_CLIENT = join(process.cwd(), 'dist/client/');
export const LOCAL_DIST_DIR_GW = join(process.cwd(), 'dist/gateway/');
export const LOCAL_BUILD_DIR = join(process.cwd(), 'build/base/');

/**
 * A minimal notebook cell representation used by notebook utilities.
 */
export type NotebookCell = {
  cell_type: string;
  source: string[] | string;
  id?: string;
  metadata?: Record<string, unknown>;
};

/**
 * A minimal notebook document representation used by notebook utilities.
 */
export type NotebookFile = {
  cells: NotebookCell[];
  metadata?: Record<string, unknown>;
  nbformat?: number;
  nbformat_minor?: number;
};

/**
 * Normalize a cell source value to an array of string lines.
 *
 * @param source - Notebook cell source content.
 * @returns The source as an array of lines.
 */
export function sourceLines(source: string[] | string): string[] {
  return Array.isArray(source) ? source : source.split('\n');
}

/**
 * Convert heading text into a markdown anchor fragment.
 *
 * @param text - Heading text to normalize.
 * @returns A normalized anchor string.
 */
export function markdownAnchor(text: string): string {
  return text
    .trim()
    .replace(/[\`*_{}[\]()#+.!?:;,\/\\|"']/g, '')
    .replace(/\s+/g, '-');
}

/**
 * Regenerate the notebook Table of Contents cell from current markdown headings.
 *
 * @param notebookPath - Path to the notebook file.
 */
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

/**
 * Options for `spawnSyncCommand()`.
 *
 * This type allows callers to provide additional `spawnSync` options such as
 * `cwd` or `env` while preserving the helper's default encoding, stdio, and
 * shell configuration.
 */
export type SpawnCommandOptions = Omit<SpawnSyncOptionsWithStringEncoding, 'encoding' | 'stdio' | 'shell'> &
  Partial<Pick<SpawnSyncOptionsWithStringEncoding, 'encoding' | 'stdio' | 'shell'>>;

/**
 * Spawn a process with consistent options for the prelude.
 *
 * @param command - The command to run.
 * @param args - The command arguments.
 * @param options - Additional spawn options.
 */
export function spawnSyncCommand(
  command: string,
  args: string[],
  options: SpawnCommandOptions = {},
): SpawnSyncReturns<string> {
  return spawnSync(command, args, {
    stdio: 'pipe',
    encoding: 'utf8',
    shell: false,
    ...options,
  });
}

function assertSpawnResult(result: SpawnSyncReturns<string>, command: string, args: string[]) {
  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`Command failed: ${command} ${args.join(' ')} (exit ${result.status})`);
  }
}

function ensureDirectory(path: string) {
  mkdirSync(path, { recursive: true });
}

function pathExists(path: string): boolean {
  return existsSync(path);
}

/**
 * Execute a command synchronously and throw if it exits with an error.
 *
 * @param command - The command to run.
 * @param args - The command arguments.
 * @param cwd - Optional working directory for the command.
 */
export function runSyncCommand(command: string, args: string[], cwd?: string) {
  console.log(`\n> ${command} ${args.join(' ')}`);
  const result = spawnSyncCommand(command, args, { cwd });
  if (result.stdout) {
    console.log(result.stdout);
  }
  if (result.stderr) {
    console.error(result.stderr);
  }
  assertSpawnResult(result, command, args);
}

/**
 * Quote a string for safe shell use when needed.
 *
 * @param value - The string to quote.
 * @returns The quoted or original string.
 */
export function shellQuote(value: string) {
  if (/^[A-Za-z0-9_\/\.-]+$/.test(value)) {
    return value;
  }
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

/**
 * Run a command inside a chroot path, or directly if no chroot is provided.
 *
 * @param chrootPath - Path to the chroot directory.
 * @param command - The command to run.
 * @param args - Arguments for the command.
 * @param cwd - Optional working directory.
 */
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

/**
 * Ensure a directory exists.
 *
 * @param path - Directory path to create.
 */
export function ensureDir(path: string) {
  if (!pathExists(path)) {
    ensureDirectory(path);
  }
}

/**
 * Check whether a directory is empty or missing.
 *
 * @param path - Directory path to inspect.
 * @returns True when the directory does not exist or has no entries.
 */
export function isDirEmpty(path: string): boolean {
  if (!pathExists(path)) {
    return true;
  }
  return readdirSync(path).length === 0;
}

/**
 * Remove and recreate a directory.
 *
 * @param path - Directory path to clear.
 */
export function clearDir(path: string) {
  if (pathExists(path)) {
    rmSync(path, { recursive: true, force: true });
  }
  ensureDirectory(path);
}

/**
 * Throw when a required command is not available on PATH.
 *
 * @param command - Command name to check.
 */
export function checkCommandAvailable(command: string) {
  const result = spawnSyncCommand('command', ['-v', command], {
    stdio: 'ignore',
    shell: true,
  });
  if (result.status !== 0) {
    throw new Error(`Required command not found: ${command}`);
  }
}

/**
 * Install a Git pre-commit hook that regenerates README.md.
 */
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
