export const CATEGORIES = { ai: 'ML / AI', startup: 'Startupy', product: 'Produkt', funding: 'Finansowanie', networking: 'Networking' };
export const DECISIONS = { going: 'Idę', maybe: 'Może', hidden: 'Nie dla mnie' };
export const WARSAW = 'Europe/Warsaw';

export function httpUrl(value) {
  try { const u = new URL(value); return ['http:', 'https:'].includes(u.protocol) && !u.username && !u.password ? u.href : null; } catch { return null; }
}

function clean(value, limit = 500) { return typeof value === 'string' ? value.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '').trim().slice(0, limit) : ''; }
function strictIso(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,3})?)?(Z|[+-]\d{2}:\d{2})$/.exec(value);
  if (!match) return null;
  const [, year, month, day, hour, minute, second = '0'] = match;
  const calendar = new Date(Date.UTC(+year, +month - 1, +day));
  if (calendar.getUTCFullYear() !== +year || calendar.getUTCMonth() !== +month - 1 || calendar.getUTCDate() !== +day || +hour > 23 || +minute > 59 || +second > 59 || !Number.isFinite(Date.parse(value))) return null;
  return new Date(value).toISOString();
}
export function normalizeEvent(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const title = clean(raw.title, 240), url = httpUrl(raw.url);
  const startAt = strictIso(raw.startAt);
  if (!title || !url || !startAt) return null;
  const dateOrNull = strictIso;
  const price = raw.price && ['free', 'paid', 'unknown'].includes(raw.price.kind) ? raw.price : { kind: 'unknown' };
  return {
    id: clean(raw.id, 300) || url, title, url, startAt,
    endAt: dateOrNull(raw.endAt) > startAt ? dateOrNull(raw.endAt) : null, timezone: WARSAW,
    description: clean(raw.description, 900), organizer: clean(raw.organizer, 200),
    city: clean(raw.city, 120), venue: clean(raw.venue, 200), address: clean(raw.address, 300),
    language: clean(raw.language, 30) || null,
    mode: ['in-person', 'online', 'hybrid', 'unknown'].includes(raw.mode) ? raw.mode : 'unknown',
    status: ['scheduled', 'cancelled', 'sold-out', 'postponed', 'unknown'].includes(raw.status) ? raw.status : 'unknown',
    categories: Array.isArray(raw.categories) ? [...new Set(raw.categories.filter(k => Object.hasOwn(CATEGORIES, k)))] : [],
    price: { kind: price.kind, amount: Number.isFinite(price.amount) && price.amount >= 0 ? price.amount : null, currency: clean(price.currency, 6) || null },
    verifiedAt: dateOrNull(raw.verifiedAt),
    sources: Array.isArray(raw.sources) ? raw.sources.slice(0, 12).filter(s => httpUrl(s?.url)).map(s => ({ url: httpUrl(s.url), fetchedAt: dateOrNull(s.fetchedAt) })) : [],
  };
}

export function mergeEvents(...groups) {
  const byKey = new Map();
  for (const raw of groups.flat()) {
    const event = normalizeEvent(raw); if (!event) continue;
    const u = new URL(event.url); u.search = ''; u.hash = ''; const key = u.href.replace(/\/$/, '');
    const old = byKey.get(key);
    if (!old || (event.verifiedAt || '') >= (old.verifiedAt || '')) {
      if (old && ['cancelled', 'postponed'].includes(old.status) && !event.sources.some(s => s.url.replace(/\/$/, '') === key)) {
        event.status = old.status;
      }
      byKey.set(key, event);
    }
  }
  return [...byKey.values()];
}

