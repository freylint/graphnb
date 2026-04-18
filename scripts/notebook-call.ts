import * as ts from 'typescript';

function readStdin(): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => data += chunk);
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);
  });
}

async function main() {
  const args = process.argv.slice(2);
  const callIndex = args.indexOf('--call');
  const evalOnly = args.includes('--eval-only');

  let functionName: string | undefined;
  if (callIndex !== -1) {
    functionName = args[callIndex + 1];
    if (!functionName) {
      throw new Error('Missing function name after --call');
    }
  }

  const source = await readStdin();
  const transpiled = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020,
    },
  }).outputText;

  let js = transpiled;
  if (functionName) {
    js += `\nmodule.exports = ${functionName};`;
  }

  const module = { exports: {} as unknown };
  const exports = module.exports;
  eval(js);

  if (functionName) {
    const fn = module.exports as unknown;
    if (typeof fn !== 'function') {
      throw new Error(`Missing function: ${functionName}`);
    }
    (fn as Function)();
  } else if (!evalOnly) {
    // For compatibility, do nothing extra when no specific mode is passed.
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
