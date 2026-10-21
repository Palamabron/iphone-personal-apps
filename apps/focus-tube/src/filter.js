import { VERSION, PAGE_SIZE, classifyRoute, isShortsUrl, navigationDecision, parseUrl, resolveInput, sameVideo, videoId } from "./core.js";

const CARD_SELECTOR = [
  "ytd-video-renderer", "ytd-grid-video-renderer", "ytd-rich-item-renderer",
  "ytd-playlist-video-renderer", "ytd-playlist-renderer", "ytd-channel-renderer",
  "ytm-video-with-context-renderer", "ytm-video-renderer", "ytm-compact-video-renderer",
  "ytm-playlist-video-renderer", "ytm-playlist-renderer", "ytm-channel-renderer", "ytm-rich-item-renderer"
].join(",");
const SHORTS_SELECTOR = [
  "ytd-reel-shelf-renderer", "ytd-reel-item-renderer", "ytd-shorts", "ytm-shorts",
  "ytm-reel-shelf-renderer", "ytm-reel-item-renderer", "ytm-shorts-lockup-view-model",
  "ytm-shorts-lockup-view-model-v2", "yt-shorts-lockup-view-model", "ytd-shorts-lockup-view-model",
  'ytm-pivot-bar-item-renderer[pivot-identifier="shorts"]',
  'ytm-pivot-bar-item-renderer[tab-identifier="FEshorts"]'
].join(",");
const CONTINUATION_SELECTOR = "ytd-continuation-item-renderer,ytm-continuation-item-renderer,ytm-continuation-renderer";
const LIST_ROOT_SELECTOR = "ytd-search,ytd-browse,ytm-search,ytm-browse,ytm-section-list-renderer";
const RECOMMENDATION_SELECTOR = [
  "ytd-watch-next-secondary-results-renderer", "ytm-watch-next-secondary-results-renderer",
  'ytm-item-section-renderer[section-identifier="related-items"]',
  'ytm-item-section-renderer[section-identifier="watch-next-feed"]',
  "ytd-compact-autoplay-renderer", "ytm-autonav-bar", "ytm-autonav-toggle-renderer"
].join(",");

