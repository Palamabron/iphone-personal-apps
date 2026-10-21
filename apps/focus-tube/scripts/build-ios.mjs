import { mkdir, mkdtemp, readFile, readdir, writeFile, cp } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { VERSION } from '../src/core.js';

const root = fileURLToPath(new URL('../', import.meta.url));
if (process.platform !== 'darwin') throw new Error('Budowanie IPA wymaga macOS z Xcode. Windows/Ubuntu mogą przygotować źródła i zainstalować gotowe IPA przez SideStore.');
function run(command, args, capture = false) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit' });
  if (result.status !== 0) throw new Error(`${command} zakończył się błędem; zobacz log kompilacji.`);
  return result.stdout;
}
run(process.execPath, ['scripts/build.mjs', '--extension-only']);
const output = path.join(root, 'build', 'ios'); await mkdir(output, { recursive: true });
const work = await mkdtemp(path.join(output, 'focus-'));
const extension = path.join(work, 'extension'); await cp(path.join(root, 'dist', 'extension'), extension, { recursive: true });
// Safari's packager creates the signed-app container and extension targets. No Apple credentials are used in CI.
const manifest = JSON.parse(await readFile(path.join(extension, 'manifest.json'), 'utf8'));
manifest.name = 'Focus Tube';
manifest.description = 'YouTube w Safari bez Shortsów i nieskończonego przewijania.';
// The filter hooks YouTube's page-level SPA history, rather than an isolated content world.
manifest.content_scripts[0].world = 'MAIN';
manifest.icons = { 128: 'icon-128.png', 512: 'icon-512.png', 1024: 'icon-1024.png' };
for (const size of [128, 512]) await cp(path.join(root, 'ios', `icon-${size}.png`), path.join(extension, `icon-${size}.png`));
await cp(path.join(root, 'ios', 'AppIcon.png'), path.join(extension, 'icon-1024.png'));
await writeFile(path.join(extension, 'manifest.json'), JSON.stringify(manifest, null, 2));
const packager = spawnSync('xcrun', ['--find', 'safari-web-extension-packager'], { encoding: 'utf8' }).status === 0 ? 'safari-web-extension-packager' : 'safari-web-extension-converter';
run('xcrun', [packager, extension, '--project-location', work, '--app-name', 'Focus Tube', '--bundle-identifier', 'dev.palamabron.focustube', '--ios-only', '--swift', '--copy-resources', '--no-open', '--no-prompt']);
async function locate(folder, suffix) {
  for (const entry of await readdir(folder, { withFileTypes: true })) {
    const target = path.join(folder, entry.name); if (entry.name.endsWith(suffix)) return target;
    if (entry.isDirectory()) { const found = await locate(target, suffix); if (found) return found; }
  }
}
const project = await locate(work, '.xcodeproj'); if (!project) throw new Error('Packager nie utworzył projektu Xcode.');
const mainPage = await locate(path.dirname(project), 'Main.html');
if (!mainPage) throw new Error('Brak ekranu konfiguracji rozszerzenia.');
await cp(path.join(root, 'ios', 'Main.html'), mainPage);
await cp(path.join(root, 'ios', 'Style.css'), path.join(path.dirname(path.dirname(mainPage)), 'Style.css'));
const schemes = JSON.parse(run('xcodebuild', ['-list', '-json', '-project', project], true)).project.schemes;
const scheme = schemes.find(name => /iOS/i.test(name) && !/Extension/i.test(name)) || schemes.find(name => !/Extension/i.test(name));
if (!scheme) throw new Error('Nie znaleziono schematu aplikacji iOS.');
const derived = path.join(work, 'DerivedData');
run('xcodebuild', ['-project', project, '-scheme', scheme, '-configuration', 'Release', '-sdk', 'iphoneos', '-destination', 'generic/platform=iOS', '-derivedDataPath', derived, 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=', 'IPHONEOS_DEPLOYMENT_TARGET=18.0', `MARKETING_VERSION=${VERSION}`, 'CURRENT_PROJECT_VERSION=2', 'build']);
const products = path.join(derived, 'Build', 'Products', 'Release-iphoneos');
const app = (await readdir(products)).find(name => name.endsWith('.app')); if (!app) throw new Error('Brak skompilowanej aplikacji .app.');
const payload = path.join(work, 'Payload'); await mkdir(payload); await cp(path.join(products, app), path.join(payload, app), { recursive: true });
run('ditto', ['-c', '-k', '--keepParent', payload, path.join(output, 'FocusTube-unsigned.ipa')]);
console.log('Gotowe: build/ios/FocusTube-unsigned.ipa. Plik wymaga podpisania własnym kontem w SideStore/AltStore.');
