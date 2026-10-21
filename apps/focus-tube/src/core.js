export const VERSION = "0.1.1";
export const PAGE_SIZE = 15;
export const YOUTUBE_HOSTS = new Set(["youtube.com", "www.youtube.com", "m.youtube.com"]);

export function parseUrl(value, base = "https://m.youtube.com/") {
  try { return new URL(value, base); } catch { return null; }
}

export function decodedPath(url) {
  try { return decodeURIComponent(url.pathname).replace(/\/{2,}/g, "/"); }
  catch { return url.pathname; }
}

export function isYouTubeUrl(value, base) {
  const url = parseUrl(value, base);
  return !!url && url.protocol === "https:" && YOUTUBE_HOSTS.has(url.hostname);
}

export function isShortsUrl(value, base) {
  const url = parseUrl(value, base);
  return !!url && YOUTUBE_HOSTS.has(url.hostname) && /(^|\/)shorts(?:\/|$)/i.test(decodedPath(url));
}

export function classifyRoute(value) {
  const url = parseUrl(value);
  if (!url || !YOUTUBE_HOSTS.has(url.hostname)) return "external";
  const path = decodedPath(url).replace(/\/$/, "") || "/";
  if (isShortsUrl(url.href)) return "blocked";
  if (path === "/" || /^\/(feed\/(trending|explore)|gaming|hashtag)(\/|$)/.test(path)) return "home";
  if (path === "/watch") return "watch";
  if (path === "/results") return "list";
  if (path === "/feed/you") return "account";
  if (/^\/(playlist|feed\/(subscriptions|library|history|playlists))$/.test(path)) return "list";
  if (/^\/(@[^/]+|channel\/[^/]+|c\/[^/]+|user\/[^/]+)(\/(videos|streams|playlists|featured|search))?$/.test(path)) return "list";
  if (/^\/(signin|logout|channel_switcher|select_site|account(?:\/.*)?|account_.*|oops|error|t\/.*)$/.test(path)) return "utility";
  return "unsupported";
}

export function videoId(value, base) {
  const url = parseUrl(value, base);
  return url?.pathname === "/watch" ? url.searchParams.get("v") : null;
}

export function sameVideo(first, second) {
  const id = videoId(first);
  return !!id && id === videoId(second);
}

// Preserve deliberate playlist playback, but do not let an ordinary film become
// an unrequested next video. This is a UI guard, not a system security boundary.
export function navigationDecision(previous, target, userInitiated = false) {
  if (isShortsUrl(target)) return "shorts";
  if (classifyRoute(target) === "unsupported") return "unsupported";
  if (classifyRoute(previous) !== "watch" || classifyRoute(target) !== "watch") return "allow";
  if (sameVideo(previous, target) || userInitiated) return "allow";
  const from = parseUrl(previous);
  const to = parseUrl(target);
  const list = from.searchParams.get("list");
  return list && list === to.searchParams.get("list") ? "allow" : "autoplay";
}

export function resolveInput(raw, origin = "https://m.youtube.com") {
  const value = raw.trim();
  if (!value) return { type: "empty" };
  const looksLikeLink = /^(https?:\/\/|(?:www\.|m\.)?youtube\.com\/|youtu\.be\/)/i.test(value);
  if (looksLikeLink) {
    const url = parseUrl(/^https?:/i.test(value) ? value : `https://${value}`);
    if (!url || !["https:", "http:"].includes(url.protocol)) return { type: "invalid" };
    if (isShortsUrl(url.href)) return { type: "shorts" };
    const id = url.hostname === "youtu.be" ? url.pathname.slice(1) : (YOUTUBE_HOSTS.has(url.hostname) ? videoId(url.href) : null);
    if (!id || !/^[a-zA-Z0-9_-]{11}$/.test(id)) return { type: "invalid" };
    const target = new URL("/watch", origin);
    target.searchParams.set("v", id);
    for (const key of ["t", "list", "index", "start"]) {
      const item = url.searchParams.get(key);
      if (item && /^[a-zA-Z0-9_-]+$/.test(item)) target.searchParams.set(key, item);
    }
    return { type: "watch", url: target.href };
  }
  const target = new URL("/results", origin);
  target.searchParams.set("search_query", value);
  return { type: "search", url: target.href };
}
