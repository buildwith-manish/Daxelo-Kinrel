// scripts/v9_flutter_app_inspect.mjs
//
// Drives the actual Flutter web app at the production URL.
// Captures ALL console, network, and DOM evidence to figure out
// what's happening when the user loads the page.
//
// Tries multiple routes:
//   1. / (landing — should redirect to /sign-in if not authed)
//   2. /family-map (should redirect to /sign-in if not authed)
//   3. /sign-in (the login form)
//
// For each, captures:
//   - All console messages (info/warn/error)
//   - All network requests + statuses
//   - All page errors
//   - DOM state (Flutter widgets, maplibre containers)
//   - Screenshots
//
// This does NOT log in — the goal is to see if the Flutter app boots
// correctly and if there are any JS-level errors that would prevent
// the map from rendering later.

import puppeteer from 'puppeteer';
import fs from 'node:fs';
import path from 'node:path';

const OUT_DIR = '/home/z/my-project/download/v9-blank-investigation';
fs.mkdirSync(OUT_DIR, { recursive: true });

const BASE = 'https://daxelo-kinrel.vercel.app';

async function inspectRoute(browser, route, label) {
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });

  // Disable cache to bypass the immutable asset cache
  const client = await page.target().createCDPSession();
  await client.send('Network.setCacheDisabled', { cacheDisabled: true });

  const consoleLog = [];
  const pageErrors = [];
  const failedReqs = [];
  const errorResponses = [];
  const allRequests = [];

  page.on('console', (msg) => {
    consoleLog.push({ t: Date.now(), type: msg.type(), text: msg.text() });
  });
  page.on('pageerror', (err) => {
    pageErrors.push({ t: Date.now(), name: err.name, message: err.message, stack: err.stack?.split('\n').slice(0, 5).join(' | ') });
  });
  page.on('requestfailed', (req) => {
    failedReqs.push({
      t: Date.now(),
      url: req.url(),
      failure: req.failure()?.errorText ?? null,
    });
  });
  page.on('response', (resp) => {
    const status = resp.status();
    const url = resp.url();
    if (status >= 400) {
      errorResponses.push({ t: Date.now(), url, status });
    }
    allRequests.push({ t: Date.now(), url, status, method: resp.request().method() });
  });

  const url = BASE + route;
  console.log(`\n[v9] === Inspecting ${label}: ${url} ===`);
  try {
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 60000 });
  } catch (e) {
    console.log(`[v9] goto error: ${e.message}`);
  }

  // Wait for Flutter to boot
  console.log('[v9] Waiting 15s for Flutter bootstrap…');
  await new Promise((r) => setTimeout(r, 15000));

  // Screenshot
  const screenshotPath = path.join(OUT_DIR, `14_${label}.png`);
  await page.screenshot({ path: screenshotPath, fullPage: false });

  // Capture DOM + globals state
  const state = await page.evaluate(() => {
    const hasMaplibregl = typeof maplibregl !== 'undefined';
    const hasPmtiles = typeof pmtiles !== 'undefined';
    const flutter = typeof window._flutter !== 'undefined';
    const url = window.location.href;

    // Look for Flutter widgets
    const fltGlassPane = document.querySelectorAll('flt-glass-pane').length;
    const fltSceneHost = document.querySelectorAll('flt-scene-host').length;
    const fltPlatformView = document.querySelectorAll('flt-platform-view').length;
    const fltGlassPaneStyle = (() => {
      const el = document.querySelector('flt-glass-pane');
      if (!el) return null;
      const cs = getComputedStyle(el);
      return { width: cs.width, height: cs.height, position: cs.position };
    })();

    // Look for maplibre containers (in case Family Map is loaded)
    const maplibreContainers = document.querySelectorAll('.maplibregl-map, .maplibregl-canvas, canvas').length;
    const maplibreCanvases = Array.from(document.querySelectorAll('canvas')).map((c) => ({
      width: c.width,
      height: c.height,
      className: c.className,
      parentClass: c.parentElement?.className,
    }));

    // Look for any visible text on the page
    const bodyText = document.body?.innerText?.substring(0, 500);

    // Get the title
    const title = document.title;

    // Get error overlay if any
    const errorOverlay = document.querySelector('.flutter-error, .error-overlay, [class*="error"]')?.innerText?.substring(0, 300);

    return {
      url,
      title,
      hasMaplibregl,
      hasPmtiles,
      flutter,
      fltGlassPane,
      fltSceneHost,
      fltPlatformView,
      fltGlassPaneStyle,
      maplibreContainers,
      maplibreCanvases,
      bodyText,
      errorOverlay,
    };
  });

  // Service worker check
  const swInfo = await page.evaluate(async () => {
    if (!('serviceWorker' in navigator)) return { supported: false };
    const regs = await navigator.serviceWorker.getRegistrations();
    return {
      supported: true,
      count: regs.length,
      scopes: regs.map((r) => r.scope),
    };
  });

  // Cache storage check
  const cacheInfo = await page.evaluate(async () => {
    if (!('caches' in window)) return { supported: false };
    const keys = await caches.keys();
    return {
      supported: true,
      cacheNames: keys,
    };
  });

  // Save artifacts
  fs.writeFileSync(path.join(OUT_DIR, `14_${label}_console.json`), JSON.stringify(consoleLog, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, `14_${label}_page_errors.json`), JSON.stringify(pageErrors, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, `14_${label}_failed_reqs.json`), JSON.stringify(failedReqs, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, `14_${label}_error_responses.json`), JSON.stringify(errorResponses, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, `14_${label}_all_requests.json`), JSON.stringify(allRequests, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, `14_${label}_state.json`), JSON.stringify(state, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, `14_${label}_sw.json`), JSON.stringify(swInfo, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, `14_${label}_cache.json`), JSON.stringify(cacheInfo, null, 2));

  console.log('[v9] URL:', state.url);
  console.log('[v9] Title:', state.title);
  console.log('[v9] hasMaplibregl:', state.hasMaplibregl, '| hasPmtiles:', state.hasPmtiles);
  console.log('[v9] fltGlassPane:', state.fltGlassPane, '| fltSceneHost:', state.fltSceneHost, '| fltPlatformView:', state.fltPlatformView);
  console.log('[v9] fltGlassPane style:', JSON.stringify(state.fltGlassPaneStyle));
  console.log('[v9] maplibre containers:', state.maplibreContainers);
  console.log('[v9] canvases:', state.maplibreCanvases.length);
  for (const c of state.maplibreCanvases.slice(0, 5)) {
    console.log('  -', c.width + 'x' + c.height, '| class:', c.className, '| parent:', c.parentClass);
  }
  console.log('[v9] bodyText (first 200):', state.bodyText?.substring(0, 200));
  console.log('[v9] Service workers:', JSON.stringify(swInfo));
  console.log('[v9] Cache storage:', JSON.stringify(cacheInfo));
  console.log('[v9] Page errors:', pageErrors.length);
  if (pageErrors.length > 0) {
    for (const e of pageErrors.slice(0, 10)) {
      console.log('  -', e.name, ':', e.message);
    }
  }
  console.log('[v9] Failed requests:', failedReqs.length);
  console.log('[v9] 4xx/5xx responses:', errorResponses.length);
  if (errorResponses.length > 0) {
    for (const r of errorResponses.slice(0, 10)) {
      console.log('  -', r.status, r.url);
    }
  }
  console.log('[v9] Console messages:', consoleLog.length);
  const errs = consoleLog.filter((l) => l.type === 'error');
  const warns = consoleLog.filter((l) => l.type === 'warning');
  console.log('[v9] Console errors:', errs.length, '| warnings:', warns.length);
  if (errs.length > 0) {
    console.log('  Console errors (first 10):');
    for (const e of errs.slice(0, 10)) {
      console.log('    -', e.text);
    }
  }

  await page.close();
  return { label, state, consoleLog, pageErrors, errorResponses };
}

async function main() {
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
  for (const [route, label] of [
    ['/', 'root'],
    ['/sign-in', 'signin'],
    ['/family-map', 'familymap_direct'],
  ]) {
    const result = await inspectRoute(browser, route, label);
    results.push(result);
  }

  // Summary
  console.log('\n\n[v9] ========= SUMMARY =========');
  for (const r of results) {
    console.log(`\n[${r.label}]`);
    console.log('  URL:', r.state.url);
    console.log('  Title:', r.state.title);
    console.log('  fltGlassPane:', r.state.fltGlassPane, '| fltPlatformView:', r.state.fltPlatformView);
    console.log('  Page errors:', r.pageErrors.length, '| Console errors:', r.consoleLog.filter((l) => l.type === 'error').length);
    console.log('  4xx/5xx:', r.errorResponses.length);
  }

  await browser.close();
  console.log('\n[v9] Done.');
}

main().catch((e) => {
  console.error('[v9] FATAL:', e);
  process.exit(1);
});
