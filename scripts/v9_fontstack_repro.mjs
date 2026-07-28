// scripts/v9_fontstack_repro.mjs
//
// Reproduces the multi-script fontstack issue in a real browser using
// MapLibre GL JS 5.6.0 (the exact version loaded by index.html).
//
// Loads the PRODUCTION kinrel_dark_style.json AS-IS from the live URL,
// renders it in a real browser, captures console + error events, and
// screenshots the result.
//
// If the map renders WITHOUT labels but WITH basemap → fontstack is a
//   cosmetic issue, not the root cause of "blank".
// If the map renders BLANK or shows a hard error → fontstack IS the
//   root cause and must be patched in production.

import puppeteer from 'puppeteer';
import fs from 'node:fs';
import path from 'node:path';

const OUT_DIR = '/home/z/my-project/download/v9-blank-investigation';
fs.mkdirSync(OUT_DIR, { recursive: true });

const TEST_HTML = 'file:///home/z/my-project/scripts/v9_fontstack_test.html';

async function run() {
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

  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 1600, deviceScaleFactor: 1 });

  const consoleLog = [];
  const pageErrors = [];
  const failedReqs = [];
  const errorResponses = [];

  page.on('console', (msg) => {
    consoleLog.push({ t: Date.now(), type: msg.type(), text: msg.text() });
  });
  page.on('pageerror', (err) => {
    pageErrors.push({ t: Date.now(), name: err.name, message: err.message, stack: err.stack });
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
    if (status >= 400) {
      errorResponses.push({
        t: Date.now(),
        url: resp.url(),
        status,
      });
    }
  });

  console.log('[v9] Loading test HTML:', TEST_HTML);
  await page.goto(TEST_HTML, { waitUntil: 'networkidle2', timeout: 30000 });

  // Wait for the test to complete (10s settle)
  console.log('[v9] Waiting 15s for style load + tile render…');
  await new Promise((r) => setTimeout(r, 15000));

  // Screenshot the map area
  await page.screenshot({
    path: path.join(OUT_DIR, '11_fontstack_test_multiscript.png'),
    fullPage: false,
    clip: { x: 0, y: 0, width: 1440, height: 800 },
  });

  // Capture the log content from the page
  const logText = await page.evaluate(() => document.getElementById('log')?.innerText ?? '');
  fs.writeFileSync(path.join(OUT_DIR, '11_fontstack_test_log.txt'), logText);

  // Capture map state
  const mapState = await page.evaluate(() => ({
    documentTitle: document.title,
    mapCanvasExists: !!document.querySelector('#map canvas'),
    mapCanvasSize: (() => {
      const c = document.querySelector('#map canvas');
      return c ? { w: c.width, h: c.height } : null;
    })(),
    phase1Done: !!window.__phase1Done,
  }));
  fs.writeFileSync(path.join(OUT_DIR, '11_fontstack_test_state.json'), JSON.stringify(mapState, null, 2));

  fs.writeFileSync(path.join(OUT_DIR, '11_fontstack_console.json'), JSON.stringify(consoleLog, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, '11_fontstack_page_errors.json'), JSON.stringify(pageErrors, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, '11_fontstack_failed_reqs.json'), JSON.stringify(failedReqs, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, '11_fontstack_error_responses.json'), JSON.stringify(errorResponses, null, 2));

  console.log('\n[v9] === FONTSTACK TEST RESULTS ===');
  console.log('[v9] document.title:', mapState.documentTitle);
  console.log('[v9] map canvas exists:', mapState.mapCanvasExists);
  console.log('[v9] map canvas size:', JSON.stringify(mapState.mapCanvasSize));
  console.log('[v9] phase 1 done:', mapState.phase1Done);
  console.log('[v9] page errors:', pageErrors.length);
  console.log('[v9] failed requests:', failedReqs.length);
  console.log('[v9] 4xx/5xx responses:', errorResponses.length);

  if (errorResponses.length > 0) {
    console.log('\n[v9] === 4XX/5XX RESPONSES ===');
    for (const r of errorResponses.slice(0, 50)) {
      console.log('  -', r.status, r.url);
    }
  }

  if (pageErrors.length > 0) {
    console.log('\n[v9] === PAGE ERRORS ===');
    for (const e of pageErrors) {
      console.log('  -', e.name, ':', e.message);
    }
  }

  console.log('\n[v9] === MAP EVENT LOG ===');
  console.log(logText);

  await browser.close();
  console.log('\n[v9] Done. Evidence saved to', OUT_DIR);
}

run().catch((e) => {
  console.error('[v9] FATAL:', e);
  process.exit(1);
});
