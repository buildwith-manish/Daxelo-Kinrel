// Daxelo-Kinrel — Vercel Build Monitor
// =====================================
// Polls the Vercel API until a deployment reaches a terminal state
// (READY | ERROR | CANCELED). Exits non-zero on failure so the GitHub
// Actions job fails too.
//
// Usage:
//   node scripts/vercel/monitor-build.mjs <deployUrl> <vercelToken> <orgId>
//   node scripts/vercel/monitor-build.mjs --dry-run [scenario]
//
// The script does NOT need to be a secret — only the token does.
// The token is read from argv (passed via ${{ secrets.VERCEL_TOKEN }} in
// the workflow). It is never logged.
//
// Dry-run scenarios (for local verification without touching Vercel):
//   success   — QUEUED → BUILDING → BUILDING → READY        (exit 0)
//   error     — QUEUED → BUILDING → ERROR                   (exit 1)
//   canceled  — QUEUED → CANCELED                           (exit 1)
//   timeout   — BUILDING forever, hits 10-min cap           (exit 1)

const argv = process.argv.slice(2);

// ---------------------------------------------------------------------------
// Dry-run mode — no network calls, no token needed.
// ---------------------------------------------------------------------------
if (argv[0] === "--dry-run") {
  const scenario = argv[1] || "success";
  console.log(`[dry-run] simulating Vercel build with scenario: ${scenario}`);
  console.log(`[dry-run] no network calls made, no token used.`);
  await runDryRun(scenario);
  // runDryRun exits the process itself.
}

// ---------------------------------------------------------------------------
// Real mode — requires live Vercel token + org ID.
// ---------------------------------------------------------------------------
const DEPLOY_URL = argv[0];
const TOKEN = argv[1];
const ORG_ID = argv[2];

if (!DEPLOY_URL || !TOKEN || !ORG_ID) {
  console.error("Usage:");
  console.error("  monitor-build.mjs <deployUrl> <vercelToken> <orgId>");
  console.error("  monitor-build.mjs --dry-run [success|error|canceled|timeout]");
  process.exit(2);
}

// Vercel deployment URLs look like:
//   https://daxelo-kinrel-server-<hash>-<org>.vercel.app
// We need to find the deployment ID, which we fetch by inspecting the URL.
async function getDeploymentMeta(url) {
  // Resolve via the Vercel API: GET /v13/deployments?app=<name>&limit=1
  // We pass teamId via query string.
  const u = new URL(url);
  const hostParts = u.hostname.split(".");
  const deployHash = hostParts[0]; // e.g. daxelo-kinrel-server-abc123

  const apiUrl = new URL("https://api.vercel.com/v13/deployments");
  apiUrl.searchParams.set("limit", "20");
  apiUrl.searchParams.set("teamId", ORG_ID);

  const res = await fetch(apiUrl, {
    headers: { Authorization: `Bearer ${TOKEN}` },
  });
  if (!res.ok) {
    throw new Error(`Vercel API error: ${res.status} ${res.statusText}`);
  }
  const body = await res.json();
  const deployments = body.deployments || [];
  // Match by URL prefix (the unique deploy hash)
  const match = deployments.find((d) => d.url && d.url.startsWith(deployHash));
  if (!match) {
    throw new Error(`Could not resolve deployment ID for ${url}`);
  }
  return { id: match.uid, name: match.name, state: match.readyState };
}

