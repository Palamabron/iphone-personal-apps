import { mkdir, readFile, writeFile, cp } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { VERSION } from "../src/core.js";

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dist = path.join(project, "dist");
await mkdir(dist, { recursive: true });
if (!process.argv.includes('--extension-only')) await cp(path.join(project, "site"), dist, { recursive: true });
const core = (await readFile(path.join(project, "src/core.js"), "utf8")).replace(/^export /gm, "");
const filter = (await readFile(path.join(project, "src/filter.js"), "utf8")).replace(/^import .*;\r?\n/gm, "").replace(/^export /gm, "");
const header = `// ==UserScript==
// @name         Focus Tube — YouTube without Shorts
// @namespace    focus-tube.local
// @version      ${VERSION}
// @description  Without Shorts, recommendations or endless scrolling. Uses the YouTube player.
// @match        https://youtube.com/*
// @match        https://www.youtube.com/*
// @match        https://m.youtube.com/*
// @run-at       document-start
// @inject-into  page
// @grant        none
// @noframes
// ==/UserScript==
`;
const boot = `function startFocusTube() { installFocusTube(window); }
if (document.documentElement) startFocusTube();
else { const ready = new MutationObserver(() => { if (document.documentElement) { ready.disconnect(); startFocusTube(); } }); ready.observe(document, { childList: true }); }`;
const bundle = `${header}\n(function () {\n"use strict";\nif (window.top !== window.self) return;\n${core}\n${filter}\n${boot}\n})();\n`;
await writeFile(path.join(dist, "focus-tube.user.js"), bundle);
await writeFile(path.join(dist, "version.json"), JSON.stringify({ version: VERSION, variant: "safari-userscript" }, null, 2) + "\n");
await mkdir(path.join(dist, "extension"), { recursive: true });
await writeFile(path.join(dist, "extension/content.js"), `(function () {\n"use strict";\n${core}\n${filter}\n${boot}\n})();\n`);
await writeFile(path.join(dist, "extension/manifest.json"), JSON.stringify({
  manifest_version: 3, name: "Focus Tube", version: VERSION,
  description: "YouTube without Shorts or the recommendation feed. Developer build for desktop testing.",
  content_scripts: [{ matches: ["https://youtube.com/*", "https://www.youtube.com/*", "https://m.youtube.com/*"], js: ["content.js"], run_at: "document_start", world: "MAIN" }]
}, null, 2));
await writeFile(path.join(dist, "extension/README.txt"), "For Chrome/Edge testing: Extensions → Developer mode → Load unpacked → select this folder. On iPhone use Userscripts and focus-tube.user.js; this folder cannot be installed directly on iOS.\n");
console.log(`Focus Tube ${VERSION}: dist/ ready, script ${Buffer.byteLength(bundle)} B.`);
