import test from "node:test";
import assert from "node:assert/strict";
import { classifyRoute, isShortsUrl, isYouTubeUrl, navigationDecision, resolveInput } from "../src/core.js";

test("YouTube host matching is exact and protocol is HTTPS", () => {
  assert.equal(isYouTubeUrl("https://m.youtube.com/watch?v=dQw4w9WgXcQ"), true);
  assert.equal(isYouTubeUrl("https://youtube.com.evil.invalid/shorts/abc"), false);
  assert.equal(isYouTubeUrl("http://youtube.com/"), false);
  assert.equal(isYouTubeUrl("javascript:alert(1)"), false);
});

test("Shorts detection handles direct, channel, encoded and relative paths", () => {
  for (const url of ["/shorts/abc", "/shorts", "/@channel/shorts", "/channel/id/shorts", "/%73horts/abc", "https://www.youtube.com/SHORTS/abc"]) assert.equal(isShortsUrl(url), true, url);
  for (const url of ["/results?search_query=shorts", "/watch?v=shorts", "https://example.com/shorts/abc", "/shortstory"]) assert.equal(isShortsUrl(url), false, url);
});

test("route classification includes mobile and desktop browsing surfaces", () => {
  for (const [path, expected] of [["/", "home"], ["/feed/trending", "home"], ["/shorts/a", "blocked"], ["/results?search_query=x", "list"], ["/feed/subscriptions", "list"], ["/playlist?list=WL", "list"], ["/@channel/videos", "list"], ["/channel/id/playlists", "list"], ["/watch?v=dQw4w9WgXcQ", "watch"], ["/signin", "utility"], ["/new-feed", "unsupported"]]) assert.equal(classifyRoute(`https://m.youtube.com${path}`), expected, path);
});

test("ordinary film cannot silently transition to a different video", () => {
  const from = "https://m.youtube.com/watch?v=aaaaaaaaaaa";
  const to = "https://m.youtube.com/watch?v=bbbbbbbbbbb";
  assert.equal(navigationDecision(from, to), "autoplay");
  assert.equal(navigationDecision(from, to, true), "allow");
  assert.equal(navigationDecision(from, from + "&t=50"), "allow");
  assert.equal(navigationDecision(from + "&list=PL123", to + "&list=PL123"), "allow");
  assert.equal(navigationDecision(from + "&list=PL123", to + "&list=OTHER"), "autoplay");
  assert.equal(navigationDecision(from, "https://m.youtube.com/shorts/abc", true), "shorts");
});

test("account chooser, native profile and account settings remain reachable", () => {
  for (const path of ["/channel_switcher", "/select_site", "/account", "/account/notifications", "/signin?next=%2Ffeed%2Fsubscriptions"]) {
    assert.equal(classifyRoute('https://m.youtube.com' + path), 'utility', path);
    assert.equal(navigationDecision('https://m.youtube.com/feed/subscriptions', 'https://m.youtube.com' + path, true), 'allow');
  }
  assert.equal(classifyRoute('https://m.youtube.com/feed/you'), 'account');
  assert.equal(classifyRoute('https://m.youtube.com/feed/library'), 'list');
});

test("search query is encoded and pasted normal links retain useful playback data only", () => {
  assert.equal(resolveInput("  sieci neuronowe & <test>  ").url, "https://m.youtube.com/results?search_query=sieci+neuronowe+%26+%3Ctest%3E");
  assert.deepEqual(resolveInput("https://youtu.be/dQw4w9WgXcQ?si=tracking&t=30"), { type: "watch", url: "https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=30" });
  assert.equal(resolveInput("youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&index=2").url, "https://m.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&index=2");
});

test("pasted Shorts and non-YouTube links are rejected without navigation", () => {
  assert.equal(resolveInput("https://www.youtube.com/shorts/dQw4w9WgXcQ").type, "shorts");
  assert.equal(resolveInput("https://youtube.com.evil.invalid/watch?v=dQw4w9WgXcQ").type, "invalid");
  assert.equal(resolveInput("https://example.com").type, "invalid");
  assert.equal(resolveInput("https://youtube.com/watch?v=invalid").type, "invalid");
  assert.equal(resolveInput("  ").type, "empty");
});