export const FILTER_CSS = `
html[data-ft-active] [data-ft-hidden],html[data-ft-active] [data-ft-page-hidden],
html[data-ft-active] ${SHORTS_SELECTOR.split(",").join(",html[data-ft-active] ")},
html[data-ft-active] a[href^="/shorts/"],html[data-ft-active] a[href*="youtube.com/shorts/"]{display:none!important}
html[data-ft-active] ${CONTINUATION_SELECTOR.split(",").join(",html[data-ft-active] ")}{display:none!important}
html[data-ft-load="open"] ${CONTINUATION_SELECTOR.split(",").join(',html[data-ft-load="open"] ')}{display:block!important}
html[data-ft-route="home"] body>:not(#ft-root),html[data-ft-route="blocked"] body>:not(#ft-root),
html[data-ft-route="unsupported"] body>:not(#ft-root){display:none!important}
html[data-ft-route="list"][data-ft-list="pending"] ${LIST_ROOT_SELECTOR.split(",").join(',html[data-ft-route="list"][data-ft-list="pending"] ')}{visibility:hidden!important}
html[data-ft-route="list"] ${CARD_SELECTOR.split(",").map((selector) => `${selector}:not([data-ft-checked])`).join(',html[data-ft-route="list"] ')}{display:none!important}
html[data-ft-route="watch"] ${RECOMMENDATION_SELECTOR.split(",").join(',html[data-ft-route="watch"] ')},
html[data-ft-route="watch"] #related,html[data-ft-route="watch"] .ytp-endscreen-content,
html[data-ft-route="watch"] .ytp-ce-element,html[data-ft-route="watch"] .ytp-autonav-endscreen,
html[data-ft-route="watch"][data-ft-playlist="false"] .ytp-next-button{display:none!important}
html[data-ft-route="list"] body{padding-bottom:132px!important}
html[data-ft-route="account"] ${CARD_SELECTOR.split(",").join(',html[data-ft-route="account"] ')}{display:none!important}
#ft-root{font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#edf1e9;color-scheme:dark;z-index:2147483646;box-sizing:border-box}
#ft-root *{box-sizing:border-box}#ft-root a{color:inherit;text-decoration:none}#ft-root button,#ft-root input{font:inherit}
#ft-root.ft-home{position:fixed;inset:0;overflow:auto;display:grid;align-items:center;padding:32px 24px calc(32px + env(safe-area-inset-bottom));background:#12251e}
#ft-root .ft-home-inner{width:min(100%,620px);margin:auto}#ft-root .ft-wordmark{font-weight:700;letter-spacing:-.05em;font-size:24px;display:flex;align-items:center;gap:9px}
#ft-root .ft-mark{display:inline-grid;place-items:center;background:#d8f29b;color:#163225;border-radius:11px;width:34px;height:34px;font-size:17px}
#ft-root .ft-eyebrow{font-size:11px;letter-spacing:.16em;color:#b4c6af;text-transform:uppercase;margin-top:65px}
#ft-root h1{font-size:clamp(35px,8vw,58px);line-height:1.08;letter-spacing:-.045em;font-weight:600;margin:15px 0 20px}
#ft-root .ft-intro{color:#bac9bc;max-width:440px}#ft-root form{margin:32px 0 12px}
#ft-root label{display:block;font-size:13px;margin-bottom:8px;color:#c9d5c6}
#ft-root .ft-search-row{display:flex;gap:8px}#ft-root input{min-width:0;flex:1;border:1px solid #60705d;background:#20392e;color:#fff;border-radius:14px;padding:15px 14px;font-size:16px}
#ft-root button,#ft-root .ft-button{border:0;border-radius:14px;padding:14px 18px;background:#d8f29b;color:#163225;cursor:pointer;min-height:48px;font-weight:650}
#ft-root button:focus-visible,#ft-root input:focus-visible,#ft-root a:focus-visible{outline:3px solid #f0d79d;outline-offset:3px}
#ft-root .ft-error{color:#ffd6ae;min-height:24px;font-size:13px}#ft-root nav{display:flex;flex-wrap:wrap;gap:9px;margin-top:20px}
#ft-root nav a{border:1px solid #4a6150;border-radius:999px;padding:10px 15px;font-size:13px;min-height:44px;display:inline-flex;align-items:center}
#ft-root .ft-note{font-size:12px;color:#9db59e;margin-top:40px;max-width:430px}#ft-root .ft-blocked{padding:14px 16px;border:1px solid #67824d;background:#263b29;border-radius:14px;margin-top:20px;font-size:14px}
#ft-root.ft-footer{position:fixed;bottom:0;left:0;right:0;padding:12px 16px calc(12px + env(safe-area-inset-bottom));background:#12251ef5;border-top:1px solid #496047;display:flex;gap:12px;align-items:center;justify-content:space-between}
#ft-root.ft-footer .ft-summary{min-width:0;font-size:12px;color:#bac9bc;max-width:62%}#ft-root.ft-footer .ft-summary strong{display:block;font-size:13px;color:#edf1e9}
#ft-root.ft-footer button{white-space:nowrap;font-size:13px;padding:12px 14px}#ft-root.ft-footer a{text-decoration:underline;text-underline-offset:3px}
#ft-root .ft-links{display:flex;gap:10px;flex-wrap:wrap;margin-top:4px}
#ft-root.ft-badge{position:fixed;bottom:calc(12px + env(safe-area-inset-bottom));left:12px;background:#12251eea;border:1px solid #53704f;border-radius:999px;padding:6px 12px;font-size:11px;color:#d8f29b}
html:has(video:fullscreen) #ft-root,html:fullscreen #ft-root{display:none!important}
@media(max-width:800px){#ft-root.ft-footer{bottom:calc(56px + env(safe-area-inset-bottom))}html[data-ft-route="list"] body{padding-bottom:220px!important}}
@media(prefers-reduced-motion:reduce){#ft-root *{scroll-behavior:auto!important}}
`;

