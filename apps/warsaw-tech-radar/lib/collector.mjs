/** Public event collection. No cookies, credentials, private APIs or paid services. */
export const DEFAULT_SOURCES = Object.freeze([
  { name: 'Luma · Warszawa', url: 'https://luma.com/warsaw' },
  { name: 'Poland Tech Week', url: 'https://luma.com/polandtechweek' },
  { name: 'Śniadania AI Warszawa', url: 'https://luma.com/warsaw-ai-breakfast' },
  { name: 'Tech Leaders Collective Warsaw', url: 'https://luma.com/tlcwarsaw' },
  { name: 'Evenea · Warszawa', url: 'https://evenea.pl/wydarzenia/warszawa' },
]);

const HOSTS = new Set(['luma.com', 'www.luma.com', 'lu.ma', 'www.lu.ma', 'evenea.pl', 'www.evenea.pl', 'app.evenea.pl']);
const MAX_BYTES = 2_000_000;
const TIMEOUT_MS = 12_000;
const RESERVED_LUMA = new Set(['warsaw', 'polandtechweek', 'warsaw-ai-breakfast', 'tlcwarsaw', 'discover', 'home', 'signin', 'login', 'pricing', 'ios', 'android', 'create', 'calendars', 'settings', 'terms', 'privacy', 'about', 'help', 'search', 'user', 'calendar']);

/** A strict host allowlist also applies to every HTTP redirect. */
export function safeUrl(value, base) {
  try {
    if (typeof value !== 'string' || !value.trim()) return null;
    const url = new URL(value, base);
    if (url.protocol !== 'https:' || !HOSTS.has(url.hostname) || url.username || url.password || (url.port && url.port !== '443')) return null;
    if (/^\/(auth|signin|login|settings|session-|in\/|company\/)/i.test(url.pathname)) return null;
    url.hash = '';
    url.search = '';
    return url.href;
  } catch { return null; }
}

function clean(value, limit = 500) {
  if (typeof value !== 'string') return null;
  return value.replace(/<[^>]*>/g, ' ').replace(/&#(x[\da-f]+|\d+);/gi, (_, code) => {
    const num = code[0].toLowerCase() === 'x' ? parseInt(code.slice(1), 16) : Number(code);
    return num > 0 && num <= 0x10ffff ? String.fromCodePoint(num) : '';
  }).replace(/&quot;/g, '"').replace(/&apos;|&#39;/g, "'").replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim().slice(0, limit) || null;
}

function date(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,3})?)?(Z|[+-]\d{2}:\d{2})$/.exec(value);
  if (!match) return null; // Never invent a time or a UTC offset for date-only/local dates.
  const [, y, m, d, h, min, sec = '0'] = match;
  const calendar = new Date(Date.UTC(+y, +m - 1, +d));
  if (calendar.getUTCFullYear() !== +y || calendar.getUTCMonth() !== +m - 1 || calendar.getUTCDate() !== +d || +h > 23 || +min > 59 || +sec > 59) return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString() : null;
}

function hash(value) {
  let result = 2166136261;
  for (const char of value) result = Math.imul(result ^ char.charCodeAt(0), 16777619);
  return (result >>> 0).toString(36);
}

export function classifyCategories(text = '') {
  const value = text.toLowerCase();
  const categories = [];
  if (/\b(ai|ml|llm|grok|machine learning|deep learning|artificial intelligence|agentic|neural|pytorch|tensorflow)\b|sztuczn\w* inteligenc|uczeni\w* maszyn/.test(value)) categories.push('ai');
  if (/start[ -]?up|founder|cofounder|venture building|przedsiębior|przedsiebior|saas|y combinator|\byc\b/.test(value)) categories.push('startup');
  if (/\b(product|produkt|engineering|go.to.market|gtm|developer|software|fintech)\w*\b/.test(value)) categories.push('product');
  if (/network|mixer|matching|meetup|śniadani|sniadani|gathering|community|spotkani/.test(value)) categories.push('networking');
  if (/investor|investment|funding|fundrais|venture capital|\bvc\b|pitch|inwestor|inwestyc|finansowani/.test(value)) categories.push('funding');
  return categories;
}

