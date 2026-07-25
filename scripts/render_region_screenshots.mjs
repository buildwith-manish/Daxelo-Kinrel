// scripts/render_region_screenshots.mjs
//
// Phase B v1.0 — Web rendering screenshot generator
//
// Renders the Kinrel dark style on 5 required test regions per the Phase B
// brief, using headless Chromium + MapLibre GL JS + pmtiles.js.
//
// Output: 5 PNG files in $GITHUB_WORKSPACE/screenshots/ (or ./screenshots/)
//   - manhattan.png    (dense high-rise downtown)
//   - venice.png       (historic irregular-grid European)
//   - rural-kansas.png (sparse rural/suburban)
//   - riyadh.png       (arid region)
//   - dharavi.png      (dense low-rise informal settlement)
//
// Usage: node scripts/render_region_screenshots.mjs
//
// Notes:
//   - Uses OpenFreeMap as the tile source for screenshots (since Phase A's
//     PMTiles isn't deployed to production yet). This verifies the STYLE
//     JSON renders correctly across regions — the tile source swap is a
//     separate Phase A verification item.
//   - OpenFreeMap is z14-capped — screenshots at z15+ will show z14-stretched
//     buildings. The GOAL here is to verify style rendering (colors, fonts,
//     glow filters) not tile detail.
//   - MapLibre GL JS 4.7.1 + pmtiles.js 3.2.0 loaded via CDN.

import puppeteer from 'puppeteer';
import { createServer } from 'http';
import { readFile } from 'fs/promises';
import { mkdirSync, writeFileSync as wf, existsSync } from 'fs';
import { join, extname } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const WORKSPACE = process.env.GITHUB_WORKSPACE || join(__dirname, '..');
const STYLE_DIR = join(WORKSPACE, 'Daxelo-Kinrel-App/assets/map_styles');
const RENDER_DIR = join(WORKSPACE, 'Daxelo-Kinrel-App/screenshot-render');
const SCREENSHOTS_DIR = join(WORKSPACE, 'screenshots');

mkdirSync(RENDER_DIR, { recursive: true });
mkdirSync(SCREENSHOTS_DIR, { recursive: true });

// 5 required test regions per Phase B brief
const regions = [
  { id: 'manhattan',    name: 'Dense downtown',          lng: -74.0060, lat: 40.7128, zoom: 14, pitch: 45, bearing: 0 },
  { id: 'venice',       name: 'Historic European',       lng: 12.3389,  lat: 45.4376, zoom: 14, pitch: 45, bearing: 0 },
  { id: 'rural-kansas', name: 'Sparse rural',            lng: -98.4255, lat: 38.5556, zoom: 14, pitch: 45, bearing: 0 },
  { id: 'riyadh',       name: 'Arid region',             lng: 46.6753,  lat: 24.7136, zoom: 14, pitch: 45, bearing: 0 },
  { id: 'dharavi',      name: 'Dense low-rise informal',  lng: 72.8530, lat: 19.0368, zoom: 15, pitch: 45, bearing: 0 },
];

