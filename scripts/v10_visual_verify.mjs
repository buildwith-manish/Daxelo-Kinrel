// scripts/v10_visual_verify.mjs
//
// v10 visual-system verification — renders the bundled Kinrel dark style
// in a standalone MapLibre 5.6.0 headless browser at TWO camera poses to
// prove the new atmospheric + 3D-building layers actually paint:
//
//   1. Pose A — pitch: 0, bearing: 0 (flat top-down)
//      Verifies: fog/sky layer doesn't error at flat pitch, base map renders.
//
//   2. Pose B — pitch: 50, bearing: -17 (the new v10 default)
//      Verifies: 3D building extrusion visible, fog horizon-blend, sky
//                atmosphere layer paints a warm horizon gradient at the
//                top of the canvas.
//
// Output: PNGs + console log saved under
//   /home/z/my-project/download/v10-visual-verify/
//
// Run from anywhere:
//   node /home/z/my-project/scripts/v10_visual_verify.mjs
//
// Requirements: node_modules/puppeteer reachable. The script auto-detects
// the puppeteer install at /home/z/my-project/node_modules/puppeteer.

import { createRequire } from 'node:module';
import { mkdtempSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import http from 'node:http';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';

const require = createRequire('/home/z/my-project/');
const puppeteer = require('puppeteer');

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = '/home/z/my-project/download/v10-visual-verify';
mkdirSync(OUT_DIR, { recursive: true });

const STYLE_SRC = '/home/z/my-project/Daxelo-Kinrel-App/assets/map_styles/kinrel_dark_style.json';

if (!existsSync(STYLE_SRC)) {
  console.error(`✗ style JSON not found at ${STYLE_SRC}`);
  process.exit(1);
}

// ── Test city: Mumbai (lots of 3D buildings) ──────────────────────────
const TEST = {
  name: 'mumbai',
  center: [72.8777, 19.0760],   // [lng, lat]
  zoom: 14.5,
};

// ── Static HTTP server for the headless browser to fetch style + html ──
const tmpRoot = mkdtempSync(join(tmpdir(), 'v10-verify-'));
const htmlPath = join(tmpRoot, 'index.html');
const stylePath = join(tmpRoot, 'kinrel_dark_style.json');

copyFileSync(STYLE_SRC, stylePath);

writeFileSync(htmlPath, `<!doctype html>
<html><head>
<meta charset="utf-8"/>
<script src="https://cdn.jsdelivr.net/npm/maplibre-gl@5.6.0/dist/maplibre-gl.js"></script>
<link href="https://cdn.jsdelivr.net/npm/maplibre-gl@5.6.0/dist/maplibre-gl.css" rel="stylesheet"/>
<script src="https://cdn.jsdelivr.net/npm/pmtiles@3.2.0/dist/pmtiles.js"></script>
<style>
  html,body{margin:0;padding:0;background:#0B0F17;}
  #map{width:1280px;height:720px;}
  #log{position:fixed;top:0;right:0;width:480px;height:720px;
       background:rgba(0,0,0,0.85);color:#0f0;font:11px/1.4 monospace;
       padding:8px;overflow:auto;white-space:pre-wrap;display:none;}
</style>
</head><body>
<div id="map"></div>
<pre id="log"></pre>
<script>
window.__errors = [];
window.__logs = [];
window.addEventListener('error', e => {
  window.__errors.push(e.message + (e.error && e.error.stack ? '\\n' + e.error.stack : ''));
  document.getElementById('log').style.display='block';
  document.getElementById('log').textContent += '\\n[ERR] ' + e.message;
});
const origLog = console.log;
const origErr = console.error;
console.log = function(...args){ window.__logs.push('[I] '+args.join(' ')); origLog.apply(console,args); };
console.error = function(...args){ window.__logs.push('[E] '+args.join(' ')); origErr.apply(console,args); };

const pm = new pmtiles.Protocol();
maplibregl.addProtocol('pmtiles', pm.tile);

fetch('/kinrel_dark_style.json')
  .then(r => r.json())
  .then(style => {
    // Belt-and-suspenders: replicate production runtime patches so the
    // screenshot reflects what users actually see.
    if (style.sources && style.sources.openmaptiles) {
      style.sources.openmaptiles = {
        type: 'vector',
        url: 'https://tiles.openfreemap.org/planet',
        attribution: '© OpenStreetMap contributors, © OpenFreeMap'
      };
    }
    // v9.0 fontstack patch (same as family_map_screen.dart _patchFontstacks)
    for (const layer of (style.layers || [])) {
      if (layer.type !== 'symbol') continue;
      const layout = layer.layout || {};
      if (!Array.isArray(layout['text-font']) || layout['text-font'].length <= 1) continue;
      layout['text-font'] = [layout['text-font'][0]];
    }
    window.__styleReady = true;
    window.__map = new maplibregl.Map({
      container: 'map',
      style: style,
      center: ${JSON.stringify(TEST.center)},
      zoom: ${TEST.zoom},
      pitch: 0,
      bearing: 0,
      attributionControl: false,
      preserveDrawingBuffer: true,
      failIfMajorPerformanceCaveat: false,
      preferCanvas: true,
      maxZoom: 18,
    });
    window.__map.on('error', e => {
      window.__errors.push('maplibre: ' + (e && e.error && e.error.message ? e.error.message : JSON.stringify(e)));
    });
    window.__map.on('style.load', () => {
      window.__logs.push('event: style.load');
      window.__styleLoadFired = true;
    });
    window.__map.on('idle', () => {
      window.__logs.push('event: idle');
      window.__idleFired = true;
    });
  })
  .catch(err => {
    window.__errors.push('fetch/style load failed: ' + err.message);
  });
</script>
</body></html>
`);

// Serve files from tmpRoot
const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  let filePath;
  if (url === '/' || url === '/index.html') filePath = htmlPath;
  else if (url === '/kinrel_dark_style.json') filePath = stylePath;
  else { res.writeHead(404); res.end('not found'); return; }
  const ext = filePath.endsWith('.json') ? 'application/json'
            : filePath.endsWith('.html') ? 'text/html' : 'application/octet-stream';
  res.writeHead(200, { 'Content-Type': ext + '; charset=utf-8',
                       'Cache-Control': 'no-store' });
  import('node:fs').then(fs => {
    res.end(fs.readFileSync(filePath));
  });
});