function price(offers, isFree) {
  if (isFree === true) return { kind: 'free', amount: 0, currency: null };
  const list = Array.isArray(offers) ? offers : offers ? [offers] : [];
  const prices = list.map(offer => {
    const raw = offer.price ?? offer.lowPrice;
    const amount = typeof raw === 'number' ? raw : typeof raw === 'string' && /^\d+(\.\d+)?$/.test(raw.trim()) ? Number(raw) : NaN;
    return { amount, currency: clean(offer.priceCurrency, 5)?.toUpperCase() || null };
  }).filter(p => Number.isFinite(p.amount) && p.amount >= 0);
  if (!prices.length) return { kind: isFree === false ? 'paid' : 'unknown', amount: null, currency: null };
  // Multiple currencies cannot be compared; preserve the fact of payment, not a false minimum.
  if (new Set(prices.map(p => p.currency)).size > 1) return { kind: prices.some(p => p.amount === 0) ? 'unknown' : 'paid', amount: null, currency: null };
  const min = prices.reduce((a, b) => a.amount < b.amount ? a : b);
  return { kind: min.amount === 0 ? 'free' : 'paid', ...min };
}

function eventStatus(raw, offers = []) {
  const status = String(raw || '').toLowerCase();
  if (status.includes('cancel')) return 'cancelled';
  if (status.includes('postpon')) return 'postponed';
  const list = Array.isArray(offers) ? offers : offers ? [offers] : [];
  if (list.length && list.every(offer => /soldout/i.test(offer.availability || ''))) return 'sold-out';
  if (/scheduled|rescheduled/.test(status)) return 'scheduled';
  return 'unknown';
}

function joinNames(value) {
  const items = Array.isArray(value) ? value : value ? [value] : [];
  return [...new Set(items.map(item => clean(typeof item === 'string' ? item : item?.name, 120)).filter(Boolean))].join(', ') || null;
}

function createEvent(raw, sourceUrl, fetchedAt) {
  const title = clean(raw.name, 240);
  const startAt = date(raw.startDate);
  const url = safeUrl(raw.url || raw['@id'] || sourceUrl, sourceUrl);
  if (!title || !startAt || !url) return null;
  const end = date(raw.endDate);
  const endAt = end && end >= startAt ? end : null;
  const locations = Array.isArray(raw.location) ? raw.location : raw.location ? [raw.location] : [];
  const place = locations.find(location => typeof location === 'object' && !String(location['@type']).includes('Virtual'));
  const address = place?.address;
  const city = clean(typeof address === 'object' ? address.addressLocality : raw.city, 100);
  const street = clean(address?.streetAddress, 260);
  const fullAddress = typeof address === 'string' ? clean(address, 300) : street ? clean([street, address?.postalCode, street.toLowerCase().includes(String(address?.addressLocality || '').toLowerCase()) ? null : address?.addressLocality].filter(Boolean).join(', '), 300) : null;
  const attendance = String(raw.eventAttendanceMode || '');
  const mode = /Mixed/i.test(attendance) ? 'hybrid' : /Online/i.test(attendance) ? 'online' : /Offline/i.test(attendance) ? 'in-person' : 'unknown';
  const venue = clean(typeof place === 'string' ? place : place?.name, 240);
  const categories = classifyCategories([title, raw.description, joinNames(raw.organizer)].filter(Boolean).join(' '));
  // Store a short neutral classification instead of reproducing the organizer's full copy.
  const labels = { ai: 'AI / ML', startup: 'startupy', product: 'produkt i technologia', networking: 'networking', funding: 'finansowanie' };
  const description = categories.length ? `Tematy rozpoznane w ogłoszeniu: ${categories.map(key => labels[key]).join(', ')}.` : null;
  return {
    id: `event-${hash(url)}`, title, description, startAt, endAt,
    timezone: clean(raw.timezone, 80) || 'Europe/Warsaw', city, venue, address: fullAddress,
    mode, url, organizer: joinNames(raw.organizer), price: price(raw.offers, raw.isAccessibleForFree),
    categories, language: clean(raw.inLanguage, 30), status: eventStatus(raw.eventStatus, raw.offers),
    sources: [{ url: sourceUrl, fetchedAt }], verifiedAt: fetchedAt,
  };
}