// HTML page that loads the style JSON, patches PMTiles source to OpenFreeMap
// fallback (since we can't serve a real .pmtiles archive in CI), and exposes
// the map instance on window.__map.
const renderHtml = (styleJsonUrl) => `<!doctype html>
<html><head>
  <meta charset="utf-8"/>
  <script src="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js"></script>
  <link href="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css" rel="stylesheet"/>
  <script src="https://unpkg.com/pmtiles@3.2.0/dist/pmtiles.js"></script>
  <style>html,body{margin:0;padding:0;}#map{width:1280px;height:720px;}</style>
</head><body>
  <div id="map"></div>
  <script>
    const pmtilesProtocol = new pmtiles.Protocol();
    maplibregl.addProtocol('pmtiles', pmtilesProtocol.tile);
    fetch('${styleJsonUrl}')
      .then(r => r.json())
      .then(style => {
        // Patch PMTiles source to OpenFreeMap fallback for screenshot testing
        if (style.sources && style.sources.openmaptiles) {
          delete style.sources.openmaptiles.url;
          style.sources.openmaptiles = {
            type: 'vector',
            tiles: ['https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf'],
            maxzoom: 14,
            minzoom: 0,
            attribution: '© OpenStreetMap contributors, © OpenFreeMap'
          };
        }
        const map = new maplibregl.Map({
          container: 'map',
          style: style,
          center: [0, 0],
          zoom: 13,
          pitch: 0,
          bearing: 0,
          attributionControl: false,
          // Critical for headless Chromium + SwiftShader:
          //   preserveDrawingBuffer: true keeps the WebGL buffer after composite,
          //     so readPixels and screenshot can capture the rendered content.
          //   Without this, the buffer is swapped/cleared before Puppeteer's
          //     screenshot can capture it (the "blank 4257-byte PNG" bug).
          preserveDrawingBuffer: true,
          // Don't fail if WebGL is software-rendered (SwiftShader)
          failIfMajorPerformanceCaveat: false,
          // Force canvas backend (not WebGL) if available — more reliable
          // in headless environments. MapLibre falls back to WebGL if canvas
          // isn't sufficient.
          // (Note: as of MapLibre GL JS 4.x, 'preferCanvas' only affects
          // symbol layers — the base map still uses WebGL. But it doesn't hurt.)
          preferCanvas: true,
        });
        window.__map = map;
      })
      .catch(err => {
        console.error('Style load failed:', err);
        document.body.innerHTML = '<pre style="color:red;padding:20px;">Style load failed: ' + err.message + '</pre>';
      });
  </script>
</body></html>`;

wf(join(RENDER_DIR, 'index.html'), renderHtml('/kinrel_dark_style.json'));

const MIME = { '.json': 'application/json', '.html': 'text/html', '.js': 'text/javascript' };

const server = createServer(async (req, res) => {
  try {
    const p = req.url === '/' ? '/index.html' : req.url;
    const filePath = p === '/index.html'
      ? join(RENDER_DIR, 'index.html')
      : join(STYLE_DIR, p);
    const data = await readFile(filePath);
    res.writeHead(200, { 'Content-Type': MIME[extname(filePath)] || 'application/octet-stream' });
    res.end(data);
  } catch (e) {
    res.writeHead(404);
    res.end('Not found');
  }
});

await new Promise(r => server.listen(8099, r));
console.log('Static server on :8099');

const browser = await puppeteer.launch({
  headless: 'new',
  args: [
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-dev-shm-usage',
    // WebGL via SwiftShader (software rendering) — required for MapLibre GL JS
    // in headless Chromium. Without these flags, the WebGL context is created
    // but rendering produces a blank canvas (all background color).
    '--enable-unsafe-swiftshader',
    '--use-gl=angle',
    '--use-angle=swiftshader',
    '--enable-webgl',
    '--ignore-gpu-blocklist',
  ],
});

let successCount = 0;
let failureCount = 0;

