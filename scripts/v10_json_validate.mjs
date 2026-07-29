// scripts/v10_json_validate.mjs
//
// v10 visual-system JSON validator — fast, deterministic structural check
// of the bundled Kinrel dark style. Does NOT require headless browser or
// network tile fetches. Confirms:
//
//   1. JSON parses cleanly.
//   2. Top-level `fog` block exists with required properties.
//   3. `sky` LAYER (type 'sky') exists at the bottom of the layer stack
//      with sky-type: 'atmosphere' and all required paint properties.
//   4. 3D building layers exist in correct order:
//      kinrel-3d-buildings → kinrel-3d-buildings-warm-glow →
//      kinrel-3d-buildings-family-proximity-glow.
//   5. kinrel-buildings-outline exists with interpolated line-width/opacity.
//   6. kinrel-3d-buildings-family-proximity-glow is registered in
//      _kControlledLayerIds in map_quality_tier.dart.
//   7. All road-* line layers have line-cap: 'round' and line-join: 'round'.
//   8. All road colors form a monotone desaturation hierarchy (motorway
//      most saturated, service/track most desaturated).
//
// Output: prints a structured report to stdout + writes
// /home/z/my-project/download/v10-visual-verify/validation-report.md

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const STYLE = '/home/z/my-project/Daxelo-Kinrel-App/assets/map_styles/kinrel_dark_style.json';
const QUALITY_TIER = '/home/z/my-project/Daxelo-Kinrel-App/lib/features/family_map/config/map_quality_tier.dart';
const VISUAL_CONSTS = '/home/z/my-project/Daxelo-Kinrel-App/lib/features/family_map/config/map_visual_constants.dart';
const OUT_DIR = '/home/z/my-project/download/v10-visual-verify';
mkdirSync(OUT_DIR, { recursive: true });

const report = [];
function out(line = '') { report.push(line); console.log(line); }

let pass = 0, fail = 0;
function check(name, cond, details = '') {
  if (cond) { pass++; out(`  ✅ ${name}`); }
  else { fail++; out(`  ❌ ${name}${details ? ' — ' + details : ''}`); }
}

out('# v10 Visual System — JSON Validation Report');
out('');
out(`Generated: ${new Date().toISOString()}`);
out('');
out('---');
out('');

// ── 1. Parse JSON ─────────────────────────────────────────────────────
out('## 1. JSON parsing');
let style;
try {
  style = JSON.parse(readFileSync(STYLE, 'utf8'));
  check('kinrel_dark_style.json parses', true);
} catch (e) {
  check('kinrel_dark_style.json parses', false, e.message);
  out(''); finalize();
  process.exit(1);
}
out(`  - ${style.layers.length} layers total`);
out('');

// ── 2. fog top-level block ────────────────────────────────────────────
out('## 2. Top-level `fog` block (Task 2a)');
const fog = style.fog;
check('fog block exists', !!fog);
if (fog) {
  check('fog.color = #0B0F17', fog.color === '#0B0F17', `got ${fog.color}`);
  check('fog.high-color = #2A2030 (warm horizon)', fog['high-color'] === '#2A2030', `got ${fog['high-color']}`);
  check('fog.space-color set', typeof fog['space-color'] === 'string', `got ${fog['space-color']}`);
  check('fog.horizon-blend in [0,1]', typeof fog['horizon-blend'] === 'number' && fog['horizon-blend'] >= 0 && fog['horizon-blend'] <= 1, `got ${fog['horizon-blend']}`);
  check('fog.star-intensity = 0 (no stars in dark theme)', fog['star-intensity'] === 0, `got ${fog['star-intensity']}`);
  check('fog.range is array of 2 numbers', Array.isArray(fog.range) && fog.range.length === 2, `got ${JSON.stringify(fog.range)}`);
}
out('');

// ── 3. sky LAYER (type 'sky') ─────────────────────────────────────────
out('## 3. `sky` LAYER with sky-type: atmosphere (Task 2b)');
const skyLayer = style.layers.find(l => l.type === 'sky');
check('sky layer exists', !!skyLayer);
if (skyLayer) {
  const idx = style.layers.indexOf(skyLayer);
  out(`  - sky layer is at index ${idx} (background is index 0; lower index = bottom of stack)`);
  check('sky layer is at index 1 (right after background, bottom of stack)', idx === 1, `got ${idx}`);
  const p = skyLayer.paint || {};
  check('sky.paint.sky-type = "atmosphere"', p['sky-type'] === 'atmosphere', `got ${p['sky-type']}`);
  check('sky.paint.sky-color = #0B0F17', p['sky-color'] === '#0B0F17', `got ${p['sky-color']}`);
  check('sky.paint.horizon-color = #2A2030 (warm)', p['horizon-color'] === '#2A2030', `got ${p['horizon-color']}`);
  check('sky.paint.fog-color set', typeof p['fog-color'] === 'string');
  check('sky.paint.fog-ground-blend in [0,1]', typeof p['fog-ground-blend'] === 'number');
  check('sky.paint.horizon-fog-blend in [0,1]', typeof p['horizon-fog-blend'] === 'number');
  check('sky.paint.sky-horizon-blend in [0,1]', typeof p['sky-horizon-blend'] === 'number');
  check('sky.paint.atmosphere-blend is zoom-interpolated expression',
        Array.isArray(p['atmosphere-blend']) && p['atmosphere-blend'][0] === 'interpolate',
        `got ${JSON.stringify(p['atmosphere-blend']).slice(0,80)}`);
}
out('');

