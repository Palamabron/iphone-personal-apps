import test from 'node:test';
import assert from 'node:assert/strict';
import { safeUrl, parseEventPage, discoverEventLinks, fetchPublicPage, collectEvents } from '../lib/collector.mjs';

const fetchedAt = '2026-10-21T12:00:00.000Z';
const event = (changes = {}) => ({ '@type': 'Event', name: 'Warsaw ML meetup', startDate: '2026-10-26T18:00:00+01:00', endDate: '2026-10-26T20:00:00+01:00', url: 'https://luma.com/ml-meetup', eventAttendanceMode: 'https://schema.org/OfflineEventAttendanceMode', eventStatus: 'https://schema.org/EventScheduled', location: { '@type': 'Place', name: 'Sala', address: { streetAddress: 'Testowa 1', addressLocality: 'Warszawa' } }, ...changes });
const html = value => `<script type="application/ld+json">${JSON.stringify(value)}</script>`;

test('parses nested JSON-LD ItemLists, several events, offsets and explicit zero price', () => {
  const parsed = parseEventPage(html({ '@type': 'ItemList', itemListElement: [ { item: event({ offers: { price: '0', priceCurrency: 'PLN' } }) }, { item: event({ name: 'Startup pitch', url: 'https://luma.com/startup', startDate: '2026-10-24T18:00:00+02:00', offers: { price: 30, priceCurrency: 'pln' } }) } ] }), 'https://luma.com/warsaw', fetchedAt);
  assert.equal(parsed.length, 2);
  assert.equal(parsed[0].startAt, '2026-10-26T17:00:00.000Z');
  assert.equal(parsed[1].startAt, '2026-10-24T16:00:00.000Z');
  assert.deepEqual(parsed[0].price, { kind: 'free', amount: 0, currency: 'PLN' });
  assert.deepEqual(parsed[1].price, { kind: 'paid', amount: 30, currency: 'PLN' });
  assert.equal(parsed[0].address, 'Testowa 1, Warszawa');
  assert.ok(parsed[0].categories.includes('ai'));
  assert.deepEqual(parsed[0].sources, [{ url: 'https://luma.com/warsaw', fetchedAt }]);
});

test('missing, invalid, date-only and ambiguous local dates are never invented', () => {
  for (const value of [undefined, '', 'niedługo', '2026-10-26', '2026-10-25T02:30:00', '2026-02-31T12:00:00Z', '2026-13-01T12:00:00Z']) {
    assert.equal(parseEventPage(html(event({ startDate: value })), 'https://luma.com/test', fetchedAt).length, 0, value);
  }
  assert.equal(parseEventPage(html(event({ endDate: '2026-10-20T12:00:00Z' })), 'https://luma.com/test', fetchedAt)[0].endAt, null);
});

test('unknown price stays unknown; cancellation and sold out survive import', () => {
  const unknown = parseEventPage(html(event()), 'https://luma.com/test', fetchedAt)[0];
  assert.deepEqual(unknown.price, { kind: 'unknown', amount: null, currency: null });
  const cancelled = parseEventPage(html(event({ eventStatus: 'https://schema.org/EventCancelled', offers: { availability: 'https://schema.org/SoldOut' } })), 'https://luma.com/test', fetchedAt)[0];
  assert.equal(cancelled.status, 'cancelled');
  assert.equal(cancelled.price.kind, 'unknown');
  const soldOut = parseEventPage(html(event({ offers: [{ price: 40, priceCurrency: 'PLN', availability: 'https://schema.org/SoldOut' }] })), 'https://luma.com/test', fetchedAt)[0];
  assert.equal(soldOut.status, 'sold-out');
});

test('Luma Next data augments metadata, respects hidden addresses and does not duplicate events', () => {
  const raw = { event: { name: 'Warsaw ML meetup', start_at: '2026-10-26T17:00:00Z', url: 'ml-meetup', location_type: 'offline', timezone: 'Europe/Warsaw', geo_address_visibility: 'guests-only', geo_address_info: { mode: 'obfuscated', city: 'Warszawa', address: 'PRIVATE' } }, ticket_info: { is_free: true, is_sold_out: true }, hosts: [{ name: 'Organizator' }] };
  const page = html(event()) + `<script id="__NEXT_DATA__" type="application/json">${JSON.stringify({ props: { pageProps: { data: raw } } })}</script>`;
  const parsed = parseEventPage(page, 'https://luma.com/ml-meetup', fetchedAt);
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].venue, null);
  assert.equal(parsed[0].address, null);
  assert.equal(parsed[0].city, 'Warszawa');
  assert.equal(parsed[0].price.kind, 'free');
  assert.equal(parsed[0].status, 'sold-out');
  assert.equal(parsed[0].organizer, 'Organizator');
});

