// scripts/v10_visual_pass/verify_v10_scenarios.mjs
//
// v10 visual-system pass — headless verification.
//
// Loads the PATCHED kinrel_dark_style.json from disk and renders it with
// MapLibre GL JS 5.6.0 in a headless Chromium. Captures one screenshot
// per testing-checklist scenario:
//
//   1. Default load @ pitch 50, zoom 15.5, residential area WITH a
//      family pin nearby → proximity glow + 3D buildings visible.
//   2. Same area, no family pin nearby → no proximity glow (only
//      height-based warm-glow on tall buildings if any).
//   3. Top-down pin-focus view @ pitch 45 (focusPitch) → still works.
//   4. MapQualityTier.low simulation → both glow layers hidden
//      (visibility: none), base 3D buildings still render.
//   5. PMTiles probe failure → OpenFreeMap fallback shows all of the
//      above correctly (we simulate by pointing the openmaptiles source
//      at the OpenFreeMap TileJSON endpoint directly).
//   6. Pitch 0 (top-down region-overview list view) → fog/sky do NOT
//      break the flat view (sky-opacity = 0 at pitch 0).
//
// Output: /home/z/my-project/download/v10_visual_pass/*.png + diag JSON.

import puppeteer from 'puppeteer';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const SCRIPTS_DIR = path.dirname(__filename);
const PROJECT_ROOT = path.resolve(SCRIPTS_DIR, '..', '..');
const STYLE_PATH = path.join(
  PROJECT_ROOT,
  'Daxelo-Kinrel-App',
  'assets',
  'map_styles',
  'kinrel_dark_style.json',
);
const OUT_DIR = '/home/z/my-project/download/v10_visual_pass';
fs.mkdirSync(OUT_DIR, { recursive: true });

if (!fs.existsSync(STYLE_PATH)) {
  console.error('FATAL: patched style JSON not found at', STYLE_PATH);
  process.exit(1);
}

// ─────────────────────────────────────────────────────────────────────
// Test scenarios. Each scenario has:
//   - name: filename-safe identifier
//   - label: human-readable description
//   - center: [lng, lat] — Mumbai residential area for the family pin
//             (Versova, Andheri — dense residential with OSM buildings)
//   - zoom, pitch, bearing
//   - familyPlaces: array of {lat, lng, placeType} — injected into the
//                   family-places source AND used to build the proximity
//                   buffer MultiPolygon (mirrors the Dart runtime patch)
//   - patchStyle: optional (style) => style function for scenario-specific
//                 patches (e.g. low-tier visibility, fallback tile source)
// ─────────────────────────────────────────────────────────────────────

const MUMBAI_RESIDENTIAL = [72.8140, 19.1258]; // Versova, Andheri West
const MUMBAI_RESIDENTIAL_FAR = [72.8300, 19.1350]; // ~1.8km away — outside 150m buffer