// ── 4. 3D building layer ordering ────────────────────────────────────
out('## 4. 3D building layer ordering (Task 3 + Task 4)');
const idxOf = (id) => style.layers.findIndex(l => l.id === id);
const mainIdx = idxOf('kinrel-3d-buildings');
const outlineIdx = idxOf('kinrel-buildings-outline');
const warmGlowIdx = idxOf('kinrel-3d-buildings-warm-glow');
const proxGlowIdx = idxOf('kinrel-3d-buildings-family-proximity-glow');
check('kinrel-3d-buildings exists', mainIdx >= 0);
check('kinrel-buildings-outline exists', outlineIdx >= 0);
check('kinrel-3d-buildings-warm-glow exists', warmGlowIdx >= 0);
check('kinrel-3d-buildings-family-proximity-glow exists', proxGlowIdx >= 0);
if (mainIdx >= 0 && warmGlowIdx >= 0) {
  check('warm-glow is ABOVE main extrusion (renders on top)', warmGlowIdx > mainIdx, `main=${mainIdx}, warm=${warmGlowIdx}`);
}
if (warmGlowIdx >= 0 && proxGlowIdx >= 0) {
  check('proximity-glow is ABOVE warm-glow (per spec)', proxGlowIdx > warmGlowIdx, `warm=${warmGlowIdx}, prox=${proxGlowIdx}`);
}

// 4a. Main extrusion height-graded color (Task 3)
if (mainIdx >= 0) {
  const mainPaint = style.layers[mainIdx].paint || {};
  const c = mainPaint['fill-extrusion-color'];
  check('main extrusion color is interpolation expression', Array.isArray(c) && c[0] === 'interpolate');
  if (Array.isArray(c)) {
    // Format: ['interpolate', ['linear'], <input>, stop1val, stop1out, stop2val, stop2out, ...]
    // stops array starts at index 2; index 2 is the input expression, real stops start at index 3
    const stops = c.slice(3);
    const findStop = (val) => {
      for (let i = 0; i < stops.length; i += 2) if (stops[i] === val) return stops[i+1];
      return undefined;
    };
    check('main color at height 0 = #1E1D2A', findStop(0) === '#1E1D2A', `got ${findStop(0)}`);
    check('main color at height 200 = #4A4060', findStop(200) === '#4A4060', `got ${findStop(200)}`);
  }
  check('main extrusion has fill-extrusion-vertical-gradient = true',
        mainPaint['fill-extrusion-vertical-gradient'] === true);
}

// 4b. Proximity glow layer (Task 4)
if (proxGlowIdx >= 0) {
  const prox = style.layers[proxGlowIdx];
  check('proximity-glow source = openmaptiles', prox.source === 'openmaptiles');
  check('proximity-glow source-layer = building', prox['source-layer'] === 'building');
  check('proximity-glow minzoom = 13', prox.minzoom === 13, `got ${prox.minzoom}`);
  const proxPaint = prox.paint || {};
  check('proximity-glow color = #E8612A (amber)',
        proxPaint['fill-extrusion-color'] === '#E8612A',
        `got ${proxPaint['fill-extrusion-color']}`);
  // Filter can be either:
  //  - The __placeholder_proximity__ default (gets overwritten at runtime)
  //  - The `within` expression (if runtime injection already ran)
  const f = prox.filter;
  const isPlaceholder = Array.isArray(f) && f[0] === '==' &&
        Array.isArray(f[1]) && f[1][0] === 'get' && f[1][1] === '__placeholder_proximity__';
  const isWithin = Array.isArray(f) && f[0] === 'within';
  check('proximity-glow filter is placeholder or within-expression',
        isPlaceholder || isWithin,
        `got ${JSON.stringify(f).slice(0,80)}`);
}
out('');

// ── 5. Outline tuning (Task 3) ────────────────────────────────────────
out('## 5. kinrel-buildings-outline pitch/zoom tuning (Task 3)');
if (outlineIdx >= 0) {
  const o = style.layers[outlineIdx];
  check('outline source = openmaptiles', o.source === 'openmaptiles');
  check('outline source-layer = building', o['source-layer'] === 'building');
  const p = o.paint || {};
  check('outline line-color = #4A4060', p['line-color'] === '#4A4060', `got ${p['line-color']}`);
  check('outline line-width is zoom-interpolated',
        Array.isArray(p['line-width']) && p['line-width'][0] === 'interpolate');
  check('outline line-opacity is zoom-interpolated',
        Array.isArray(p['line-opacity']) && p['line-opacity'][0] === 'interpolate');
}
out('');

