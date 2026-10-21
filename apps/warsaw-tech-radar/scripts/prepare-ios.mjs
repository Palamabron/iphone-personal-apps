import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
const read = file => readFile(path.join(root, file), 'utf8');
function moduleSource(source, name) {
  const names = [...source.matchAll(/^export\s+(?:(?:async\s+)?function|const)\s+(\w+)/gm)].map(match => match[1]);
  return `const ${name} = (() => {\n${source.replace(/^export\s+/gm, '')}\nreturn {${names.join(',')}};\n})();`;
}
const core = moduleSource(await read('lib/core.mjs'), 'coreModule');
const collector = moduleSource(await read('lib/collector.mjs'), 'collectorModule');
const data = (await read('data/events.json')).replace(/</g, '\\u003c');
const bridge = `
window.RADAR_NATIVE = true;
const initialSnapshot = ${data};
const nativeValues = {...(window.__RADAR_NATIVE_STATE__ || {})};
const localStorage = {
  getItem: key => nativeValues[key] ?? null,
  setItem: (key,value) => { value=String(value); if(new TextEncoder().encode(value).length>4_000_000) throw new Error('Zapis jest za duży. Wyeksportuj kopię.'); window.webkit.messageHandlers.radar.postMessage({type:'store',key,value}); nativeValues[key] = value; }
};
const pending = new Map(); let sequence = 0;
window.__radarNativeComplete = (id, value) => { const call = pending.get(id); if(!call) return; pending.delete(id); call.cleanup(); value.error ? call.reject(new Error(value.error)) : call.resolve(value); };
function nativeCall(type, payload, signal) { return new Promise((resolve,reject) => {
  if(signal?.aborted) { reject(signal.reason); return; }
  const id=String(++sequence), abort=()=>{ pending.delete(id); reject(signal.reason); };
  const cleanup=()=>signal?.removeEventListener('abort',abort);
  pending.set(id,{resolve,reject,cleanup}); signal?.addEventListener('abort',abort,{once:true});
  try { window.webkit.messageHandlers.radar.postMessage({type,id,...payload}); }
  catch(error) { pending.delete(id); cleanup(); reject(error); }
}); }
function abortable(operation, signal) { return new Promise((resolve,reject) => {
  if(signal?.aborted) { reject(signal.reason); return; }
  const abort=()=>reject(signal.reason); signal?.addEventListener('abort',abort,{once:true});
  operation.then(resolve,reject).finally(()=>signal?.removeEventListener('abort',abort));
}); }
const nativeFetch = async (input, options={}) => {
  const route = String(input);
  if(options.signal?.aborted) throw options.signal.reason;
  const sourceFetch=(url, request={})=>nativeFetch(url,{...request,signal:options.signal ? AbortSignal.any([options.signal,...(request.signal?[request.signal]:[])]) : request.signal});
  if (route === './data/events.json') return new Response(JSON.stringify(initialSnapshot), {headers:{'content-type':'application/json'}});
  if (route === './api/refresh') return new Response(JSON.stringify(await abortable(collectorModule.collectEvents({fetchImpl:sourceFetch,maxPages:28}),options.signal)), {headers:{'content-type':'application/json'}});
  if (route === './api/import') {
    const url = collectorModule.safeUrl(JSON.parse(options.body || '{}').url);
    if (!url) return new Response(JSON.stringify({error:'Importuj publiczny link Luma/Evenea lub wpisz dane ręcznie.'}),{status:400});
    try { const page=await abortable(collectorModule.fetchPublicPage(url,{fetchImpl:sourceFetch}),options.signal); return new Response(JSON.stringify({events:collectorModule.parseEventPage(page.html,page.url,page.fetchedAt)})); }
    catch(error) { if(options.signal?.aborted) throw error; const cached=initialSnapshot.events.find(event=>collectorModule.safeUrl(event.url)===url); return new Response(JSON.stringify(cached ? {events:[cached],warning:'Użyto wcześniejszego odczytu. Potwierdź termin u organizatora.'} : {error:'Źródło jest niedostępne. Dodaj potwierdzone dane ręcznie.'}),{status:cached?200:502}); }
  }
  if (!collectorModule.safeUrl(route)) throw new Error('Niedozwolony adres źródła.');
  const response=await nativeCall('fetch',{url:route},options.signal);
  return new Response([204,205,304].includes(response.status)?null:response.body,{status:response.status,headers:response.headers});
};
const fetch = nativeFetch;
`;
// Each module retains its own scope, sharing the exact parsers and UI with the web app.
let app = await read('web/app.mjs');
app = app.replace(/^import\s+\{([^}]+)\}\s+from\s+'\.\/lib\/core\.mjs';/, 'const {$1} = coreModule;');
app = app.replace(/function download\(content, type, filename\) \{[\s\S]*?\n\}/, `function download(content, type, filename) { nativeCall('share',{content,mime:type,filename},AbortSignal.timeout(10000)).catch(()=>toast('Nie udało się otworzyć udostępniania. Spróbuj ponownie.')); }`);
app = app.replace("if ('serviceWorker' in navigator", "if (!window.RADAR_NATIVE && 'serviceWorker' in navigator");
const css = await read('web/styles.css');
let html = await read('web/index.html');
html = html.replace(/<link[^>]*>/g, '').replace('<script type="module" src="./app.mjs"></script>', '');
html = html.replace('</head>', `<style>${css}</style></head>`);
const javascript = `${core}\n${collector}\n(() => {\n${bridge}\n${app}\n})();`.replace(/<\/script/gi, '<\\/script');
html = html.replace('</body>', `<script>\n${javascript}\n</script></body>`).replace('class="brand" href="./"', 'class="brand" href="#"');
html = html.replace('Na iPhonie otwórz w Safari → Udostępnij → Dodaj do ekranu początkowego. Bez App Store i abonamentu.', 'Dane i zapisane wybory zostają w tej aplikacji. Źródła odświeżysz przyciskiem powyżej.');
const output = path.join(root, 'build', 'ios', 'resources'); await mkdir(output, { recursive: true });
await writeFile(path.join(output, 'radar.html'), html);
console.log('Przygotowano build/ios/resources/radar.html: wspólny interfejs i kolektor, lokalny zapis natywny, bez serwera.');
