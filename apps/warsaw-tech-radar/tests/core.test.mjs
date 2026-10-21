import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeEvent, mergeEvents, selectEvents, priceLabel, makeIcs, localDay, warsawDateTime, readState } from '../lib/core.mjs';
const fixture = { id: 'a', title: 'ML meetup', startAt: '2026-10-27T18:00:00+01:00', city: 'Warsaw', url: 'https://luma.com/meetup', categories: ['ai'], price: { kind: 'unknown' }, sources: [{ url: 'https://luma.com/meetup', fetchedAt: '2026-10-21T12:00:00Z' }], verifiedAt: '2026-10-21T12:00:00Z' };
test('reject unsafe source URLs and timezone-free dates', () => {
  assert.equal(normalizeEvent({ ...fixture, url: 'javascript:alert(1)' }), null);
  assert.equal(normalizeEvent({ ...fixture, startAt: '2026-10-27T18:00:00' }), null);
  assert.equal(normalizeEvent({ ...fixture, startAt: '2026-02-31T18:00:00Z' }), null);
  assert.equal(normalizeEvent({ ...fixture, endAt: '2026-10-27T19:00:00' }).endAt, null);
  assert.equal(normalizeEvent({ ...fixture, title: '' }), null);
});
test('unknown prices stay unknown and free is explicit', () => { assert.equal(priceLabel(normalizeEvent(fixture).price), 'Cena nieustalona'); assert.equal(priceLabel({ kind: 'free' }), 'Bezpłatne'); });
test('merging the same URL updates date, not duplicate; separate series URLs remain', () => {
  const values = mergeEvents([fixture], [{ ...fixture, startAt: '2026-10-28T18:00:00+01:00', verifiedAt: '2026-10-22T12:00:00Z' }], [{ ...fixture, id: 'b', url: 'https://luma.com/meetup-2' }]);
  assert.equal(values.length, 2); assert.equal(values[0].startAt, '2026-10-28T17:00:00.000Z');
});
test('filters city, online, date range, hidden decisions and saved selection', () => {
  const events = mergeEvents([fixture, { ...fixture, id: 'online', url: 'https://luma.com/online', mode: 'online' }, { ...fixture, id: 'other', url: 'https://luma.com/other', city: 'Berlin' }]);
  const options = { now: new Date('2026-10-21T12:00:00Z') };
  assert.equal(selectEvents(events, options).length, 1);
  assert.equal(selectEvents(events, { ...options, days: 2 }).length, 0);
  assert.equal(selectEvents(events, { ...options, decisions: { a: 'hidden' } }).length, 0);
  assert.equal(selectEvents(events, { ...options, saved: true }).length, 0);
  assert.equal(selectEvents(events, { ...options, saved: true, decisions: { a: 'going' } }).length, 1);
  const conflicting = mergeEvents([{ ...fixture, id: 'wrong-city', city: 'Berlin', venue: 'Warsaw Society' }, { ...fixture, id: 'unknown-city', city: '', venue: '', url: 'https://luma.com/unknown-city' }]);
  assert.equal(selectEvents(conflicting, options).length, 0);
});
test('partial snapshots cannot restore an explicitly cancelled event without a current detail source', () => {
  const cancelled = { ...fixture, status: 'cancelled' };
  const listing = { ...fixture, status: 'scheduled', verifiedAt: '2026-10-22T12:00:00Z', sources: [{ url: 'https://luma.com/warsaw' }] };
  assert.equal(mergeEvents([cancelled], [listing])[0].status, 'cancelled');
  assert.equal(mergeEvents([cancelled], [{ ...listing, sources: fixture.sources }])[0].status, 'scheduled');
});
test('Warsaw DST conversion rejects nonexistent hour and supports both seasons', () => {
  assert.equal(warsawDateTime('2026-03-29T02:30'), null);
  assert.equal(warsawDateTime('2026-07-01T18:00'), '2026-07-01T16:00:00.000Z');
  assert.equal(warsawDateTime('2026-10-27T18:00'), '2026-10-27T17:00:00.000Z');
  assert.equal(localDay('2026-10-24T22:30:00Z'), '2026-10-25');
});
test('ICS has stable UID, UTC times, escaped user content and folded utf8 lines', () => {
  const e = normalizeEvent({ ...fixture, title: 'Test, ML; dziś\nAlarm: coś' + 'ą'.repeat(80) });
  const output = makeIcs(e, new Date('2026-10-21T12:00:00Z'));
  assert.match(output, /DTSTART:20261027T170000Z/); assert.match(output, /SUMMARY:Test\\, ML\\; dziś\\n/);
  assert.match(output, /\r\n /); assert.match(output, /UID:a@warsaw-tech-radar/);
  assert.ok(output.split('\r\n').every(line => Buffer.byteLength(line) <= 75));
});
test('broken browser storage and malformed backups are recoverable', () => {
  assert.deepEqual(readState({ getItem: () => '{' }).decisions, {});
  const value = readState({ getItem: () => JSON.stringify({ decisions: { a: 'invalid', b: 'going' }, interests: ['ai', 'bad'], customEvents: [{ ...fixture, url: 'data:x' }] }) });
  assert.deepEqual(value.decisions, { b: 'going' }); assert.deepEqual(value.interests, ['ai']); assert.equal(value.customEvents.length, 0);
});