export function installFocusTube(win, options = {}) {
  const doc = win.document;
  if (!doc.documentElement || doc.documentElement.hasAttribute("data-ft-active")) return null;
  const root = doc.documentElement;
  root.setAttribute("data-ft-active", VERSION);
  const style = doc.createElement("style");
  style.id = "ft-style";
  style.textContent = FILTER_CSS;
  (doc.head || root).append(style);

  let previousUrl = win.location.href;
  let route = classifyRoute(previousUrl);
  let currentKey = "";
  let limit = PAGE_SIZE;
  let approved = null;
  let scheduled = false;
  let shell = null;
  let waiting = false;
  let loadingFromCount = 0;
  let loadingTimer = null;
  let feedback = "";
  let routeStarted = Date.now();
  let destroyed = false;
  const knownShortIds = new Set();
  const autoplayClicks = new WeakMap();
  const navigate = options.navigate || ((url) => win.location.assign(url));
  const replaceLocation = options.replaceLocation || ((url) => win.location.replace(url));
  const homeUrl = (reason = "") => `${win.location.origin}/${reason ? `?focus_tube=${encodeURIComponent(reason)}` : ""}`;
  const originalPush = win.history.pushState;
  const originalReplace = win.history.replaceState;

  // YouTube enables Trusted Types. Build UI with DOM methods instead of
  // assigning HTML strings or creating a permissive Trusted Types policy.
  function element(tag, attributes = {}, ...children) {
    const result = doc.createElement(tag);
    for (const [name, value] of Object.entries(attributes)) {
      if (name === "className") result.className = value;
      else if (name === "hidden") result.hidden = value;
      else result.setAttribute(name, String(value));
    }
    for (const child of children) result.append(typeof child === "string" ? doc.createTextNode(child) : child);
    return result;
  }

  function pauseVideos() {
    doc.querySelectorAll("video").forEach((video) => { try { video.pause(); } catch { /* A removed player can throw. */ } });
  }

  function allowedByIntent(url) {
    if (!approved || Date.now() - approved.time > 5000) return false;
    return sameVideo(approved.url, url) || approved.url === url;
  }

  function stopLoading() {
    waiting = false;
    root.removeAttribute("data-ft-load");
    if (loadingTimer) win.clearTimeout(loadingTimer);
    loadingTimer = null;
  }

  function resetForUrl(url) {
    const parsed = parseUrl(url);
    const key = `${parsed.pathname}${parsed.search}`;
    if (key !== currentKey) {
      currentKey = key;
      limit = PAGE_SIZE;
      routeStarted = Date.now();
      feedback = "";
      stopLoading();
      doc.querySelectorAll("[data-ft-page-hidden]").forEach((el) => el.removeAttribute("data-ft-page-hidden"));
      root.setAttribute("data-ft-list", "pending");
    }
    route = classifyRoute(url);
    root.setAttribute("data-ft-route", route);
    root.setAttribute("data-ft-playlist", String(!!parsed.searchParams.get("list")));
  }

  function checkNavigation(target, intent = false) {
    const decision = navigationDecision(previousUrl, target, intent || allowedByIntent(target));
    if (decision === "shorts" || decision === "autoplay") {
      pauseVideos();
      return homeUrl(decision);
    }
    return target;
  }

  function interceptHistory(original) {
    return function (state, unused, url) {
      if (url == null) return original.call(this, state, unused, url);
      const target = parseUrl(url, win.location.href);
      if (!target || target.origin !== win.location.origin) return original.call(this, state, unused, url);
      const filtered = checkNavigation(target.href);
      if (filtered !== target.href) {
        root.setAttribute("data-ft-route", "blocked");
        replaceLocation(filtered);
        return;
      }
      const result = original.call(this, state, unused, url);
      previousUrl = win.location.href;
      resetForUrl(previousUrl);
      schedule();
      return result;
    };
  }

  const pushHook = interceptHistory(originalPush);
  const replaceHook = interceptHistory(originalReplace);
  win.history.pushState = pushHook;
  win.history.replaceState = replaceHook;

  function markHidden(el) {
    if (!el.hasAttribute("data-ft-hidden")) el.setAttribute("data-ft-hidden", "");
  }

  function filterShorts() {
    // YouTube can recycle a card node for a different result during SPA updates.
    doc.querySelectorAll("[data-ft-hidden]").forEach((el) => el.removeAttribute("data-ft-hidden"));
    doc.querySelectorAll(SHORTS_SELECTOR).forEach(markHidden);
    doc.querySelectorAll("a[href]").forEach((anchor) => {
      const href = anchor.getAttribute("href");
      if (isShortsUrl(href, win.location.href)) {
        const shortUrl = parseUrl(href, win.location.href);
        const match = shortUrl.pathname.match(/\/shorts\/([^/?]+)/i);
        if (match) knownShortIds.add(match[1]);
        markHidden(anchor.closest(`${CARD_SELECTOR},ytd-guide-entry-renderer,ytd-mini-guide-entry-renderer,ytm-pivot-bar-item-renderer,ytm-pivot-bar-item-view-model,yt-tab-shape`) || anchor);
      } else if (knownShortIds.has(videoId(href, win.location.href))) {
        markHidden(anchor.closest(CARD_SELECTOR) || anchor);
      }
    });
  }

  function getCards() {
    return [...doc.querySelectorAll(CARD_SELECTOR)].filter((el) => !el.parentElement?.closest(CARD_SELECTOR)
      && !el.closest('[data-ft-hidden],[hidden],[aria-hidden="true"]') && !el.closest(RECOMMENDATION_SELECTOR));
  }

  function applyPagination() {
    const cards = getCards();
    if (waiting && cards.length > loadingFromCount) stopLoading();
    for (let index = 0; index < cards.length; index++) {
      if (!cards[index].hasAttribute("data-ft-checked")) cards[index].setAttribute("data-ft-checked", "");
      cards[index].querySelectorAll(CARD_SELECTOR).forEach((child) => { if (!child.hasAttribute("data-ft-checked")) child.setAttribute("data-ft-checked", ""); });
      if (index >= limit) {
        if (!cards[index].hasAttribute("data-ft-page-hidden")) cards[index].setAttribute("data-ft-page-hidden", "");
      } else if (cards[index].hasAttribute("data-ft-page-hidden")) cards[index].removeAttribute("data-ft-page-hidden");
    }
    // Fail closed on an unrecognised layout. Only reveal supported cards after
    // they have been filtered and capped. Login/account pages are separate.
    root.setAttribute("data-ft-list", cards.length ? "ready" : "pending");
    return cards;
  }

  function disableAutoplay() {
    const selectors = [
      '.ytp-autonav-toggle-button[aria-checked="true"]',
      'ytm-autonav-toggle-renderer [aria-checked="true"]',
      'ytm-autonav-toggle-renderer [aria-pressed="true"]',
      'ytm-autonav-toggle-renderer input:checked',
      'ytm-autonav-toggle-button-renderer [aria-checked="true"]'
    ].join(",");
    doc.querySelectorAll(selectors).forEach((toggle) => {
      if (Date.now() - (autoplayClicks.get(toggle) || 0) < 1500) return;
      autoplayClicks.set(toggle, Date.now());
      toggle.click();
    });
  }

  function createShell(className) {
    if (!doc.body) return null;
    if (!shell?.isConnected) {
      shell = doc.createElement("section");
      shell.id = "ft-root";
      doc.body.append(shell);
    }
    if (shell.className !== className) {
      shell.className = className;
      shell.replaceChildren();
      delete shell.dataset.view;
    }
    return shell;
  }

  function showHome() {
    const target = createShell("ft-home");
    if (!target) return;
    const reason = parseUrl(win.location.href).searchParams.get("focus_tube");
    const viewKey = `${route}:${reason}`;
    if (target.dataset.view === viewKey) return;
    target.dataset.view = viewKey;
    target.replaceChildren(element("div", { className: "ft-home-inner" },
      element("div", { className: "ft-wordmark" }, element("span", { className: "ft-mark", "aria-hidden": "true" }, "▶"), "focus tube", element("span", { style: "font-size:11px;letter-spacing:0;margin-left:auto;color:#b4c6af" }, "FILTR AKTYWNY")),
      element("p", { className: "ft-eyebrow" }, "Mniej impulsu. Więcej wyboru."),
      element("h1", {}, "Co chcesz", element("br"), "dzisiaj obejrzeć?"),
      element("p", { className: "ft-intro" }, "Jeden dobry film wystarczy. Wyszukaj temat lub wklej link, a resztę zostaw za sobą."),
      element("div", { className: "ft-blocked", "data-ft-reason": "", hidden: true }),
      element("form", {}, element("label", { for: "ft-query" }, "Temat lub link do filmu"),
        element("div", { className: "ft-search-row" }, element("input", { id: "ft-query", name: "q", type: "search", autocomplete: "off", placeholder: "Czego chcesz się dowiedzieć?", required: "" }), element("button", { type: "submit", "aria-label": "Wyszukaj lub otwórz film" }, "Szukaj")),
        element("p", { className: "ft-error", role: "status", "aria-live": "polite" })),
      element("nav", { "aria-label": "Twoje miejsca w YouTube" },
        element("a", { href: "/feed/subscriptions" }, "Subskrypcje ↗"), element("a", { href: "/playlist?list=WL" }, "Do obejrzenia ↗"), element("a", { href: "/feed/library" }, "Twoja biblioteka ↗"), element("a", { href: "/channel_switcher" }, "Zmień konto ↗")),
      element("p", { className: "ft-note" }, "Bez Shortsów i polecanego feedu. Odtwarzacz i konto pozostają w YouTube. Filtr działa w tej karcie Safari.")
    ));
    const messages = {
      shorts: "Ten link prowadzi do Shortsów. Wybierz temat lub pełny film.",
      autoplay: "Film skończony. Kolejny wybór należy do Ciebie."
    };
    const message = route === "blocked" ? messages.shorts : (route === "unsupported" ? "Ten widok nie jest obsługiwany przez filtr. Wybierz film przez wyszukiwarkę." : messages[reason]);
    if (message) {
      const notice = target.querySelector("[data-ft-reason]");
      notice.hidden = false;
      notice.textContent = message;
    }
    target.querySelector("form").addEventListener("submit", (event) => {
      event.preventDefault();
      const result = resolveInput(target.querySelector("input").value, win.location.origin);
      const error = target.querySelector(".ft-error");
      if (result.type === "shorts") { error.textContent = messages.shorts; return; }
      if (result.type === "invalid") { error.textContent = "Wklej link do zwykłego filmu YouTube lub wpisz temat."; return; }
      if (result.url) { approved = { url: result.url, time: Date.now() }; navigate(result.url); }
    });
  }

  function showMore() {
    const cards = getCards();
    if (waiting) return;
    if (cards.length > limit) {
      limit += PAGE_SIZE;
      feedback = "";
      schedule();
      return;
    }
    const continuation = [...doc.querySelectorAll(CONTINUATION_SELECTOR)].find((el) => !el.closest("[data-ft-hidden]"));
    if (!continuation) { feedback = "To wszystkie dostępne pozycje na tej stronie."; schedule(); return; }
    limit += PAGE_SIZE;
    loadingFromCount = cards.length;
    waiting = true;
    root.setAttribute("data-ft-load", "open");
    const button = continuation.querySelector("button,[role='button'],ytm-button-renderer");
    if (button) button.click();
    else continuation.scrollIntoView({ block: "end", behavior: "instant" });
    loadingTimer = win.setTimeout(() => { stopLoading(); feedback = "YouTube nie dodał pozycji. Spróbuj ponownie lub zmień wyszukiwanie."; schedule(); }, 5000);
    schedule();
  }

  function showList(cards) {
    const target = createShell("ft-footer");
    if (!target) return;
    if (!target.firstElementChild) {
      target.replaceChildren(element("div", { className: "ft-summary" }, element("strong", {}, "Focus Tube · filtr aktywny"), element("span", { "aria-live": "polite" }), element("div", { className: "ft-links" }, element("a", { href: "/" }, "Szukaj"), element("a", { href: "/channel_switcher" }, "Zmień konto"))), element("button", { type: "button" }, "Pokaż kolejne 15"));
      target.querySelector("button").addEventListener("click", showMore);
    }
    let message = feedback || `${Math.min(cards.length, limit)} widocznych. Kolejne wybierasz sam.`;
    if (!cards.length) message = Date.now() - routeStarted < 5000
      ? "Czekam na wyniki YouTube…"
      : "Brak rozpoznanych wyników. Brak treści, logowanie lub zmiana YouTube — spróbuj wyszukać film.";
    if (waiting) message = "Pobieram wybraną porcję…";
    const label = target.querySelector(".ft-summary span");
    if (label.textContent !== message) label.textContent = message;
    const button = target.querySelector("button");
    button.disabled = waiting;
    const buttonText = waiting ? "Ładowanie…" : "Pokaż kolejne 15";
    if (button.textContent !== buttonText) button.textContent = buttonText;
  }

  function showBadge() {
    const target = createShell("ft-badge");
    if (target && !target.firstElementChild) target.append(element("a", { href: "/", "aria-label": "Focus Tube: wróć do wyszukiwarki" }, "↖ Focus Tube · filtr aktywny"));
  }

  function sweep() {
    scheduled = false;
    if (destroyed) return;
    if (win.location.href !== previousUrl) {
      const safe = checkNavigation(win.location.href);
      if (safe !== win.location.href) { root.setAttribute("data-ft-route", "blocked"); replaceLocation(safe); return; }
      previousUrl = win.location.href;
    }
    resetForUrl(win.location.href);
    filterShorts();
    if (route === "blocked") {
      pauseVideos();
      showHome();
    } else if (route === "home" || route === "unsupported") showHome();
    else if (route === "list") showList(applyPagination());
    else if (route === "watch") { disableAutoplay(); showBadge(); }
    else shell?.remove();
  }

  function schedule() {
    if (scheduled || destroyed) return;
    scheduled = true;
    win.setTimeout(sweep, 30);
  }

  function onClick(event) {
    const anchor = event.target?.closest?.("a[href]");
    if (!anchor) return;
    const url = parseUrl(anchor.getAttribute("href"), win.location.href);
    if (!url) return;
    if (isShortsUrl(url.href)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      navigate(homeUrl("shorts"));
      return;
    }
    if (url.hostname === "youtu.be") {
      const result = resolveInput(url.href, win.location.origin);
      if (result.url) { event.preventDefault(); event.stopImmediatePropagation(); approved = { url: result.url, time: Date.now() }; navigate(result.url); }
    } else approved = { url: url.href, time: Date.now() };
  }

  function onEnded(event) {
    if (event.target?.tagName !== "VIDEO" || classifyRoute(win.location.href) !== "watch"
      || parseUrl(win.location.href).searchParams.has("list")) return;
    event.stopImmediatePropagation();
    pauseVideos();
    replaceLocation(homeUrl("autoplay"));
  }

  const observer = new win.MutationObserver((records) => {
    if (records.some((record) => !record.target?.closest?.("#ft-root")
      && !(record.type === "attributes" && record.attributeName?.startsWith("data-ft-")))) schedule();
  });
  observer.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ["href", "aria-checked", "aria-pressed"] });
  const onPopState = () => { approved = { url: win.location.href, time: Date.now() }; schedule(); };
  doc.addEventListener("click", onClick, true);
  doc.addEventListener("ended", onEnded, true);
  doc.addEventListener("yt-navigate-finish", schedule);
  doc.addEventListener("yt-page-data-updated", schedule);
  doc.addEventListener("DOMContentLoaded", schedule);
  win.addEventListener("popstate", onPopState);
  const poll = win.setInterval(() => { if (!doc.hidden) sweep(); }, 800);
  resetForUrl(previousUrl);
  sweep();
  if (route === "blocked") replaceLocation(homeUrl("shorts"));

  return {
    sweep, showMore,
    destroy() {
      destroyed = true;
      observer.disconnect();
      win.clearInterval(poll);
      stopLoading();
      if (win.history.pushState === pushHook) win.history.pushState = originalPush;
      if (win.history.replaceState === replaceHook) win.history.replaceState = originalReplace;
      doc.removeEventListener("click", onClick, true);
      doc.removeEventListener("ended", onEnded, true);
      doc.removeEventListener("yt-navigate-finish", schedule);
      doc.removeEventListener("yt-page-data-updated", schedule);
      doc.removeEventListener("DOMContentLoaded", schedule);
      win.removeEventListener("popstate", onPopState);
      shell?.remove();
      style.remove();
      root.removeAttribute("data-ft-active");
      root.removeAttribute("data-ft-route");
      doc.querySelectorAll("[data-ft-hidden],[data-ft-page-hidden],[data-ft-checked]").forEach((el) => { el.removeAttribute("data-ft-hidden"); el.removeAttribute("data-ft-page-hidden"); el.removeAttribute("data-ft-checked"); });
    }
  };
}