function walk(value, visitor, depth = 0, state = { count: 0 }) {
  if (!value || typeof value !== 'object' || depth > 35 || state.count++ > 30_000) return;
  visitor(value);
  for (const child of Array.isArray(value) ? value : Object.values(value)) walk(child, visitor, depth + 1, state);
}

function structuredScripts(html) {
  html = String(html).slice(0, MAX_BYTES);
  const scripts = [];
  for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)) {
    if (!/(application\/ld\+json|__NEXT_DATA__)/i.test(match[1])) continue;
    try { scripts.push({ kind: /__NEXT_DATA__/i.test(match[1]) ? 'next' : 'jsonld', value: JSON.parse(match[2]) }); } catch { /* Bad markup is untrusted data. */ }
  }
  if (!scripts.length && /^\s*[\[{]/.test(html)) {
    try { scripts.push({ kind: 'jsonld', value: JSON.parse(html) }); } catch { /* Not JSON. */ }
  }
  return scripts;
}

function lumaEvent(container, sourceUrl) {
  const event = container.event;
  if (!event || typeof event !== 'object' || !event.start_at || !event.name) return null;
  const geo = event.geo_address_info || {};
  const localized = geo.localized?.pl || geo;
  const hidden = geo.mode === 'obfuscated' || event.geo_address_visibility === 'guests-only';
  const tickets = (container.ticket_types || []).filter(ticket => !ticket.is_hidden && !ticket.is_disabled);
  const ticketInfo = container.ticket_info || {};
  const raw = {
    name: event.name, startDate: event.start_at, endDate: event.end_at, timezone: event.timezone,
    url: event.url ? new URL(event.url, 'https://luma.com/').href : sourceUrl,
    location: { '@type': 'Place', name: hidden ? null : localized.address || geo.address, address: { addressLocality: localized.city || geo.city, streetAddress: hidden ? null : localized.short_address || geo.short_address } },
    eventAttendanceMode: event.location_type === 'online' ? 'OnlineEventAttendanceMode' : event.location_type === 'offline' ? 'OfflineEventAttendanceMode' : null,
    eventStatus: event.cancelled_at || event.is_cancelled ? 'EventCancelled' : 'EventScheduled',
    organizer: container.hosts,
    description: typeof container.description_mirror === 'string' ? container.description_mirror : JSON.stringify(container.description_mirror || ''),
    offers: tickets.map(ticket => ({ price: ticket.type === 'free' ? 0 : typeof ticket.cents === 'number' ? ticket.cents / 100 : undefined, priceCurrency: ticket.currency, availability: ticket.spots_remaining === 0 ? 'SoldOut' : undefined })),
    isAccessibleForFree: typeof ticketInfo.is_free === 'boolean' ? ticketInfo.is_free : undefined,
  };
  return { raw, hidden, soldOut: container.sold_out === true || ticketInfo.is_sold_out === true };
}

function mergeEvent(previous, next) {
  if (!previous) return next;
  const merge = { ...previous };
  for (const [key, value] of Object.entries(next)) {
    if (value !== null && value !== undefined && !(Array.isArray(value) && !value.length) && !(key === 'price' && value.kind === 'unknown') && !(key === 'status' && value === 'unknown')) merge[key] = value;
  }
  merge.categories = [...new Set([...previous.categories, ...next.categories])];
  merge.sources = [...new Map([...previous.sources, ...next.sources].map(source => [source.url, source])).values()];
  // A calendar's generic Scheduled default must not erase cancellation evidence.
  // A newly fetched event detail page can explicitly re-open a postponed/cancelled event.
  const nextIsDetail = next.sources.some(source => source.url === next.url);
  if (['cancelled', 'postponed'].includes(previous.status) && next.status === 'scheduled' && !nextIsDetail) merge.status = previous.status;
  return merge;
}

/** Parse JSON-LD Events/ItemLists and Luma's publicly rendered Next.js data. */
export function parseEventPage(html, url, fetchedAt = new Date().toISOString()) {
  const sourceUrl = safeUrl(url);
  if (!sourceUrl || !date(fetchedAt)) return [];
  const events = new Map();
  const scripts = structuredScripts(html);
  // The public app data often has richer addresses; JSON-LD carries explicit prices/status.
  for (const script of scripts.filter(item => item.kind === 'jsonld')) walk(script.value, value => {
    const types = Array.isArray(value['@type']) ? value['@type'] : [value['@type']];
    if (!types.some(type => /(^|\/)[A-Za-z]*Event$/.test(type || ''))) return;
    const event = createEvent(value, sourceUrl, fetchedAt);
    if (event) events.set(event.url, mergeEvent(events.get(event.url), event));
  });
  for (const script of scripts.filter(item => item.kind === 'next')) walk(script.value, value => {
    let parsed;
    try { parsed = lumaEvent(value, sourceUrl); } catch { return; }
    if (!parsed) return;
    const event = createEvent(parsed.raw, sourceUrl, fetchedAt);
    if (!event) return;
    const previous = events.get(event.url);
    if (parsed.soldOut && !['cancelled', 'postponed'].includes(previous?.status)) event.status = 'sold-out';
    else if (previous?.status && previous.status !== 'unknown' && !parsed.raw.eventStatus.includes('Cancelled')) event.status = previous.status;
    const merged = mergeEvent(previous, event);
    if (parsed.hidden) { merged.address = null; merged.venue = null; }
    events.set(event.url, merged);
  });
  return [...events.values()];
}

export function discoverEventLinks(html, baseUrl) {
  const found = new Set();
  function add(value) {
    const link = safeUrl(clean(value, 2000), baseUrl);
    if (!link) return;
    const url = new URL(link);
    if (/luma\.com$|lu\.ma$/.test(url.hostname)) {
      const path = url.pathname.split('/').filter(Boolean);
      if (path.length !== 1 || RESERVED_LUMA.has(path[0]) || /\.[a-z\d]{2,12}$/i.test(path[0])) return;
    } else if (!/\/(wydarzenie|event)\//.test(url.pathname)) return;
    found.add(link);
  }
  for (const event of parseEventPage(html, baseUrl)) add(event.url);
  for (const match of String(html).slice(0, MAX_BYTES).matchAll(/\bhref\s*=\s*["']([^"']+)["']/gi)) add(match[1]);
  return [...found].slice(0, 150);
}

/** Fetch once, bound time/bytes, and never follow an unapproved redirect. */
export async function fetchPublicPage(input, { fetchImpl = fetch, timeoutMs = TIMEOUT_MS, maxBytes = MAX_BYTES } = {}) {
  let url = safeUrl(input);
  if (!url) throw new Error('Nieobsługiwany lub niebezpieczny adres źródła.');
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    for (let redirects = 0; redirects <= 3; redirects++) {
      // Node/Workers have no browser cookie jar. Do not pass browser-only credentials:
      // some Workers compatibility dates reject that RequestInit property entirely.
      // Only these explicit public headers are sent; incoming request headers are never copied.
      const response = await fetchImpl(url, { redirect: 'manual', signal: controller.signal, headers: { Accept: 'text/html, application/ld+json, application/json', 'User-Agent': 'WarsawTechRadar/1.0 (personal public event reader)' } });
      if ([301, 302, 303, 307, 308].includes(response.status)) {
        const target = safeUrl(response.headers.get('location'), url);
        await response.body?.cancel();
        if (!target) throw new Error('Przekierowanie poza dozwolone publiczne źródła.');
        url = target;
        continue;
      }
      if (!response.ok) { await response.body?.cancel(); throw new Error(`HTTP ${response.status}; źródło może wymagać dostępu lub blokować pobieranie.`); }
      if (Number(response.headers.get('content-length')) > maxBytes) { await response.body?.cancel(); throw new Error('Strona przekracza limit rozmiaru.'); }
      const contentType = response.headers.get('content-type') || '';
      if (contentType && !/text\/html|application\/(ld\+)?json|text\/plain/.test(contentType)) { await response.body?.cancel(); throw new Error('Nieobsługiwany typ odpowiedzi.'); }
      let bytes = 0;
      const chunks = [];
      if (!response.body) throw new Error('Puste źródło.');
      const reader = response.body.getReader();
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        bytes += value.byteLength;
        if (bytes > maxBytes) { await reader.cancel(); throw new Error('Strona przekracza limit rozmiaru.'); }
        chunks.push(value);
      }
      const buffer = new Uint8Array(bytes);
      let position = 0;
      for (const chunk of chunks) { buffer.set(chunk, position); position += chunk.byteLength; }
      const html = new TextDecoder().decode(buffer);
      if (/_cf_chl_opt|cf-chl-widget|<title>Just a moment/i.test(html)) throw new Error('Strona wymaga weryfikacji CAPTCHA / Cloudflare. Kolektor jej nie obchodzi.');
      return { html, url, fetchedAt: new Date().toISOString() };
    }
    throw new Error('Zbyt wiele przekierowań.');
  } finally { clearTimeout(timeout); }
}

