#!/usr/bin/env node

/**
 * cm-repos-launcher.mjs — bootstrap and launch the cm-repos MCP server.
 *
 * Called by .mcp.json via: node ${CLAUDE_PLUGIN_ROOT}/tools/cm-repos-launcher.mjs
 *
 * 1. Checks that npm dependencies are installed
 * 2. Runs npm ci --omit=dev if needed (first-run only)
 * 3. Dynamically imports cm-repos-server.mjs (same process — no subprocess)
 */

import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const log = (msg) => process.stderr.write(`[cm-repos] ${msg}\n`);

// ── Path resolution ──────────────────────────────────────────────────────────
// tools/ → cm-dev-tools/ → plugins/ → cm-marketplace/

const __filename = fileURLToPath(import.meta.url);
const toolsDir = dirname(__filename);
const repoRoot = resolve(toolsDir, "..", "..", "..");

// ── Dependency check ─────────────────────────────────────────────────────────
// Use createRequire anchored at the repo root so resolution finds
// cm-marketplace/node_modules regardless of where this file lives.

const require = createRequire(resolve(repoRoot, "package.json"));

function depsInstalled() {
  try {
    require.resolve("@modelcontextprotocol/sdk");
    require.resolve("zod");
    return true;
  } catch {
    return false;
  }
}

if (!depsInstalled()) {
  log("Dependencies not found — running npm ci --omit=dev …");
  try {
    execFileSync("npm", ["ci", "--omit=dev"], {
      cwd: repoRoot,
      stdio: ["ignore", "ignore", "inherit"], // stderr → visible, stdout → discarded
      shell: process.platform === "win32", // npm is a .cmd on Windows
      timeout: 120_000,
    });
    log("Dependencies installed successfully.");
  } catch (err) {
    log(`Failed to install dependencies: ${err.message}`);
    process.exit(1);
  }
}

// ── Launch server ────────────────────────────────────────────────────────────

try {
  await import("./cm-repos-server.mjs");
} catch (err) {
  log(`Server failed to start: ${err.message}`);
  if (err.stack) log(err.stack);
  process.exit(1);
}
