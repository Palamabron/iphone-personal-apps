const CACHE = 'warsaw-radar-shell-v2';
const BASE = new URL('./', self.location).href;
const SHELL = ['./', './index.html', './styles.css', './app.mjs', './lib/core.mjs', './manifest.webmanifest', './icon.svg', './icon-192.png', './apple-touch-icon.png'];
self.addEventListener('install', event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL.map(x => new URL(x, BASE).href))).then(() => self.skipWaiting())));
self.addEventListener('activate', event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('warsaw-radar-') && k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || url.pathname.includes('/api/') || url.pathname.includes('signin') || url.pathname.includes('callback')) return;
  event.respondWith(fetch(event.request).then(response => {
    if (response.ok && !response.redirected && new URL(response.url).origin === url.origin) { const clone = response.clone(); event.waitUntil(caches.open(CACHE).then(cache => cache.put(event.request, clone))); }
    return response;
  }).catch(async () => (await caches.match(event.request)) || (event.request.mode === 'navigate' ? caches.match(new URL('./index.html', BASE).href) : new Response('Offline', { status: 503 }))));
});