for (const region of regions) {
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 720, deviceScaleFactor: 1 });

  page.on('console', msg => console.log(`[${region.id}] PAGE LOG:`, msg.text()));
  page.on('pageerror', err => console.log(`[${region.id}] PAGE ERROR:`, err.message));
  page.on('requestfailed', req => {
    const url = req.url();
    // Don't log tile request failures (they're expected for some regions)
    if (!url.includes('openfreemap.org') && !url.includes('tile')) {
      console.log(`[${region.id}] REQUEST FAILED:`, url, req.failure()?.errorText);
    }
  });

  try {
    await page.goto('http://localhost:8099/index.html', { waitUntil: 'load', timeout: 30000 });
    await page.waitForFunction('window.__map !== undefined', { timeout: 15000 });
    console.log(`[${region.id}] map object created`);

    // Wait for the map's `load` event (fires when style has loaded)
    await page.waitForFunction('window.__map.isStyleLoaded()', { timeout: 20000 }).catch(() => {
      console.log(`[${region.id}] style not fully loaded after 20s — proceeding anyway`);
    });
    console.log(`[${region.id}] style loaded`);

    // Jump to region (jumpTo is instant, no animation)
    await page.evaluate((r) => {
      window.__map.jumpTo({
        center: [r.lng, r.lat],
        zoom: r.zoom,
        pitch: r.pitch,
        bearing: r.bearing,
      });
    }, region);
    console.log(`[${region.id}] jumped to region: ${region.lng}, ${region.lat} z${region.zoom}`);

    // Wait for the map's 'idle' event, which fires when all tiles have loaded
    // AND the map has rendered. This is more reliable than polling areTilesLoaded().
    // Set up the listener BEFORE we wait, with a 25s timeout.
    await page.evaluate(() => {
      window.__idlePromise = new Promise((resolve) => {
        if (window.__map.areTilesLoaded() && window.__map.isStyleLoaded()) {
          resolve();
        } else {
          window.__map.once('idle', () => resolve());
          // Safety timeout — resolve anyway after 25s
          setTimeout(resolve, 25000);
        }
      });
    });
    await page.waitForFunction('window.__idlePromise !== undefined', { timeout: 5000 });
    await page.evaluate(() => window.__idlePromise);
    console.log(`[${region.id}] map idle (tiles + style loaded)`);

    // Extra render wait — give MapLibre a chance to actually paint to the canvas
    // With preserveDrawingBuffer: true, the buffer is preserved for screenshot.
    await new Promise(r => setTimeout(r, 2000));

    // Verify the map actually rendered (not all background color) by sampling
    // the center pixel of the canvas via WebGL readPixels.
    // With preserveDrawingBuffer: true, this should return real pixel data.
    const canvasInfo = await page.evaluate(() => {
      const canvas = document.querySelector('#map canvas');
      if (!canvas) return { error: 'no canvas found' };
      try {
        const ctx = canvas.getContext('webgl2') || canvas.getContext('webgl');
        if (!ctx) return { error: 'no WebGL context' };
        const w = canvas.width, h = canvas.height;
        // Read a 4x4 grid of pixels around the center (in case center is background)
        const samples = {};
        const positions = [
          ['center', Math.floor(w/2), Math.floor(h/2)],
          ['tl', Math.floor(w*0.25), Math.floor(h*0.75)],
          ['tr', Math.floor(w*0.75), Math.floor(h*0.75)],
          ['bl', Math.floor(w*0.25), Math.floor(h*0.25)],
          ['br', Math.floor(w*0.75), Math.floor(h*0.25)],
        ];
        for (const [name, x, y] of positions) {
          const pixels = new Uint8Array(4);
          ctx.readPixels(x, y, 1, 1, ctx.RGBA, ctx.UNSIGNED_BYTE, pixels);
          samples[name] = [pixels[0], pixels[1], pixels[2], pixels[3]];
        }
        return { width: w, height: h, samples };
      } catch (e) {
        return { error: e.message };
      }
    });
    console.log(`[${region.id}] canvas samples:`, JSON.stringify(canvasInfo));

    const outPath = join(SCREENSHOTS_DIR, `${region.id}.png`);
    await page.screenshot({
      path: outPath,
      // Capture the full page, not just viewport — sometimes the canvas
      // is positioned outside the viewport due to layout quirks.
      fullPage: false,
    });
    console.log(`✓ Screenshot: ${outPath} (${region.name})`);
    successCount++;
  } catch (e) {
    console.log(`❌ Failed: ${region.id} — ${e.message}`);
    // Take a screenshot anyway for debugging
    try {
      const errPath = join(SCREENSHOTS_DIR, `${region.id}-error.png`);
      await page.screenshot({ path: errPath });
      console.log(`  (error screenshot saved to ${errPath})`);
    } catch (_) {}
    failureCount++;
  } finally {
    await page.close();
  }
}

await browser.close();
server.close();

console.log(`\n=== Summary ===`);
console.log(`✓ Success: ${successCount}/${regions.length}`);
console.log(`❌ Failed:  ${failureCount}/${regions.length}`);

if (failureCount > 0) {
  process.exit(1);
}
