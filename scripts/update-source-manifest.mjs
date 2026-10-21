import { execFileSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const paths = [...new Set(execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { cwd: root, encoding: 'utf8' }).split('\0').filter(name => name && name !== 'SOURCE-MANIFEST.json'))].sort();
const files = [];
for (const name of paths) {
  const bytes = await readFile(new URL('../' + name, import.meta.url));
  const canonical = name.endsWith('.png') ? bytes : Buffer.from(bytes.toString('utf8').replace(/\r\n/g, '\n'));
  files.push({ path: name, bytes: canonical.length, sha256: createHash('sha256').update(canonical).digest('hex') });
}
await writeFile(new URL('../SOURCE-MANIFEST.json', import.meta.url), JSON.stringify({ generatedAt: new Date().toISOString(), textLineEndings: 'LF', files }, null, 2) + '\n');
console.log(`Updated manifest for ${files.length} source files.`);