const SCENARIOS = [
  {
    name: '01_default_pitch50_with_proximity_glow',
    label: 'Default load @ pitch 50° — family pin nearby → proximity glow visible',
    center: MUMBAI_RESIDENTIAL,
    zoom: 15.5,
    pitch: 50,
    bearing: -17,
    familyPlaces: [
      { lat: 19.1258, lng: 72.8140, placeType: 'current_home' },
    ],
  },
  {
    name: '02_no_family_pin_no_proximity_glow',
    label: 'Same area, no family pin within 150m → no proximity glow (only height-based glow on tall buildings if any)',
    center: MUMBAI_RESIDENTIAL,
    zoom: 15.5,
    pitch: 50,
    bearing: -17,
    familyPlaces: [
      // Pin is ~1.8km away — outside the 150m proximity buffer
      { lat: MUMBAI_RESIDENTIAL_FAR[1], lng: MUMBAI_RESIDENTIAL_FAR[0], placeType: 'current_home' },
    ],
  },
  {
    name: '03_pinfocus_pitch45_topdown',
    label: 'Pin-focus @ pitch 45° (focusPitch) — 3D buildings still visible, sky/fog correctly render',
    center: MUMBAI_RESIDENTIAL,
    zoom: 16.5, // focusMinZoom
    pitch: 45,
    bearing: 0,
    familyPlaces: [
      { lat: 19.1258, lng: 72.8140, placeType: 'current_home' },
    ],
  },
  {
    name: '04_low_tier_glow_layers_hidden',
    label: 'MapQualityTier.low — both warm-glow + proximity-glow hidden (visibility: none), base 3D buildings still render',
    center: MUMBAI_RESIDENTIAL,
    zoom: 15.5,
    pitch: 50,
    bearing: -17,
    familyPlaces: [
      { lat: 19.1258, lng: 72.8140, placeType: 'current_home' },
    ],
    patchStyle: (style) => {
      // Mirror MapQualityTierController.applyToStyleJson for low tier:
      // set layout.visibility = 'none' on every controlled layer.
      const controlled = new Set([
        'kinrel-3d-buildings-warm-glow',
        'kinrel-3d-buildings-family-proximity-glow',
      ]);
      let patched = 0;
      for (const layer of style.layers) {
        if (!controlled.has(layer.id)) continue;
        layer.layout = layer.layout || {};
        layer.layout.visibility = 'none';
        patched++;
      }
      console.log(`  [scenario 4] hid ${patched} controlled layer(s) for low tier`);
      return style;
    },
  },
  {
    name: '05_pmtiles_failure_openfreemap_fallback',
    label: 'PMTiles probe failure → OpenFreeMap TileJSON fallback shows all of the above correctly',
    center: MUMBAI_RESIDENTIAL,
    zoom: 15.5,
    pitch: 50,
    bearing: -17,
    familyPlaces: [
      { lat: 19.1258, lng: 72.8140, placeType: 'current_home' },
    ],
    patchStyle: (style) => {
      // Mirror _applyOpenFreeMapFallback: set openmaptiles source to the
      // OpenFreeMap TileJSON endpoint. The patched style already uses
      // this URL by default (v7.0 fix), so this is a no-op for the
      // current style — but we keep the scenario to verify the fallback
      // path produces the same visual result.
      style.sources.openmaptiles = {
        type: 'vector',
        url: 'https://tiles.openfreemap.org/planet',
        attribution: '© OpenStreetMap contributors, © OpenFreeMap',
      };
      console.log('  [scenario 5] forced OpenFreeMap TileJSON fallback');
      return style;
    },
  },
  {
    name: '06_pitch0_topdown_fog_sky_no_break',
    label: 'Pitch 0° (top-down region-overview list view) — fog/sky do NOT break the flat view (sky-opacity = 0)',
    center: MUMBAI_RESIDENTIAL,
    zoom: 12,
    pitch: 0,
    bearing: 0,
    familyPlaces: [
      { lat: 19.1258, lng: 72.8140, placeType: 'current_home' },
    ],
  },
];

// ─────────────────────────────────────────────────────────────────────
// Helpers — mirror the Dart runtime patches so the headless render
// reproduces what the Flutter app would produce.
// ─────────────────────────────────────────────────────────────────────

/** Build a 16-gon ~150m buffer polygon around each family-place coord. */
function buildFamilyProximityBuffer(places) {
  const radiusM = 150.0;
  const sides = 16;
  const metersPerDegLat = 111000.0;
  const coordinates = [];
  for (const p of places) {
    if (p.lat === 0 && p.lng === 0) continue;
    const cosLat = Math.max(0.0001, Math.cos((p.lat * Math.PI) / 180));
    const degLatPerM = 1 / metersPerDegLat;
    const degLngPerM = 1 / (metersPerDegLat * cosLat);
    const ring = [];
    for (let i = 0; i < sides; i++) {
      const angle = (2 * Math.PI * i) / sides;
      const dLng = radiusM * Math.cos(angle) * degLngPerM;
      const dLat = radiusM * Math.sin(angle) * degLatPerM;
      ring.push([p.lng + dLng, p.lat + dLat]);
    }
    ring.push([ring[0][0], ring[0][1]]);
    coordinates.push([ring]);
  }
  return { type: 'MultiPolygon', coordinates };
}

/** Build the GeoJSON FeatureCollection for the family-places source. */
function buildFamilyPlacesGeoJson(places) {
  const boxSize = 0.0002;
  const features = places.map((p, i) => {
    const ring = [
      [p.lng - boxSize, p.lat - boxSize],
      [p.lng + boxSize, p.lat - boxSize],
      [p.lng + boxSize, p.lat + boxSize],
      [p.lng - boxSize, p.lat + boxSize],
      [p.lng - boxSize, p.lat - boxSize],
    ];
    return {
      type: 'Feature',
      id: `place-${i}`,
      geometry: { type: 'Polygon', coordinates: [ring] },
      properties: {
        placeId: `place-${i}`,
        placeType: p.placeType,
        name: `Place ${i}`,
        memoryCount: 0,
      },
    };
  });
  return { type: 'FeatureCollection', features };
}

