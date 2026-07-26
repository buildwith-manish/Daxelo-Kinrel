// sanity_test.mjs — Verify MapLibre + WebGL can paint anything at all in this
// environment. Uses the official MapLibre demo style (no PMTiles).
import puppeteer from 'puppeteer';
import path from 'path';

const SCREENSHOTS_DIR = '/home/z/my-project/screenshots/verification';

const browser = await puppeteer.launch({
  executablePath: '/home/z/.cache/puppeteer/chrome/linux-150.0.7871.24/chrome-linux64/chrome',
  headless: 'new',
  args: [
    '--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage',
    '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader',
    '--enable-webgl', '--ignore-gpu-blocklist',
  ],
});

const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 800 });
page.on('console', msg => console.log(`[browser ${msg.type()}] ${msg.text()}`));
page.on('pageerror', err => console.log(`[pageerror] ${err.message}`));

console.log('Loading sanity test page (MapLibre official demo style)...');
await page.goto('http://localhost:8080/sanity_test.html', { waitUntil: 'networkidle2', timeout: 30000 });

try {
  await page.waitForFunction('window.__sanityDone === true', { timeout: 30000 });
} catch (e) { console.log('Sanity timeout'); }

await new Promise(r => setTimeout(r, 5000));
await page.screenshot({ path: path.join(SCREENSHOTS_DIR, 'sanity-maplibre-demo.png'), fullPage: false });

const diag = await page.evaluate(() => document.getElementById('diag')?.textContent || '');
console.log('--- Diagnostic ---');
console.log(diag);

await browser.close();
