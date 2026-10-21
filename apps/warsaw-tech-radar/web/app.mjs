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
  const custom = mergeEvents(state.customEvents);
  const customUrls = new Set(custom.map(e => e.url));
  return [...mergeEvents(snapshot.events, state.savedEvents).filter(e => !customUrls.has(e.url)), ...custom];
}
function download(content, type, filename) {
  const url = URL.createObjectURL(new Blob([content], { type })), a = document.createElement('a');
  a.href = url; a.download = filename; document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 60000);
}
function time(iso) { return formatDate(iso, { hour: '2-digit', minute: '2-digit', day: undefined, month: undefined }); }
function card(event) {
  const decision = state.decisions[event.id];
  const flags = { cancelled: 'Odwołane', 'sold-out': 'Brak miejsc — sprawdź listę rezerwową', postponed: 'Termin zmieniony — sprawdź u organizatora' };
  const categories = [...event.categories].sort((a, b) => Number(state.interests.includes(b)) - Number(state.interests.includes(a)));
  const hours = `${time(event.startAt)}${event.endAt ? '–' + time(event.endAt) : ''}`;
  const place = event.venue || event.address || event.city || 'Miejsce do sprawdzenia';
  const address = event.venue && event.address && event.venue !== event.address ? event.address : (!event.venue && !event.address ? 'Dokładne miejsce sprawdź u organizatora' : '');
  const description = event.description && !event.description.startsWith('Tematy rozpoznane w ogłoszeniu:') ? `<p>${esc(event.description)}</p>` : '';
  return `<article class="event-card ${event.status === 'cancelled' ? 'cancelled' : ''}" data-event="${esc(event.id)}">
    <div class="event-top"><p class="event-time"><time datetime="${esc(event.startAt)}">${esc(hours)}</time></p><span class="price-label ${event.price.kind === 'free' ? 'free' : ''}">${esc(priceLabel(event.price))}</span></div>
    <h3><a href="${esc(event.url)}" target="_blank" rel="noopener noreferrer">${esc(event.title)}</a></h3>
    ${flags[event.status] ? `<p class="event-status ${event.status === 'cancelled' ? 'cancelled' : ''}">${esc(flags[event.status])}</p>` : ''}
    <p class="event-location">${esc(place)}${address ? `<span>${esc(address)}</span>` : ''}</p>
    <div class="tags">${categories.slice(0, 2).map(c => `<span class="tag">${esc(CATEGORIES[c])}</span>`).join('')}</div>
    <div class="card-footer"><div class="decisions" role="group" aria-label="Twój wybór dla tego wydarzenia">${Object.entries(DECISIONS).map(([key, label]) => `<button data-decision="${key}" aria-pressed="${decision === key}" class="${decision === key ? 'selected' : ''}">${label}</button>`).join('')}</div><div class="event-links"><a class="event-primary" href="${esc(event.url)}" target="_blank" rel="noopener noreferrer">Szczegóły i zapisy ↗</a><button class="calendar" data-calendar>＋ Kalendarz</button></div></div>
    <details class="card-details"><summary>Organizator i szczegóły</summary><div class="card-details-body">${event.organizer ? `<p><strong>Organizator</strong><br>${esc(event.organizer)}</p>` : ''}${description}<p>${esc(reasons(event, state.interests))}</p>${categories.length ? `<p><strong>Tematy:</strong> ${esc(categories.map(c => CATEGORIES[c]).join(', '))}</p>` : ''}${event.status === 'unknown' ? '<p>Status zapisów sprawdź na stronie organizatora.</p>' : ''}<p class="source-meta">${event.verifiedAt ? 'Odczyt źródła: ' + esc(formatDate(event.verifiedAt, { hour: '2-digit', minute: '2-digit' })) : 'Dodane ręcznie · dane do sprawdzenia'}<br>${esc(new URL(event.url).hostname)}</p></div></details>
  </article>`;
}
function render() {
  const all = allEvents();
  $('#saved-count').textContent = Object.values(state.decisions).filter(d => ['going', 'maybe'].includes(d)).length;
  const events = selectEvents(all, { days: $('#days').value, category, search: $('#search').value.trim(), price: $('#price').value, saved: currentView === 'saved', interests: state.interests, decisions: state.decisions });
  $('#results-title').textContent = currentView === 'saved' ? 'Twoje zapisane wydarzenia' : 'Nadchodzące wydarzenia';
  $('#result-count').textContent = events.length + ' propozycji';
  $('#period-label').textContent = $('#days').selectedOptions[0].textContent.toLocaleUpperCase('pl-PL');
  const shown = events.slice(0, visible); let previousDay = '';
  $('#events').innerHTML = shown.map(event => { const day = localDay(event.startAt); const heading = day !== previousDay ? `<h3 class="day-heading">${esc(formatDate(event.startAt, { weekday: 'long', day: 'numeric', month: 'long' }))}</h3>` : ''; previousDay = day; return heading + card(event); }).join('') || '<div class="empty"><strong>Na razie spokojnie.</strong><br>Brak wydarzeń dla tych filtrów. Zmień okres, odśwież źródła lub dodaj spotkanie z linku.</div>';
  $('#more').hidden = events.length <= visible;
  const interests = state.interests;
  $('#interests').innerHTML = Object.entries(CATEGORIES).map(([key, label]) => `<label><input type="checkbox" value="${key}" ${interests.includes(key) ? 'checked' : ''}>${label}</label>`).join('');
}
function renderSources() {
  const generated = snapshot.generatedAt && Number.isFinite(Date.parse(snapshot.generatedAt));
  $('#freshness').textContent = generated ? 'Ostatni odczyt: ' + formatDate(snapshot.generatedAt, { year: 'numeric', hour: '2-digit', minute: '2-digit' }) + '. Daty i godziny: Warszawa.' : 'Brak aktualnego odczytu. Odśwież źródła lub dodaj własny link.';
  const old = generated && Date.now() - Date.parse(snapshot.generatedAt) > 48 * 3600000;
  $('#notice').hidden = !old;
  if (old) $('#notice').textContent = 'Dane mają ponad 48 godzin. Odśwież źródła i potwierdź termin u organizatora przed wyjściem.';
  $('#sources').innerHTML = (snapshot.sources || []).map(source => `<li>${httpUrl(source.url) ? `<a href="${esc(source.url)}" target="_blank" rel="noopener noreferrer">${esc(source.name || new URL(source.url).hostname)}</a>` : esc(source.name || 'Źródło')}: ${source.status === 'ok' ? esc(String(source.count ?? 0)) + ' odczytanych wydarzeń' : 'niedostępne — ' + esc(source.error || 'spróbuj później')}</li>`).join('') || '<li>Brak raportu źródeł.</li>';
}
function acceptSnapshot(value) {
  if (!value || !Array.isArray(value.events) || value.events.length > 3000) throw new Error('Nieprawidłowe dane wydarzeń');
  state.savedEvents = mergeEvents(state.savedEvents, snapshot.events.filter(e => ['going', 'maybe'].includes(state.decisions[e.id])), value.events.filter(e => ['going', 'maybe'].includes(state.decisions[e.id])));
  persist();
  // A source can rate-limit or disappear. Missing from a partial snapshot is not evidence of cancellation.
  snapshot = { version: 1, generatedAt: value.generatedAt || null, events: mergeEvents(snapshot.events, value.events), sources: Array.isArray(value.sources) ? value.sources.slice(0, 50) : [] };
  renderSources(); render();
}
async function initialLoad() {
  try { const cached = localStorage.getItem('warsaw-radar-snapshot-v1'); if (cached) acceptSnapshot(JSON.parse(cached)); } catch { /* ignore corrupt cache */ }
  try { const response = await fetch('./data/events.json', { cache: 'no-cache' }); if (!response.ok) throw new Error(); const data = await response.json(); if (!snapshot.generatedAt || data.generatedAt > snapshot.generatedAt) { acceptSnapshot(data); cacheSnapshot(snapshot); } } catch { if (!snapshot.events.length) { renderSources(); render(); toast('Brak połączenia. Możesz nadal dodawać własne wydarzenia.'); } }
}
$('#categories').innerHTML = [['all', 'Wszystko'], ...Object.entries(CATEGORIES)].map(([key, label]) => `<button data-category="${key}" class="${key === category ? 'active' : ''}" aria-pressed="${key === category}">${label}</button>`).join('');
$('#categories').addEventListener('click', event => { const button = event.target.closest('[data-category]'); if (!button) return; category = button.dataset.category; for (const b of $('#categories').children) { b.classList.toggle('active', b === button); b.setAttribute('aria-pressed', String(b === button)); } visible = 12; render(); });
document.querySelectorAll('[data-view]').forEach(button => button.addEventListener('click', () => { currentView = button.dataset.view; document.querySelectorAll('[data-view]').forEach(b => b.classList.toggle('active', b === button)); visible = 12; render(); }));
for (const id of ['search', 'days', 'price']) $('#' + id).addEventListener(id === 'search' ? 'input' : 'change', () => { visible = 12; render(); });
$('#more').addEventListener('click', () => { visible += 12; render(); });
$('#events').addEventListener('click', event => {
  const article = event.target.closest('[data-event]'); if (!article) return;
  const item = allEvents().find(e => e.id === article.dataset.event); if (!item) return;
  const decisionButton = event.target.closest('[data-decision]');
  if (decisionButton) { const choice = decisionButton.dataset.decision; if (state.decisions[item.id] === choice) delete state.decisions[item.id]; else state.decisions[item.id] = choice; state.savedEvents = mergeEvents(state.savedEvents, [item]).filter(e => ['going', 'maybe'].includes(state.decisions[e.id])); persist(); render(); if (choice === 'hidden') toast('Ukryto wydarzenie. Możesz je przywrócić w ustawieniach danych.'); }
  if (event.target.closest('[data-calendar]')) download(makeIcs(item), 'text/calendar;charset=utf-8', 'wydarzenie.ics');
});
$('#interests').addEventListener('change', () => { state.interests = [...$('#interests').querySelectorAll('input:checked')].map(i => i.value); persist(); render(); });
$('#export').addEventListener('click', () => download(JSON.stringify({ version: 1, exportedAt: new Date().toISOString(), ...state }, null, 2), 'application/json', 'warsaw-radar-kopia.json'));
$('#restore-hidden').addEventListener('click', () => { state.decisions = Object.fromEntries(Object.entries(state.decisions).filter(([, value]) => value !== 'hidden')); persist(); render(); toast('Przywrócono odrzucone wydarzenia.'); });
$('#restore').addEventListener('change', async event => { const file = event.target.files[0]; if (!file) return; try { if (file.size > 2000000) throw new Error('Kopia jest za duża'); const value = JSON.parse(await file.text()); if (value.version !== 1 || !value.decisions || !Array.isArray(value.customEvents)) throw new Error('To nie jest kopia radaru'); const imported = readState({ getItem: () => JSON.stringify(value) }); state = { decisions: { ...state.decisions, ...imported.decisions }, interests: imported.interests, customEvents: mergeEvents(state.customEvents, imported.customEvents), savedEvents: mergeEvents(state.savedEvents, imported.savedEvents) }; persist(); render(); toast('Przywrócono dane z kopii.'); } catch (error) { toast(error.message || 'Nie udało się odczytać kopii.'); } event.target.value = ''; });
$('#refresh').addEventListener('click', async () => {
  const button = $('#refresh'); button.disabled = true; button.querySelector('span').textContent = 'Szukam wydarzeń…';
  try { const response = await fetch('./api/refresh', { method: 'POST', signal: AbortSignal.timeout(90000), headers: { 'Content-Type': 'application/json' }, body: '{}' }); if (!response.ok) throw new Error(response.status === 404 ? 'Ten hosting nie ma kolektora. Uruchom node scripts/collect.mjs lub importuj wydarzenie ręcznie.' : 'Źródła są teraz niedostępne. Spróbuj później.'); const value = await response.json(); if (!value.events?.length && snapshot.events.length) { snapshot.sources = Array.isArray(value.sources) ? value.sources : snapshot.sources; renderSources(); toast('Brak nowych danych. Zachowano poprzedni odczyt; raport źródeł jest poniżej.'); return; } acceptSnapshot(value); cacheSnapshot(snapshot); toast('Odczytano źródła. Sprawdź raport dostępności poniżej.'); } catch (error) { toast(error.name === 'TimeoutError' ? 'Odczyt trwa zbyt długo. Zachowano poprzednie dane.' : error.message); } finally { button.disabled = false; button.querySelector('span').textContent = 'Odśwież źródła'; }
});