/**
 * Apply the Dart runtime patches to the style JSON:
 *   1. _injectFamilyProximityBuffer — replace the placeholder filter on
 *      kinrel-3d-buildings-family-proximity-glow with a `within` filter
 *      using the buffered MultiPolygon.
 *   2. Populate the family-places GeoJSON source with the test data.
 *   3. Call the scenario's patchStyle if present (e.g. low-tier).
 */
function applyRuntimePatches(style, scenario) {
  const buffer = buildFamilyProximityBuffer(scenario.familyPlaces);
  let proximityPatched = false;
  for (const layer of style.layers) {
    if (layer.id !== 'kinrel-3d-buildings-family-proximity-glow') continue;
    layer.filter = ['within', buffer];
    proximityPatched = true;
    break;
  }
  if (!proximityPatched) {
    console.warn(`  [${scenario.name}] WARNING: proximity glow layer not found`);
  } else {
    console.log(
      `  [${scenario.name}] injected proximity buffer ` +
      `(${scenario.familyPlaces.length} place(s), ` +
      `${buffer.coordinates.length} polygon ring(s))`,
    );
  }

  // Populate the family-places GeoJSON source.
  const fc = buildFamilyPlacesGeoJson(scenario.familyPlaces);
  style.sources['family-places'] = {
    type: 'geojson',
    data: fc,
  };

  // Scenario-specific patches (e.g. low-tier visibility).
  if (scenario.patchStyle) {
    style = scenario.patchStyle(style);
  }
  return style;
}

// ─────────────────────────────────────────────────────────────────────
// HTML template — loads MapLibre GL JS 5.6.0 from CDN, fetches the
// patched style JSON from disk via a `file://` URL passed as a query
// param. The scenario data is injected via window.__SCENARIO.
// ─────────────────────────────────────────────────────────────────────

