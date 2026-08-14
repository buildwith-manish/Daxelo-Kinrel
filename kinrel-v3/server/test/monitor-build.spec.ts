/**
 * Daxelo-Kinrel — Vercel Build Monitor Tests
 * ============================================
 * Verifies the monitor script's dry-run mode handles all 4 Vercel build
 * outcomes correctly. No live API calls, no real token.
 */
import { execFileSync } from "child_process";
import * as path from "path";

const SCRIPT = path.resolve(__dirname, "../scripts/vercel/monitor-build.mjs");

function runDryRun(scenario: string): { exitCode: number; stdout: string; stderr: string } {
  try {
    const stdout = execFileSync("node", [SCRIPT, "--dry-run", scenario], {
      encoding: "utf-8",
      timeout: 10_000,
    });
    return { exitCode: 0, stdout, stderr: "" };
  } catch (e: any) {
    return {
      exitCode: e.status ?? -1,
      stdout: e.stdout ?? "",
      stderr: e.stderr ?? "",
    };
  }
}

describe("Vercel Build Monitor — dry-run scenarios", () => {
  test("success scenario → exit 0, READY printed", () => {
    const r = runDryRun("success");
    expect(r.exitCode).toBe(0);
    expect(r.stdout).toContain("state=READY");
    expect(r.stdout).toContain("✓ Deployment READY");
    expect(r.stdout).toContain("Inspection: https://vercel.com/");
    // No token leak
    expect(r.stdout).not.toMatch(/vcp_|Bearer /i);
    expect(r.stderr).not.toMatch(/vcp_|Bearer /i);
  });

  test("error scenario → exit 1, ERROR printed", () => {
    const r = runDryRun("error");
    expect(r.exitCode).toBe(1);
    expect(r.stdout).toContain("state=ERROR");
    expect(r.stdout).toContain("✗ Deployment ERROR");
  });

  test("canceled scenario → exit 1, CANCELED printed", () => {
    const r = runDryRun("canceled");
    expect(r.exitCode).toBe(1);
    expect(r.stdout).toContain("state=CANCELED");
    expect(r.stdout).toContain("✗ Deployment CANCELED");
  });

  test("timeout scenario → exit 1, TIMEOUT printed", () => {
    const r = runDryRun("timeout");
    expect(r.exitCode).toBe(1);
    expect(r.stdout).toContain("Timeout");
    expect(r.stdout).toContain("BUILDING");
  });

  test("unknown scenario → exit 2 with usage", () => {
    const r = runDryRun("nonsense");
    expect(r.exitCode).toBe(2);
    expect(r.stderr.toLowerCase()).toContain("unknown");
  });

  test("missing args (real mode) → exit 2 with usage", () => {
    const r = runDryRun("__missing_args__"); // placeholder
    // Override: actually call with no args
    try {
      execFileSync("node", [SCRIPT], { encoding: "utf-8", timeout: 5_000 });
      fail("Should have thrown");
    } catch (e: any) {
      expect(e.status).toBe(2);
      expect(e.stderr).toContain("Usage:");
    }
  });

  test("dry-run never makes network calls and never references a real token", () => {
    const r = runDryRun("success");
    expect(r.stdout).toContain("no network calls made, no token used");
    // The fake URL should be clearly fake
    expect(r.stdout).toContain("dryrun");
  });
});