test('safeUrl rejects localhost, credentials, arbitrary domains, ports and deceptive hosts', () => {
  for (const value of ['http://luma.com/a', 'https://127.0.0.1', 'https://localhost', 'https://luma.com.evil.com/a', 'https://luma.com@evil.com', 'https://user:pass@luma.com/a', 'https://luma.com:8080/a', 'file:///etc/passwd', 'javascript:alert(1)', 'https://evenea.pl/auth/x']) assert.equal(safeUrl(value), null, value);
  assert.equal(safeUrl('/abc?tracking=1#hello', 'https://luma.com/warsaw'), 'https://luma.com/abc');
});

test('discovers public event links, excludes accounts, asset URLs and login', () => {
  const links = discoverEventLinks('<a href="/abc">A</a><a href="/abc#x">B</a><a href="/user/test">User</a><a href="/signin">Login</a><a href="https://evil.com/a">X</a><a href="https://evenea.pl/pl/wydarzenie/tech-123">E</a>', 'https://luma.com/warsaw');
  assert.deepEqual(links, ['https://luma.com/abc', 'https://evenea.pl/pl/wydarzenie/tech-123']);
});

test('redirects cannot escape the fetch allowlist', async () => {
  let calls = 0;
  await assert.rejects(fetchPublicPage('https://luma.com/test', { fetchImpl: async () => { calls++; return new Response(null, { status: 302, headers: { location: 'https://127.0.0.1/admin' } }); } }), /Przekierowanie/);
  assert.equal(calls, 1);
});

test('outbound fetch is compatible with Workers that reject browser credentials options', async () => {
  let captured;
  const result = await fetchPublicPage('https://luma.com/test', { fetchImpl: async (url, init) => {
    if (Object.hasOwn(init, 'credentials')) throw new Error("The 'credentials' field on 'RequestInitializerDict' is not implemented.");
    captured = init;
    return new Response('public HTML');
  } });
  assert.equal(result.html, 'public HTML');
  assert.equal(captured.headers.Cookie, undefined);
  assert.equal(captured.headers.Authorization, undefined);
  assert.equal(captured.redirect, 'manual');
});

test('fetch stops at response size limit and records challenge instead of bypassing', async () => {
  await assert.rejects(fetchPublicPage('https://luma.com/test', { maxBytes: 5, fetchImpl: async () => new Response('123456') }), /limit rozmiaru/);
  await assert.rejects(fetchPublicPage('https://evenea.pl/', { fetchImpl: async () => new Response('<title>Just a moment...</title>') }), /CAPTCHA/);
});

test('collector excludes past, non-Warsaw and online events, merges sources and reports failures', async () => {
  const page = html([event(), event({ url: 'https://luma.com/old', startDate: '2026-09-01T12:00:00Z', endDate: '2026-09-01T14:00:00Z' }), event({ url: 'https://luma.com/online', eventAttendanceMode: 'https://schema.org/OnlineEventAttendanceMode' }), event({ url: 'https://luma.com/krakow', location: { address: { addressLocality: 'Kraków' } } })]);
  const sources = [{ name: 'Luma Warsaw', url: 'https://luma.com/warsaw' }, { name: 'Evenea', url: 'https://evenea.pl/' }];
  let count = 0;
  const snapshot = await collectEvents({ now: fetchedAt, sources, maxPages: 3, fetchImpl: async url => { count++; return url.includes('evenea') ? new Response('', { status: 403 }) : new Response(page); } });
  assert.equal(snapshot.events.length, 1);
  assert.equal(snapshot.events[0].title, 'Warsaw ML meetup');
  assert.equal(snapshot.sources[1].status, 'error');
  assert.equal(snapshot.events[0].sources.length, 2);
  assert.equal(count, 3);
});

test('broken JSON and untrusted embedded text are not executed', () => {
  assert.deepEqual(parseEventPage('<script type="application/ld+json">{bad}</script><script>throw new Error("execute me")</script>', 'https://luma.com/test', fetchedAt), []);
  assert.deepEqual(parseEventPage(html(event({ url: 'https://malicious.example/event' })), 'https://luma.com/test', fetchedAt), []);
});

test('a second calendar Scheduled default does not erase a cancelled event during partial collection', async () => {
  const snapshot = await collectEvents({ now: fetchedAt, maxPages: 2, sources: [{ name: 'One', url: 'https://luma.com/warsaw' }, { name: 'Two', url: 'https://luma.com/polandtechweek' }], fetchImpl: async url => new Response(html(event({ eventStatus: url.endsWith('/warsaw') ? 'https://schema.org/EventCancelled' : 'https://schema.org/EventScheduled' }))) });
  assert.equal(snapshot.events[0].status, 'cancelled');
});
