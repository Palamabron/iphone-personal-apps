import { CATEGORIES, DECISIONS, mergeEvents, normalizeEvent, selectEvents, rankEvent, reasons, priceLabel, localDay, formatDate, makeIcs, readState, warsawDateTime, httpUrl } from './lib/core.mjs';

const $ = selector => document.querySelector(selector);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
let state; try { state = readState(localStorage); } catch { state = readState({ getItem: () => null }); }
let snapshot = { events: [], sources: [], generatedAt: null }, currentView = 'discover', category = 'all', visible = 12;
let fetchedDraft = null, toastTimer;

function toast(message) { $('#toast').textContent = message; $('#toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => { $('#toast').hidden = true; }, 4500); }
function persist() { try { localStorage.setItem('warsaw-radar-v1', JSON.stringify(state)); } catch { $('#storage-warning').hidden = false; } }
function cacheSnapshot(value) { try { localStorage.setItem('warsaw-radar-snapshot-v1', JSON.stringify(value)); } catch { /* snapshot can be fetched next visit */ } }
function allEvents() {
  const sources = [...state.savedEvents, ...state.customEvents, ...snapshot.events];
  const key = value => { try { const u = new URL(value); u.search = ''; u.hash = ''; return u.href.replace(/\/$/, ''); } catch { return value; } };
  return mergeEvents(state.savedEvents, state.customEvents, snapshot.events).map(event => {
    // Retain an existing decision even if a source uses another ID for this URL.
    const selected = sources.find(item => key(item.url) === key(event.url) && state.decisions[item.id]);
    return selected ? { ...event, id: selected.id } : event;
  });
}
function download(content, type, filename) {
  const url = URL.createObjectURL(new Blob([content], { type })), a = document.createElement('a');
  a.href = url; a.download = filename; document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 60000);
}
function time(iso) { return formatDate(iso, { hour: '2-digit', minute: '2-digit', day: undefined, month: undefined }); }
function card(event) {
  const decision = state.decisions[event.id];
  const flags = { cancelled: 'Cancelled', 'sold-out': 'Sold out — check the waitlist', postponed: 'Rescheduled — check with the organizer' };
  const categories = [...event.categories].sort((a, b) => Number(state.interests.includes(b)) - Number(state.interests.includes(a)));
  const hours = `${time(event.startAt)}${event.endAt ? '–' + time(event.endAt) : ''}`;
  const place = event.venue || event.address || event.city || 'Venue to be confirmed';
  const address = event.venue && event.address && event.venue !== event.address ? event.address : (!event.venue && !event.address ? 'Check the exact location with the organizer' : '');
  const description = event.description && !['Tematy rozpoznane w ogłoszeniu:', 'Topics recognized in the announcement:'].some(prefix => event.description.startsWith(prefix)) ? `<p>${esc(event.description)}</p>` : '';
  return `<article class="event-card ${event.status === 'cancelled' ? 'cancelled' : ''}" data-event="${esc(event.id)}">
    <div class="event-top"><p class="event-time"><time datetime="${esc(event.startAt)}">${esc(hours)}</time></p><span class="price-label ${event.price.kind === 'free' ? 'free' : ''}">${esc(priceLabel(event.price))}</span></div>
    <h3><a href="${esc(event.url)}" target="_blank" rel="noopener noreferrer">${esc(event.title)}</a></h3>
    ${flags[event.status] ? `<p class="event-status ${event.status === 'cancelled' ? 'cancelled' : ''}">${esc(flags[event.status])}</p>` : ''}
    <p class="event-location">${esc(place)}${address ? `<span>${esc(address)}</span>` : ''}</p>
    <div class="tags">${categories.slice(0, 2).map(c => `<span class="tag">${esc(CATEGORIES[c])}</span>`).join('')}</div>
    <div class="card-footer"><div class="decisions" role="group" aria-label="Your choice for this event">${Object.entries(DECISIONS).map(([key, label]) => `<button data-decision="${key}" aria-pressed="${decision === key}" class="${decision === key ? 'selected' : ''}">${label}</button>`).join('')}</div><div class="event-links"><a class="event-primary" href="${esc(event.url)}" target="_blank" rel="noopener noreferrer">Details and registration ↗</a><button class="calendar" data-calendar>＋ Calendar</button></div></div>
    <details class="card-details"><summary>Organizer and details</summary><div class="card-details-body">${event.organizer ? `<p><strong>Organizer</strong><br>${esc(event.organizer)}</p>` : ''}${description}<p>${esc(reasons(event, state.interests))}</p>${categories.length ? `<p><strong>Topics:</strong> ${esc(categories.map(c => CATEGORIES[c]).join(', '))}</p>` : ''}${event.status === 'unknown' ? '<p>Check registration status on the organizer’s page.</p>' : ''}<p class="source-meta">${event.verifiedAt ? 'Source checked: ' + esc(formatDate(event.verifiedAt, { hour: '2-digit', minute: '2-digit' })) : 'Added manually · details unverified'}<br>${esc(new URL(event.url).hostname)}</p></div></details>
  </article>`;
}
function render() {
  const all = allEvents();
  $('#saved-count').textContent = Object.values(state.decisions).filter(d => ['going', 'maybe'].includes(d)).length;
  const events = selectEvents(all, { days: $('#days').value, category, search: $('#search').value.trim(), price: $('#price').value, saved: currentView === 'saved', interests: state.interests, decisions: state.decisions });
  $('#results-title').textContent = currentView === 'saved' ? 'Saved events' : 'Upcoming events';
  $('#result-count').textContent = events.length + ' events';
  $('#period-label').textContent = $('#days').selectedOptions[0].textContent.toLocaleUpperCase('pl-PL');
  const shown = events.slice(0, visible); let previousDay = '';
  $('#events').innerHTML = shown.map(event => { const day = localDay(event.startAt); const heading = day !== previousDay ? `<h3 class="day-heading">${esc(formatDate(event.startAt, { weekday: 'long', day: 'numeric', month: 'long' }))}</h3>` : ''; previousDay = day; return heading + card(event); }).join('') || '<div class="empty"><strong>No events found.</strong><br>Change your filters, refresh sources or add an event.</div>';
  $('#more').hidden = events.length <= visible;
  const interests = state.interests;
  $('#interests').innerHTML = Object.entries(CATEGORIES).map(([key, label]) => `<label><input type="checkbox" value="${key}" ${interests.includes(key) ? 'checked' : ''}>${label}</label>`).join('');
}
function renderSources() {
  const generated = snapshot.generatedAt && Number.isFinite(Date.parse(snapshot.generatedAt));
  $('#freshness').textContent = generated ? 'Last checked: ' + formatDate(snapshot.generatedAt, { year: 'numeric', hour: '2-digit', minute: '2-digit' }) + '. Times shown in Warsaw time.' : 'No recent data. Refresh sources or add a link.';
  const old = generated && Date.now() - Date.parse(snapshot.generatedAt) > 48 * 3600000;
  $('#notice').hidden = !old;
  if (old) $('#notice').textContent = 'Data is over 48 hours old. Refresh and confirm the time with the organizer.';
  $('#sources').innerHTML = (snapshot.sources || []).map(source => `<li>${httpUrl(source.url) ? `<a href="${esc(source.url)}" target="_blank" rel="noopener noreferrer">${esc(source.name || new URL(source.url).hostname)}</a>` : esc(source.name || 'Source')}: ${source.status === 'ok' ? esc(String(source.count ?? 0)) + ' events found' : 'unavailable — ' + esc(source.error || 'try again later')}</li>`).join('') || '<li>No source report.</li>';
}
function acceptSnapshot(value) {
  if (!value || !Array.isArray(value.events) || value.events.length > 3000) throw new Error('Invalid event data');
  state.savedEvents = mergeEvents(state.savedEvents, snapshot.events.filter(e => ['going', 'maybe'].includes(state.decisions[e.id])), value.events.filter(e => ['going', 'maybe'].includes(state.decisions[e.id])));
  persist();
  // A source can rate-limit or disappear. Missing from a partial snapshot is not evidence of cancellation.
  snapshot = { version: 1, generatedAt: value.generatedAt || null, events: mergeEvents(snapshot.events, value.events), sources: Array.isArray(value.sources) ? value.sources.slice(0, 50) : [] };
  renderSources(); render();
}
async function initialLoad() {
  try { const cached = localStorage.getItem('warsaw-radar-snapshot-v1'); if (cached) acceptSnapshot(JSON.parse(cached)); } catch { /* ignore corrupt cache */ }
  try { const response = await fetch('./data/events.json', { cache: 'no-cache' }); if (!response.ok) throw new Error(); const data = await response.json(); if (!snapshot.generatedAt || data.generatedAt > snapshot.generatedAt) { acceptSnapshot(data); cacheSnapshot(snapshot); } } catch { if (!snapshot.events.length) { renderSources(); render(); toast('Offline. You can still add events manually.'); } }
}
$('#categories').innerHTML = [['all', 'All'], ...Object.entries(CATEGORIES)].map(([key, label]) => `<button data-category="${key}" class="${key === category ? 'active' : ''}" aria-pressed="${key === category}">${label}</button>`).join('');
$('#categories').addEventListener('click', event => { const button = event.target.closest('[data-category]'); if (!button) return; category = button.dataset.category; for (const b of $('#categories').children) { b.classList.toggle('active', b === button); b.setAttribute('aria-pressed', String(b === button)); } visible = 12; render(); });
document.querySelectorAll('[data-view]').forEach(button => button.addEventListener('click', () => { currentView = button.dataset.view; document.querySelectorAll('[data-view]').forEach(b => b.classList.toggle('active', b === button)); visible = 12; render(); }));
for (const id of ['search', 'days', 'price']) $('#' + id).addEventListener(id === 'search' ? 'input' : 'change', () => { visible = 12; render(); });
$('#more').addEventListener('click', () => { visible += 12; render(); });
$('#events').addEventListener('click', event => {
  const article = event.target.closest('[data-event]'); if (!article) return;
  const item = allEvents().find(e => e.id === article.dataset.event); if (!item) return;
  const decisionButton = event.target.closest('[data-decision]');
  if (decisionButton) { const choice = decisionButton.dataset.decision; if (state.decisions[item.id] === choice) delete state.decisions[item.id]; else state.decisions[item.id] = choice; state.savedEvents = mergeEvents(state.savedEvents, [item]).filter(e => ['going', 'maybe'].includes(state.decisions[e.id])); persist(); render(); if (choice === 'hidden') toast('Event hidden. You can restore it in data settings.'); }
  if (event.target.closest('[data-calendar]')) download(makeIcs(item), 'text/calendar;charset=utf-8', 'event.ics');
});
$('#interests').addEventListener('change', () => { state.interests = [...$('#interests').querySelectorAll('input:checked')].map(i => i.value); persist(); render(); });
$('#export').addEventListener('click', () => download(JSON.stringify({ version: 1, exportedAt: new Date().toISOString(), ...state }, null, 2), 'application/json', 'warsaw-radar-backup.json'));
$('#restore-hidden').addEventListener('click', () => { state.decisions = Object.fromEntries(Object.entries(state.decisions).filter(([, value]) => value !== 'hidden')); persist(); render(); toast('Hidden events restored.'); });
$('#restore').addEventListener('change', async event => { const file = event.target.files[0]; if (!file) return; try { if (file.size > 2000000) throw new Error('Backup is too large'); const value = JSON.parse(await file.text()); if (value.version !== 1 || !value.decisions || !Array.isArray(value.customEvents)) throw new Error('Not a radar backup'); const imported = readState({ getItem: () => JSON.stringify(value) }); state = { decisions: { ...state.decisions, ...imported.decisions }, interests: imported.interests, customEvents: mergeEvents(state.customEvents, imported.customEvents), savedEvents: mergeEvents(state.savedEvents, imported.savedEvents) }; persist(); render(); toast('Backup restored.'); } catch (error) { toast(error.message || 'Could not read backup.'); } event.target.value = ''; });
$('#refresh').addEventListener('click', async () => {
  const button = $('#refresh'); button.disabled = true; button.querySelector('span').textContent = 'Checking sources…';
  try { const response = await fetch('./api/refresh', { method: 'POST', signal: AbortSignal.timeout(90000), headers: { 'Content-Type': 'application/json' }, body: '{}' }); if (!response.ok) throw new Error(response.status === 404 ? 'Source refresh is unavailable here. Add events manually.' : 'Sources are unavailable. Try again later.'); const value = await response.json(); if (!value.events?.length && snapshot.events.length) { snapshot.sources = Array.isArray(value.sources) ? value.sources : snapshot.sources; renderSources(); toast('No new data. Previous results kept; see the source report.'); return; } acceptSnapshot(value); cacheSnapshot(snapshot); toast('Sources checked. See the availability report below.'); } catch (error) { toast(error.name === 'TimeoutError' ? 'The request timed out. Previous results kept.' : error.message); } finally { button.disabled = false; button.querySelector('span').textContent = 'Refresh sources'; }
});

const importDialog = $('#import-dialog');
$('#import-url').addEventListener('input', () => { fetchedDraft = null; });
$('#import-open').addEventListener('click', () => { fetchedDraft = null; $('#import-form').reset(); $('#import-feedback').textContent = ''; importDialog.showModal(); });
$('#import-close').addEventListener('click', () => importDialog.close());
$('#import-fetch').addEventListener('click', async () => { fetchedDraft = null; const url = httpUrl($('#import-url').value); if (!url) { $('#import-feedback').textContent = 'Enter a valid HTTPS link.'; return; } const button = $('#import-fetch'); button.disabled = true; $('#import-feedback').textContent = 'Fetching details…'; try {
  const response = await fetch('./api/import', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url }), signal: AbortSignal.timeout(25000) });
  const value = await response.json().catch(() => ({})); if (!response.ok) throw new Error(value.error || 'Could not read this page. Enter verified details manually.'); const event = normalizeEvent(value.events?.[0]); if (!event) throw new Error('The page lacks a complete date or event name. Enter them manually.'); fetchedDraft = event;
  $('#import-title').value = event.title; $('#import-city').value = event.city || ''; $('#import-place').value = event.address || event.venue; $('#import-organizer').value = event.organizer; $('#import-category').value = event.categories[0] || 'ai'; $('#import-price').value = event.price.kind;
  const local = iso => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Warsaw', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(iso)).replace(' ', 'T'); $('#import-date').value = local(event.startAt); $('#import-end').value = event.endAt ? local(event.endAt) : ''; $('#import-feedback').textContent = value.warning || 'Details loaded. Check the fields and save.';
  } catch (error) { $('#import-feedback').textContent = error.message; } finally { button.disabled = false; }
});
$('#import-form').addEventListener('submit', event => { event.preventDefault(); const startAt = warsawDateTime($('#import-date').value), endAt = $('#import-end').value ? warsawDateTime($('#import-end').value) : null;
  if (!startAt || ($('#import-end').value && !endAt)) { $('#import-feedback').textContent = 'Invalid Warsaw time (check the daylight saving transition).'; return; }
  if (endAt && endAt <= startAt) { $('#import-feedback').textContent = 'End time must be after start time.'; return; }
  const url = httpUrl($('#import-url').value); if (!url) return;
  const draft = { ...(fetchedDraft || {}), id: fetchedDraft?.id || url, url, title: $('#import-title').value, startAt, endAt, city: $('#import-city').value.trim(), mode: fetchedDraft?.mode || 'unknown', venue: $('#import-place').value, address: $('#import-place').value, organizer: $('#import-organizer').value, categories: [$('#import-category').value], price: { kind: $('#import-price').value, amount: null, currency: null }, status: fetchedDraft?.status || 'unknown', verifiedAt: null, sources: [{ url, fetchedAt: null }] };
  state.customEvents = mergeEvents(state.customEvents.filter(e => e.url !== url), [draft]); persist(); render(); importDialog.close(); toast('Saved. Confirm manually entered details with the organizer.');
});

if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1')) navigator.serviceWorker.register('./sw.js').catch(() => {});
render(); initialLoad();