const importDialog = $('#import-dialog');
$('#import-url').addEventListener('input', () => { fetchedDraft = null; });
$('#import-open').addEventListener('click', () => { fetchedDraft = null; $('#import-form').reset(); $('#import-feedback').textContent = ''; importDialog.showModal(); });
$('#import-close').addEventListener('click', () => importDialog.close());
$('#import-fetch').addEventListener('click', async () => { fetchedDraft = null; const url = httpUrl($('#import-url').value); if (!url) { $('#import-feedback').textContent = 'Wpisz poprawny link HTTPS.'; return; } const button = $('#import-fetch'); button.disabled = true; $('#import-feedback').textContent = 'Odczytuję źródło…'; try {
  const response = await fetch('./api/import', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url }), signal: AbortSignal.timeout(25000) });
  const value = await response.json().catch(() => ({})); if (!response.ok) throw new Error(value.error || 'Nie można odczytać strony. Wpisz potwierdzone dane ręcznie.'); const event = normalizeEvent(value.events?.[0]); if (!event) throw new Error('Strona nie udostępnia pełnej daty i nazwy wydarzenia. Uzupełnij ręcznie.'); fetchedDraft = event;
  $('#import-title').value = event.title; $('#import-place').value = event.address || event.venue; $('#import-organizer').value = event.organizer; $('#import-category').value = event.categories[0] || 'ai'; $('#import-price').value = event.price.kind;
  const local = iso => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Warsaw', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(iso)).replace(' ', 'T'); $('#import-date').value = local(event.startAt); $('#import-end').value = event.endAt ? local(event.endAt) : ''; $('#import-feedback').textContent = value.warning || 'Dane odczytane. Sprawdź pola i zapisz.';
  } catch (error) { $('#import-feedback').textContent = error.message; } finally { button.disabled = false; }
});
$('#import-form').addEventListener('submit', event => { event.preventDefault(); const startAt = warsawDateTime($('#import-date').value), endAt = $('#import-end').value ? warsawDateTime($('#import-end').value) : null;
  if (!startAt || ($('#import-end').value && !endAt)) { $('#import-feedback').textContent = 'Nieprawidłowa godzina w Warszawie (możliwa zmiana czasu).'; return; }
  if (endAt && endAt <= startAt) { $('#import-feedback').textContent = 'Koniec musi przypadać po rozpoczęciu.'; return; }
  const url = httpUrl($('#import-url').value); if (!url) return;
  const draft = { ...(fetchedDraft || {}), id: fetchedDraft?.id || url, url, title: $('#import-title').value, startAt, endAt, city: fetchedDraft?.city || 'Warszawa', mode: fetchedDraft?.mode || 'in-person', venue: $('#import-place').value, address: $('#import-place').value, organizer: $('#import-organizer').value, categories: [$('#import-category').value], price: { kind: $('#import-price').value, amount: null, currency: null }, status: fetchedDraft?.status || 'unknown', verifiedAt: null, sources: [{ url, fetchedAt: null }] };
  state.customEvents = mergeEvents(state.customEvents.filter(e => e.url !== url), [draft]); persist(); render(); importDialog.close(); toast('Zapisano. Dane ręczne potwierdź u organizatora.');
});

if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1')) navigator.serviceWorker.register('./sw.js').catch(() => {});
render(); initialLoad();