export function localDay(iso) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: WARSAW, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(iso));
}
export function warsawDateTime(value) {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) return null;
  const approximate = Date.parse(value + ':00Z'); if (!Number.isFinite(approximate)) return null;
  const format = new Intl.DateTimeFormat('sv-SE', { timeZone: WARSAW, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
  // Współczesna Warszawa: CET / CEST. Przy powtórzonej godzinie wybieramy wcześniejsze wystąpienie.
  const candidates = [120, 60].map(offset => new Date(approximate - offset * 60000));
  return candidates.find(date => format.format(date).replace(' ', 'T') === value)?.toISOString() || null;
}
export function formatDate(iso, options = {}) {
  return new Intl.DateTimeFormat('pl-PL', { timeZone: WARSAW, day: 'numeric', month: 'short', ...options }).format(new Date(iso));
}
export function matchesWarsaw(event) {
  if (event.city) return /^(warsaw|warszawa)(?:$|[,\s])/i.test(event.city);
  return /\b(warszawa|warsaw)\b/i.test([event.address, event.venue].join(' '));
}
export function rankEvent(event, interests = ['ai', 'startup']) {
  const matched = event.categories.filter(c => interests.includes(c));
  return matched.length * 20 + (event.status === 'scheduled' ? 5 : 0) + (event.price.kind === 'free' ? 2 : 0);
}
export function reasons(event, interests = ['ai', 'startup']) {
  const matched = event.categories.filter(c => interests.includes(c)).map(c => CATEGORIES[c]);
  return matched.length ? 'Pasuje do: ' + matched.join(', ') : 'Sprawdź program i zdecyduj, czy temat Ci odpowiada.';
}

export function selectEvents(events, { now = new Date(), days = 30, category = 'all', search = '', price = 'all', saved = false, includeUnknownLocation = false, interests = ['ai', 'startup'], decisions = {} } = {}) {
  const start = Date.parse(now), end = start + Number(days) * 86400000;
  const query = search.toLocaleLowerCase('pl-PL');
  return events.filter(e => {
    const decision = decisions[e.id];
    if (saved) { if (!['going', 'maybe'].includes(decision)) return false; }
    else if (decision === 'hidden') return false;
    const time = Date.parse(e.startAt);
    if (time < start || time > end || e.mode === 'online') return false;
    if (!matchesWarsaw(e) && (!includeUnknownLocation || e.city)) return false;
    if (category !== 'all' && !e.categories.includes(category)) return false;
    if (price !== 'all' && e.price.kind !== price) return false;
    return !query || [e.title, e.description, e.organizer, e.venue].join(' ').toLocaleLowerCase('pl-PL').includes(query);
  }).sort((a, b) => Date.parse(a.startAt) - Date.parse(b.startAt) || rankEvent(b, interests) - rankEvent(a, interests));
}

export function priceLabel(price) {
  if (price.kind === 'free') return 'Bezpłatne';
  if (price.kind === 'paid' && price.amount !== null && price.currency) return new Intl.NumberFormat('pl-PL', { style: 'currency', currency: /^[A-Z]{3}$/.test(price.currency) ? price.currency : 'PLN', maximumFractionDigits: 2 }).format(price.amount);
  return price.kind === 'paid' ? 'Płatne · sprawdź cenę' : 'Cena nieustalona';
}

const icsEscape = value => String(value || '').replace(/\\/g, '\\\\').replace(/\r\n|\r|\n/g, '\\n').replace(/;/g, '\\;').replace(/,/g, '\\,');
const stamp = iso => new Date(iso).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
function foldLine(line) {
  const chunks = []; let part = '', bytes = 0;
  for (const c of line) { const length = new TextEncoder().encode(c).length; if (bytes + length > 73) { chunks.push(part); part = ' '; bytes = 1; } part += c; bytes += length; }
  return [...chunks, part].join('\r\n');
}
export function makeIcs(event, now = new Date()) {
  const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Warsaw Tech Radar//PL', 'CALSCALE:GREGORIAN', 'BEGIN:VEVENT',
    'UID:' + icsEscape(encodeURIComponent(event.id) + '@warsaw-tech-radar'), 'DTSTAMP:' + stamp(now), 'DTSTART:' + stamp(event.startAt)];
  if (event.endAt && Date.parse(event.endAt) > Date.parse(event.startAt)) lines.push('DTEND:' + stamp(event.endAt));
  lines.push('SUMMARY:' + icsEscape(event.title), 'LOCATION:' + icsEscape([event.venue, event.address || event.city].filter(Boolean).join(', ')), 'URL:' + event.url,
    'DESCRIPTION:' + icsEscape((event.description || '') + '\nZapisy i aktualne informacje: ' + event.url));
  if (event.status === 'cancelled') lines.push('STATUS:CANCELLED');
  lines.push('END:VEVENT', 'END:VCALENDAR'); return lines.map(foldLine).join('\r\n') + '\r\n';
}

export function readState(storage) {
  try {
    const value = JSON.parse(storage.getItem('warsaw-radar-v1') || '{}');
    const decisions = Object.fromEntries(Object.entries(value.decisions || {}).filter(([key, val]) => key.length <= 300 && Object.hasOwn(DECISIONS, val)));
    const interests = Array.isArray(value.interests) ? value.interests.filter(v => Object.hasOwn(CATEGORIES, v)) : ['ai', 'startup'];
    return { decisions, interests, customEvents: mergeEvents(Array.isArray(value.customEvents) ? value.customEvents : []), savedEvents: mergeEvents(Array.isArray(value.savedEvents) ? value.savedEvents : []) };
  } catch { return { decisions: {}, interests: ['ai', 'startup'], customEvents: [], savedEvents: [] }; }
}