function relevant(event, now) {
  const technical = event.categories.some(category => ['ai', 'startup', 'product', 'funding'].includes(category));
  const unrelatedTitle = /speed dating|visual arts|photo walk|exhibition|exibition|the movie|social mixer|halloween|slow friending/i.test(event.title);
  return Date.parse(event.endAt || event.startAt) >= now && /^(warsaw|warszawa)$/i.test(event.city || '') && event.mode !== 'online' && technical && (!unrelatedTitle || /\b(ai|ml|startup)\b/i.test(event.title));
}

/** A snapshot can be written to disk or returned by a private Worker endpoint. */
export async function collectEvents({ now = new Date().toISOString(), sources = DEFAULT_SOURCES, fetchImpl = fetch, maxPages = 28 } = {}) {
  const timestamp = date(now);
  if (!timestamp) throw new Error('Parametr now musi zawierać datę ISO z godziną i strefą.');
  if (!Array.isArray(sources) || sources.length > 15) throw new Error('Dozwolone jest najwyżej 15 źródeł.');
  maxPages = Math.max(sources.length, Math.min(Number(maxPages) || 28, 50));
  const events = new Map();
  const reports = [];
  const discovered = new Set();
  const fetched = new Set();
  let pages = 0;
  async function read(source, isSeed) {
    if (pages++ >= maxPages) return;
    const url = safeUrl(source.url);
    const row = { name: clean(source.name, 120) || url || 'Źródło', url: url || String(source.url).slice(0, 500), status: 'error', fetchedAt: new Date().toISOString(), count: 0 };
    reports.push(row);
    if (!url) { row.error = 'Nieobsługiwany lub niebezpieczny adres źródła.'; return; }
    fetched.add(url);
    try {
      const page = await fetchPublicPage(url, { fetchImpl });
      row.fetchedAt = page.fetchedAt;
      const parsed = parseEventPage(page.html, page.url, page.fetchedAt);
      row.count = parsed.length;
      row.status = 'ok';
      for (const event of parsed) {
        if (!relevant(event, Date.parse(timestamp))) continue;
        events.set(event.url, mergeEvent(events.get(event.url), event));
        // Relevant event detail pages are visited before unrelated links.
        discovered.add(event.url);
      }
      if (isSeed) for (const link of discoverEventLinks(page.html, page.url)) discovered.add(link);
    } catch (error) {
      row.error = error.name === 'AbortError' ? 'Przekroczono czas pobierania (12 s).' : String(error.message).slice(0, 300);
    }
  }
  // Keep small concurrency so that refreshing from a phone does not burst requests.
  for (let i = 0; i < sources.length; i += 3) await Promise.all(sources.slice(i, i + 3).map(source => read(source, true)));
  const details = [...discovered].filter(url => !fetched.has(url)).slice(0, Math.max(0, maxPages - pages));
  for (let i = 0; i < details.length; i += 3) await Promise.all(details.slice(i, i + 3).map(url => read({ name: 'Strona wydarzenia', url }, false)));
  return { version: 1, generatedAt: new Date().toISOString(), events: [...events.values()].sort((a, b) => a.startAt.localeCompare(b.startAt) || a.title.localeCompare(b.title)), sources: reports };
}
