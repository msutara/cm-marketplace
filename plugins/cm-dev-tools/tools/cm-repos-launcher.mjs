#!/usr/bin/env node

/**
 * cm-repos-launcher.mjs — bootstrap and launch the cm-repos MCP server.
 *
 * Called by .mcp.json via: node ${CLAUDE_PLUGIN_ROOT}/tools/cm-repos-launcher.mjs
 *
 * 1. Checks that npm dependencies are installed (resolves from tools/)
 * 2. Auto-installs deps if missing (npm ci in tools/)
 * 3. Dynamically imports cm-repos-server.mjs (same process — no subprocess)
 */

import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const log = (msg) => process.stderr.write(`[cm-repos] ${msg}\n`);

// ── Path resolution ──────────────────────────────────────────────────────────
// Deps live alongside this file in tools/package.json + tools/node_modules/.
// This works in both the source repo and the installed plugin layout.

const __filename = fileURLToPath(import.meta.url);
const toolsDir = dirname(__filename);

// ── Dependency check ─────────────────────────────────────────────────────────
// Anchor createRequire at tools/package.json so resolution finds
// tools/node_modules/ regardless of where the plugin is installed.

const require = createRequire(resolve(toolsDir, "package.json"));

function depsInstalled() {
  try {
    require.resolve("@modelcontextprotocol/sdk/server/mcp.js");
    require.resolve("@modelcontextprotocol/sdk/server/stdio.js");
    require.resolve("zod");
    return true;
  } catch {
    return false;
  }
}

if (!depsInstalled()) {
  log("Dependencies not found — installing automatically...");
  const hasLockfile = existsSync(resolve(toolsDir, "package-lock.json"));
  const cmd = hasLockfile ? "npm ci --omit=dev" : "npm install --omit=dev";
  try {
    execSync(cmd, {
      cwd: toolsDir,
      stdio: ["ignore", process.stderr, process.stderr],
    });
  } catch (err) {
    const exitCode = typeof err?.status === "number" ? err.status : err?.code;
    log(
      `Auto-install failed running "${cmd}"${exitCode !== undefined ? ` (exit code: ${exitCode}).` : "."}`,
    );
    if (err?.message) log(`Error: ${err.message}`);
    log(`Install manually:\n  cd ${toolsDir} && ${cmd}\n`);
    process.exit(1);
  }

  if (!depsInstalled()) {
    log(
      "Dependencies still not found after install. Check:\n" +
        `  ${resolve(toolsDir, "package.json")}\n` +
        `  ${resolve(toolsDir, "node_modules")}\n`,
    );
    process.exit(1);
  }
  log("Dependencies installed successfully.");
}

// ── Launch server ────────────────────────────────────────────────────────────

try {
  await import("./cm-repos-server.mjs");
} catch (err) {
  log(`Server failed to start: ${err.message}`);
  if (err.stack) log(err.stack);
  process.exit(1);
}