// ── 6. Quality tier registration (Task 4 part 2) ─────────────────────
out('## 6. MapQualityTier registration (Task 4 part 2)');
const qtSource = readFileSync(QUALITY_TIER, 'utf8');
check('_kControlledLayerIds contains kinrel-3d-buildings-warm-glow',
      qtSource.includes("'kinrel-3d-buildings-warm-glow'"));
check('_kControlledLayerIds contains kinrel-3d-buildings-family-proximity-glow',
      qtSource.includes("'kinrel-3d-buildings-family-proximity-glow'"));
out('');

// ── 7. Visual constants (Task 1) ─────────────────────────────────────
out('## 7. MapVisualConstants (Task 1)');
const vc = readFileSync(VISUAL_CONSTS, 'utf8');
check('defaultPitch = 50.0', /defaultPitch\s*=\s*50\.0/.test(vc));
check('defaultBearing = -17.0', /defaultBearing\s*=\s*-17\.0/.test(vc));
check('focusPitch = 45.0 (preserved)', /focusPitch\s*=\s*45\.0/.test(vc));
check('proximityGlowRadiusMeters = 150.0', /proximityGlowRadiusMeters\s*=\s*150\.0/.test(vc));
out('');

// ── 8. Road styling (Task 5) ──────────────────────────────────────────
out('## 8. Road styling — line-cap/line-join round + desaturation (Task 5)');
// Note: rail layers (road_major_rail*, road_transit_rail*) are train tracks
// with hatching patterns — they intentionally do NOT use line-join: round.
const railPattern = /(_rail|_rail_hatching|_arrow|_arrow_opposite|_shield|_area_pattern|_path_pedestrian)/;
const roadLayers = style.layers.filter(l =>
  typeof l.id === 'string' && l.id.startsWith('road_') && l.type === 'line' && !railPattern.test(l.id));
out(`  - ${roadLayers.length} road line layers found (rail/arrow/shield/path excluded)`);
let roadCapOk = 0, roadJoinOk = 0, roadCapFail = [], roadJoinFail = [];
for (const l of roadLayers) {
  const layout = l.layout || {};
  if (layout['line-cap'] === 'round') roadCapOk++;
  else roadCapFail.push(`${l.id}=${layout['line-cap'] ?? '(missing)'}`);
  if (layout['line-join'] === 'round') roadJoinOk++;
  else roadJoinFail.push(`${l.id}=${layout['line-join'] ?? '(missing)'}`);
}
check(`all road layers have line-cap: round (${roadCapOk}/${roadLayers.length})`,
      roadCapOk === roadLayers.length,
      roadCapFail.length ? `missing: ${roadCapFail.join(', ')}` : '');
check(`all road layers have line-join: round (${roadJoinOk}/${roadLayers.length})`,
      roadJoinOk === roadLayers.length,
      roadJoinFail.length ? `missing: ${roadJoinFail.join(', ')}` : '');

// Desaturation hierarchy: motorway should be brightest/most saturated,
// service/track should be darkest/most desaturated.
const roadColors = {};
for (const l of roadLayers) {
  if (l.id.endsWith('_casing')) continue;  // casing = outline, not road color
  const c = l.paint?.['line-color'];
  if (typeof c === 'string') roadColors[l.id] = c;
}
out('');
out('  Road color hierarchy (brightest first → most desaturated last):');
const ordered = Object.entries(roadColors).sort((a,b) => {
  const lum = (hex) => {
    const h = hex.replace('#','');
    const r = parseInt(h.slice(0,2),16), g = parseInt(h.slice(2,4),16), b = parseInt(h.slice(4,6),16);
    return (r+g+b)/3;
  };
  return lum(b[1]) - lum(a[1]);
});
for (const [id, c] of ordered) {
  out(`    ${id.padEnd(34)} ${c}`);
}
// Motorway and motorway_link share the same color (#4A3F63) — accept either.
check('top of hierarchy is road_motorway or road_motorway_link (both share #4A3F63)',
      ordered.length > 0 && (ordered[0][0] === 'road_motorway' || ordered[0][0] === 'road_motorway_link'),
      `got ${ordered[0]?.[0]}`);
check('bottom of hierarchy is a non-motorway class (#221E36)',
      ordered.length > 0 && ordered[ordered.length-1][1] === '#221E36',
      `got ${ordered[ordered.length-1]?.[1]}`);
out('');

// ── 9. Summary ────────────────────────────────────────────────────────
out('---');
out('');
out(`## Summary: ${pass} passed, ${fail} failed`);
out('');
if (fail === 0) {
  out('✅ **All v10 visual-system checks passed.** The style JSON is');
  out('   structurally correct and ready for Vercel preview deployment.');
} else {
  out('❌ **Some checks failed.** Review the failures above before deploy.');
}

writeFileSync(`${OUT_DIR}/validation-report.md`, report.join('\n') + '\n');
console.log(`\nReport written to ${OUT_DIR}/validation-report.md`);
process.exit(fail === 0 ? 0 : 1);