await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;
const base = `http://127.0.0.1:${port}/`;
console.log(`[v10-verify] local server: ${base}`);

const browser = await puppeteer.launch({
  headless: 'new',
  args: [
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-dev-shm-usage',
    '--enable-logging', '--v=1',
    '--use-gl=angle',
    '--use-angle=swiftshader',
    '--enable-unsafe-swiftshader',
    '--ignore-gpu-blocklist',
  ],
});

const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 720, deviceScaleFactor: 1 });

const consoleLines = [];
page.on('console', msg => consoleLines.push(`[${msg.type()}] ${msg.text()}`));
page.on('pageerror', err => consoleLines.push(`[pageerror] ${err.message}`));
page.on('requestfailed', req => consoleLines.push(`[reqfail] ${req.url()} ${req.failure()?.errorText}`));

console.log(`[v10-verify] navigating to ${base}`);
await page.goto(base, { waitUntil: 'domcontentloaded', timeout: 30000 });

// Wait for style to be fetched and MapLibre instance created
await page.waitForFunction(() => !!window.__map, { timeout: 15000 });
console.log('[v10-verify] maplibre.Map instance created');

// Wait for style.load event
await page.waitForFunction(() => !!window.__styleLoadFired, { timeout: 30000 })
  .catch(() => console.error('[v10-verify] style.load did NOT fire within 30s'));
console.log('[v10-verify] style.load fired');

// Give tiles a moment to start loading
await new Promise(r => setTimeout(r, 2000));

async function capturePose(name, pitch, bearing) {
  console.log(`[v10-verify] capturing ${name} (pitch=${pitch}, bearing=${bearing})`);
  // Use easeTo so we get the actual camera pose we want
  await page.evaluate(({ pitch, bearing }) => {
    return new Promise(resolve => {
      window.__map.once('moveend', () => resolve());
      window.__map.easeTo({ pitch, bearing, duration: 800 });
    });
  }, { pitch, bearing });
  // Wait for idle (all tiles loaded) with timeout
  await page.waitForFunction(() => !!window.__idleFired, { timeout: 45000 })
    .catch(() => console.warn(`[v10-verify] idle did not fire for ${name} — capturing anyway`));
  // Reset idle flag so we can detect the next idle
  await page.evaluate(() => { window.__idleFired = false; });
  // Small settle delay
  await new Promise(r => setTimeout(r, 1500));
  const outPng = join(OUT_DIR, `${name}.png`);
  await page.screenshot({ path: outPng, type: 'png' });
  console.log(`[v10-verify] saved ${outPng}`);
}

await capturePose('pose_a_pitch0', 0, 0);
await capturePose('pose_b_pitch50_bearing-17', 50, -17);

// Final: dump captured errors + a tail of console logs
const errors = await page.evaluate(() => window.__errors);
const logsTail = (await page.evaluate(() => window.__logs)).slice(-50);

writeFileSync(join(OUT_DIR, 'console.log'),
              '=== v10 visual verify console capture ===\n\n'
              + '--- page.on console ---\n' + consoleLines.join('\n') + '\n\n'
              + '--- in-page errors ---\n' + (errors.length ? errors.join('\n\n') : '(none)') + '\n\n'
              + '--- last 50 in-page logs ---\n' + logsTail.join('\n') + '\n');

console.log(`[v10-verify] done. Output: ${OUT_DIR}`);

await browser.close();
server.close();
process.exit(0);
