// Deterministic geometric app icons, encoded with Node's standard library.
import { deflateSync } from 'node:zlib';
import { mkdir, writeFile } from 'node:fs/promises';
const root = new URL('../', import.meta.url);
function crc32(bytes) { let crc = 0xffffffff; for (const byte of bytes) { crc ^= byte; for (let n = 0; n < 8; n++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1)); } return (crc ^ 0xffffffff) >>> 0; }
function chunk(name, bytes) { const type = Buffer.from(name), size = Buffer.alloc(4), crc = Buffer.alloc(4); size.writeUInt32BE(bytes.length); crc.writeUInt32BE(crc32(Buffer.concat([type, bytes]))); return Buffer.concat([size, type, bytes, crc]); }
function line(x, y, x1, y1, x2, y2, width) { const t = Math.max(0, Math.min(1, ((x - x1) * (x2 - x1) + (y - y1) * (y2 - y1)) / ((x2 - x1) ** 2 + (y2 - y1) ** 2))); return Math.hypot(x - x1 - t * (x2 - x1), y - y1 - t * (y2 - y1)) <= width / 2; }
function color(kind, x, y) {
  if (kind === 'radar') {
    const background = [25, 41, 34], foreground = [214, 243, 141], r = Math.hypot(x - 96, y - 96), dot = Math.hypot(x - 125, y - 67);
    if (dot <= 8) return foreground;
    if (dot <= 12) return background;
    return Math.abs(r - 58) <= 1.5 || Math.abs(r - 32) <= 1.5 || line(x, y, 96, 38, 96, 154, 3) || line(x, y, 38, 96, 154, 96, 3) || line(x, y, 96, 96, 136, 56, 3) ? foreground : background;
  }
  const background = [18, 37, 30], foreground = [216, 242, 155];
  if (x >= 82 && x <= 121 && y >= 72 + (x - 82) * 24 / 39 && y <= 120 - (x - 82) * 24 / 39) return background;
  return Math.hypot(Math.max(Math.abs(x - 96) - 38, 0), Math.max(Math.abs(y - 96) - 23, 0)) <= 16 ? foreground : background;
}
function png(kind, size) {
  const raw = Buffer.alloc(size * (1 + size * 3));
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const rgb = [0, 0, 0];
    for (const dy of [0.25, 0.75]) for (const dx of [0.25, 0.75]) { const sample = color(kind, (x + dx) * 192 / size, (y + dy) * 192 / size); for (let c = 0; c < 3; c++) rgb[c] += sample[c] / 4; }
    for (let c = 0; c < 3; c++) raw[y * (1 + size * 3) + 1 + x * 3 + c] = Math.round(rgb[c]);
  }
  const header = Buffer.alloc(13); header.writeUInt32BE(size); header.writeUInt32BE(size, 4); header[8] = 8; header[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
for (const [app, kind] of [['focus-tube', 'focus'], ['warsaw-tech-radar', 'radar']]) {
  const folder = new URL(`apps/${app}/ios/`, root); await mkdir(folder, { recursive: true });
  await writeFile(new URL('AppIcon.png', folder), png(kind, 1024));
  if (kind === 'focus') for (const size of [128, 512]) await writeFile(new URL(`icon-${size}.png`, folder), png(kind, size));
}
console.log('Created opaque iOS icons and Safari extension icons.');