function buildHtml(styleJsonStr) {
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>v10 Visual Pass Verification</title>
<script src="https://cdn.jsdelivr.net/npm/maplibre-gl@5.6.0/dist/maplibre-gl.js"></script>
<link href="https://cdn.jsdelivr.net/npm/maplibre-gl@5.6.0/dist/maplibre-gl.css" rel="stylesheet" />
<style>
  html, body { margin:0; padding:0; height:100%; background:#000; }
  #map { position:absolute; top:0; left:0; right:0; bottom:0; }
  #status { position:absolute; top:8px; left:8px; right:8px; padding:8px; background:rgba(0,0,0,0.7); color:#fff; font-family:monospace; font-size:11px; border-radius:4px; pointer-events:none; z-index:10; }
</style>
</head>
<body>
<div id="map"></div>
<div id="status">init</div>
<script>
window.__events = [];
window.__errors = [];
window.__STYLE_JSON = ${styleJsonStr};

(async () => {
  try {
    document.getElementById('status').textContent = 'parsing style…';
    const style = window.__STYLE_JSON;

    const map = new maplibregl.Map({
      container: 'map',
      style: style,
      center: window.__SCENARIO_CENTER,
      zoom: window.__SCENARIO_ZOOM,
      pitch: window.__SCENARIO_PITCH,
      bearing: window.__SCENARIO_BEARING,
      hash: false,
      preserveDrawingBuffer: true,
      attributionControl: false,
      antialias: true,
    });

    map.on('style.load', () => {
      window.__events.push('style.load');
    });
    map.on('error', (e) => {
      window.__errors.push({
        message: e.error && e.error.message,
        type: e.error && e.error.type,
        url: e.url,
      });
    });
    map.on('idle', () => {
      window.__events.push('idle');
      document.getElementById('status').textContent = 'idle (all tiles loaded)';
    });
    map.on('render', () => {
      if (!window.__firstRender) {
        window.__firstRender = Date.now();
        window.__events.push('render.first');
      }
    });
  } catch (e) {
    window.__errors.push({ message: e.message, type: e.name });
    document.getElementById('status').textContent = 'FATAL: ' + e.message;
  }
})();
</script>
</body>
</html>`;
}

// ─────────────────────────────────────────────────────────────────────
// Main — iterate scenarios, render each, capture screenshot + diag.
// ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log('══════════════════════════════════════════════════════════════════');
  console.log('  v10 VISUAL-SYSTEM PASS — Headless Verification');
  console.log('══════════════════════════════════════════════════════════════════');
  console.log('Style JSON:', STYLE_PATH);
  console.log('Output dir:', OUT_DIR);
  console.log('');

  const rawStyle = fs.readFileSync(STYLE_PATH, 'utf-8');
  const baseStyle = JSON.parse(rawStyle);
  console.log(`Loaded base style: ${baseStyle.layers.length} layers, fog=${!!baseStyle.fog}`);
  const hasSky = baseStyle.layers.some((l) => l.id === 'sky');
  const hasProximity = baseStyle.layers.some(
    (l) => l.id === 'kinrel-3d-buildings-family-proximity-glow',
  );
  console.log(`  sky layer: ${hasSky}, proximity glow layer: ${hasProximity}`);
  console.log('');

  const browser = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
    ],
  });

  const results = [];

  for (const scenario of SCENARIOS) {
    console.log(`\n▶ ${scenario.name}`);
    console.log(`  ${scenario.label}`);

    // Deep-clone the base style and apply runtime patches.
    const scenarioStyle = applyRuntimePatches(
      JSON.parse(JSON.stringify(baseStyle)),
      scenario,
    );

    const html = buildHtml(JSON.stringify(scenarioStyle));
    const htmlPath = path.join(OUT_DIR, `_tmp_${scenario.name}.html`);
    fs.writeFileSync(htmlPath, html);

    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });

    // Inject the scenario params BEFORE the page's <script> runs.
    await page.evaluateOnNewDocument((s) => {
      window.__SCENARIO_CENTER = s.center;
      window.__SCENARIO_ZOOM = s.zoom;
      window.__SCENARIO_PITCH = s.pitch;
      window.__SCENARIO_BEARING = s.bearing;
    }, scenario);

    await page.goto('file://' + htmlPath, {
      waitUntil: 'domcontentloaded',
      timeout: 30000,
    });

    // Wait for idle (or 15s timeout, whichever comes first).
    console.log('  waiting up to 15s for idle…');
    const idleStart = Date.now();
    while (Date.now() - idleStart < 15000) {
      const events = await page.evaluate(() => window.__events);
      if (events.includes('idle')) break;
      await new Promise((r) => setTimeout(r, 250));
    }

    const screenshotPath = path.join(OUT_DIR, `${scenario.name}.png`);
    await page.screenshot({ path: screenshotPath, fullPage: false });
    const stat = fs.statSync(screenshotPath);

    const diag = await page.evaluate(() => ({
      events: window.__events,
      errors: window.__errors,
      statusText: document.getElementById('status').textContent,
    }));

    fs.unlinkSync(htmlPath);

    const ok = stat.size > 50000 && diag.errors.length === 0;
    console.log(`  screenshot: ${screenshotPath} (${stat.size} bytes)`);
    console.log(`  events: ${diag.events.join(', ')}`);
    console.log(`  errors: ${diag.errors.length}`);
    if (diag.errors.length > 0) {
      for (const e of diag.errors.slice(0, 5)) {
        console.log(`    - ${e.type}: ${e.message}${e.url ? ' | url=' + e.url : ''}`);
      }
    }
    console.log(`  status: ${diag.statusText}`);
    console.log(`  ${ok ? '✅ PASS' : '❌ FAIL'}`);

    results.push({
      scenario: scenario.name,
      label: scenario.label,
      screenshot: screenshotPath,
      sizeBytes: stat.size,
      events: diag.events,
      errorCount: diag.errors.length,
      firstErrors: diag.errors.slice(0, 3),
      status: diag.statusText,
      ok,
    });

    await page.close();
  }

  await browser.close();

  // Write the summary JSON.
  const summaryPath = path.join(OUT_DIR, 'summary.json');
  fs.writeFileSync(
    summaryPath,
    JSON.stringify({ generatedAt: new Date().toISOString(), results }, null, 2),
  );
  console.log(`\n══════════════════════════════════════════════════════════════════`);
  console.log(`Summary: ${summaryPath}`);
  console.log(`Screenshots in: ${OUT_DIR}/`);
  console.log(`Pass: ${results.filter((r) => r.ok).length}/${results.length}`);
  console.log('══════════════════════════════════════════════════════════════════');
}

main().catch((e) => {
  console.error('FATAL:', e);
  process.exit(1);
});