async function pollDeployment(deploymentId) {
  const start = Date.now();
  const timeoutMs = 10 * 60 * 1000; // 10 min cap
  const pollIntervalMs = 5_000;     // 5s between polls

  let lastState = null;
  for (;;) {
    const url = new URL(`https://api.vercel.com/v13/deployments/${deploymentId}`);
    url.searchParams.set("teamId", ORG_ID);
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${TOKEN}` },
    });
    if (!res.ok) {
      throw new Error(`Vercel API error: ${res.status} ${res.statusText}`);
    }
    const body = await res.json();
    const state = body.readyState;
    const buildProgress = body.buildingAt;
    const elapsedMs = Date.now() - start;

    if (state !== lastState) {
      const elapsed = (elapsedMs / 1000).toFixed(1);
      console.log(`  [${elapsed}s] state=${state}`);
      lastState = state;
    }

    // Terminal states per Vercel docs
    if (state === "READY") {
      console.log(`✓ Deployment READY (took ${(elapsedMs / 1000).toFixed(1)}s)`);
      console.log(`  Inspection: https://vercel.com/${ORG_ID}/${body.name}/${deploymentId}`);
      return { ok: true, state, deploymentId };
    }
    if (state === "ERROR") {
      console.log(`✗ Deployment ERROR`);
      if (body.errorMessage) console.log(`  Error: ${body.errorMessage}`);
      return { ok: false, state, deploymentId };
    }
    if (state === "CANCELED") {
      console.log(`✗ Deployment CANCELED`);
      return { ok: false, state, deploymentId };
    }

    if (elapsedMs > timeoutMs) {
      console.log(`✗ Timeout after ${timeoutMs / 1000}s — last state: ${state}`);
      return { ok: false, state: "TIMEOUT", deploymentId };
    }

    await sleep(pollIntervalMs);
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

(async () => {
  try {
    console.log(`Monitoring Vercel build for: ${DEPLOY_URL}`);
    const meta = await getDeploymentMeta(DEPLOY_URL);
    console.log(`  resolved deployment: id=${meta.id} name=${meta.name} state=${meta.state}`);
    const result = await pollDeployment(meta.id);
    process.exit(result.ok ? 0 : 1);
  } catch (e) {
    console.error(`Monitor failed: ${e.message}`);
    process.exit(1);
  }
})();

// ---------------------------------------------------------------------------
// Dry-run implementation
// ---------------------------------------------------------------------------
async function runDryRun(scenario) {
  // Accelerated time for dry-run — 200ms between polls instead of 5s.
  const tickMs = 200;
  const states = {
    success:  ["QUEUED", "BUILDING", "BUILDING", "BUILDING", "READY"],
    error:    ["QUEUED", "BUILDING", "BUILDING", "ERROR"],
    canceled: ["QUEUED", "CANCELED"],
    timeout:  ["BUILDING", "BUILDING", "BUILDING", "BUILDING", "BUILDING"],  // never terminates
  }[scenario];

  if (!states) {
    console.error(`Unknown scenario: ${scenario}`);
    console.error(`Choose from: success | error | canceled | timeout`);
    process.exit(2);
  }

  const fakeUrl = "https://daxelo-kinrel-server-dryrun-abc123.vercel.app";
  console.log(`Monitoring Vercel build for: ${fakeUrl}`);
  console.log(`  resolved deployment: id=dpl_dryrun_abc123 name=daxelo-kinrel-server state=${states[0]}`);

  const start = Date.now();
  let lastState = null;

  // Override timeout cap to keep dry-run snappy
  const dryRunTimeoutMs = 2_000; // 2s for timeout scenario

  for (let i = 0; i < states.length; i++) {
    const state = states[i];
    const elapsed = ((Date.now() - start) / 1000).toFixed(1);
    if (state !== lastState) {
      console.log(`  [${elapsed}s] state=${state}`);
      lastState = state;
    }
    if (state === "READY") {
      console.log(`✓ Deployment READY (took ${elapsed}s)`);
      console.log(`  Inspection: https://vercel.com/dryrun-org/daxelo-kinrel-server/dpl_dryrun_abc123`);
      process.exit(0);
    }
    if (state === "ERROR") {
      console.log(`✗ Deployment ERROR`);
      console.log(`  Error: Build step "npm run build" failed with exit code 1`);
      process.exit(1);
    }
    if (state === "CANCELED") {
      console.log(`✗ Deployment CANCELED`);
      process.exit(1);
    }
    // Timeout scenario: if we've consumed all BUILDING ticks, force timeout
    if (scenario === "timeout" && i === states.length - 1) {
      while ((Date.now() - start) < dryRunTimeoutMs) {
        await sleep(tickMs);
      }
      console.log(`✗ Timeout after ${dryRunTimeoutMs / 1000}s — last state: ${state}`);
      process.exit(1);
    }
    await sleep(tickMs);
  }
}
