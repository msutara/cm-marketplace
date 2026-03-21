#!/usr/bin/env node

/**
 * ensure-prerequisites.mjs — preflight check and installer for cm-marketplace.
 *
 * Verifies that every CLI tool required by the marketplace scripts and skills
 * is installed and meets the minimum version. Automatically installs missing
 * tools when possible. Outputs a coloured summary to stderr.
 *
 * Exit codes:
 *   0 — all prerequisites satisfied (possibly after auto-install)
 *   1 — one or more prerequisites still missing
 *
 * Usage:
 *   node ensure-prerequisites.mjs            # check only
 *   node ensure-prerequisites.mjs --install  # check + auto-install missing
 */

import { execFileSync, execSync } from "node:child_process";
import { existsSync } from "node:fs";

const isWindows = process.platform === "win32";
const isMac = process.platform === "darwin";
const isLinux = process.platform === "linux";
const autoInstall = process.argv.includes("--install");

// ── Windows fallback paths ───────────────────────────────────────────────────
// On Windows, tools installed via Git-for-Windows, winget, scoop, or chocolatey
// may not be on the default PATH. We check common locations as fallbacks.

/** @type {Record<string, string[]>} */
const windowsFallbacks = {
  bash: [
    "C:\\Program Files\\Git\\bin\\bash.exe",
    "C:\\Program Files\\Git\\usr\\bin\\bash.exe",
    "C:\\Program Files (x86)\\Git\\bin\\bash.exe",
  ],
  jq: [
    "C:\\ProgramData\\chocolatey\\bin\\jq.exe",
    `${process.env.USERPROFILE}\\scoop\\shims\\jq.exe`,
  ],
};

// ── Colour helpers (respects NO_COLOR / CI) ──────────────────────────────────

const colour =
  !process.env.NO_COLOR && process.stderr.isTTY
    ? {
        green: (s) => `\x1b[32m${s}\x1b[0m`,
        red: (s) => `\x1b[31m${s}\x1b[0m`,
        yellow: (s) => `\x1b[33m${s}\x1b[0m`,
        bold: (s) => `\x1b[1m${s}\x1b[0m`,
        dim: (s) => `\x1b[2m${s}\x1b[0m`,
      }
    : {
        green: (s) => s,
        red: (s) => s,
        yellow: (s) => s,
        bold: (s) => s,
        dim: (s) => s,
      };

const log = (msg) => process.stderr.write(`${msg}\n`);

// ── Version parsing ──────────────────────────────────────────────────────────

/**
 * Parse a major.minor version from an arbitrary version string.
 * Handles formats like "jq-1.7.1", "bash 5.2.26(1)-release",
 * "go version go1.24.1 ...", "gh version 2.67.0", etc.
 *
 * @param {string} raw - Raw output from `tool --version`
 * @returns {{ major: number, minor: number } | null}
 */
function parseVersion(raw) {
  const match = raw.match(/(\d+)\.(\d+)/);
  if (!match) return null;
  return { major: Number(match[1]), minor: Number(match[2]) };
}

/**
 * Returns true when `actual` >= `min` (major.minor comparison).
 */
function meetsMinimum(actual, min) {
  if (actual.major > min.major) return true;
  if (actual.major === min.major && actual.minor >= min.minor) return true;
  return false;
}

// ── Tool execution ───────────────────────────────────────────────────────────

/**
 * Run a command and return its output or a structured error.
 *
 * With `shell: true` (needed on Windows for .cmd wrappers), a missing command
 * does not throw ENOENT. Instead: Unix sh exits 127, Windows cmd exits 1 with
 * "not recognized" in stderr. We detect all three patterns.
 *
 * @param {string} cmd
 * @param {string[]} args
 * @returns {{ ok: true, stdout: string } | { ok: false, reason: "not_found" | "timeout" | "exec_error" }}
 */
function tryExec(cmd, args) {
  try {
    const stdout = execFileSync(cmd, args, {
      stdio: ["pipe", "pipe", "pipe"],
      shell: isWindows, // needed on Windows for .cmd wrappers and PATH resolution
      timeout: 10_000,
    })
      .toString()
      .trim();
    return { ok: true, stdout };
  } catch (err) {
    if (err.code === "ETIMEDOUT") return { ok: false, reason: "timeout" };
    if (err.code === "ENOENT") return { ok: false, reason: "not_found" };
    // shell: true → missing command exits 127 (Unix sh) or 1 (Windows cmd)
    if (err.status === 127) return { ok: false, reason: "not_found" };
    const stderr = err.stderr?.toString() ?? "";
    if (/not recognized|not found|command not found/i.test(stderr)) {
      return { ok: false, reason: "not_found" };
    }
    return { ok: false, reason: "exec_error" };
  }
}

/**
 * Try the default command first, then Windows fallback paths if available.
 * Fallback paths are absolute, so we use shell: false to avoid quoting issues.
 *
 * @param {string} name - Tool name (key into windowsFallbacks)
 * @param {string} cmd  - Default command
 * @param {string[]} args
 * @returns {{ ok: true, stdout: string, resolvedCmd: string } | { ok: false, reason: string }}
 */
function tryExecWithFallback(name, cmd, args) {
  const result = tryExec(cmd, args);
  if (result.ok) return { ...result, resolvedCmd: cmd };

  if (isWindows && windowsFallbacks[name]) {
    for (const fallback of windowsFallbacks[name]) {
      if (!existsSync(fallback)) continue;
      try {
        const stdout = execFileSync(fallback, args, {
          stdio: ["pipe", "pipe", "pipe"],
          timeout: 10_000,
        })
          .toString()
          .trim();
        return { ok: true, stdout, resolvedCmd: fallback };
      } catch {
        // fallback failed, try next
      }
    }
  }

  return result;
}

// ── Prerequisite definitions ─────────────────────────────────────────────────

/**
 * @typedef {object} Prerequisite
 * @property {string}   name       - Display name
 * @property {string}   cmd        - Command to invoke
 * @property {string[]} args       - Arguments for version output
 * @property {{ major: number, minor: number }} minVersion
 * @property {string}   installHint - One-line manual install instruction
 * @property {{ win?: string, mac?: string, linux?: string }} [installCmd] - Auto-install commands
 */

/** @type {Prerequisite[]} */
const prerequisites = [
  {
    name: "bash",
    cmd: "bash",
    args: ["--version"],
    minVersion: { major: 4, minor: 0 },
    installHint: "brew install bash (macOS) · native on Linux · Git Bash on Windows",
    installCmd: {
      win: "winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements",
      mac: "brew install bash",
    },
  },
  {
    name: "git",
    cmd: "git",
    args: ["--version"],
    minVersion: { major: 2, minor: 30 },
    installHint: "https://git-scm.com/downloads",
    installCmd: {
      win: "winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements",
      mac: "brew install git",
      linux: "sudo apt-get install -y git || sudo yum install -y git",
    },
  },
  {
    name: "node",
    cmd: "node",
    args: ["--version"],
    minVersion: { major: 20, minor: 0 },
    installHint: "https://nodejs.org/",
    // node is running this script, so if we got here it's installed
  },
  {
    name: "jq",
    cmd: "jq",
    args: ["--version"],
    minVersion: { major: 1, minor: 6 },
    installHint: "apt install jq · brew install jq · winget install jqlang.jq",
    installCmd: {
      win: "winget install --id jqlang.jq -e --accept-source-agreements --accept-package-agreements",
      mac: "brew install jq",
      linux: "sudo apt-get install -y jq || sudo yum install -y jq",
    },
  },
  {
    name: "gh",
    cmd: "gh",
    args: ["--version"],
    minVersion: { major: 2, minor: 0 },
    installHint: "https://cli.github.com/",
    installCmd: {
      win: "winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements",
      mac: "brew install gh",
      linux: "sudo apt-get install -y gh || sudo dnf install -y gh",
    },
  },
  {
    name: "shellcheck",
    cmd: "shellcheck",
    args: ["--version"],
    minVersion: { major: 0, minor: 9 },
    installHint: "apt install shellcheck · brew install shellcheck · scoop install shellcheck",
    installCmd: {
      win: "scoop install shellcheck",
      mac: "brew install shellcheck",
      linux: "sudo apt-get install -y shellcheck",
    },
  },
];

// ── Auto-install ─────────────────────────────────────────────────────────────

/**
 * Get the install command for the current platform, if available.
 * @param {Prerequisite} prereq
 * @returns {string | undefined}
 */
function getInstallCmd(prereq) {
  if (!prereq.installCmd) return undefined;
  if (isWindows) return prereq.installCmd.win;
  if (isMac) return prereq.installCmd.mac;
  if (isLinux) return prereq.installCmd.linux;
  return undefined;
}

/**
 * Attempt to install a missing prerequisite. Returns true on success.
 * @param {Prerequisite} prereq
 * @returns {boolean}
 */
function tryInstall(prereq) {
  const cmd = getInstallCmd(prereq);
  if (!cmd) return false;

  log(`    ${colour.yellow("⟳")} Installing ${prereq.name}...`);
  try {
    execSync(cmd, { stdio: "inherit", timeout: 120_000 });
    log(`    ${colour.green("✓")} Installed successfully`);
    return true;
  } catch {
    log(`    ${colour.red("✗")} Install failed (see output above for details)`);
    return false;
  }
}

// ── Main ─────────────────────────────────────────────────────────────────────

log(colour.bold("\n🔍 cm-marketplace prerequisite check\n"));

let failures = 0;

for (const prereq of prerequisites) {
  let result = tryExecWithFallback(prereq.name, prereq.cmd, prereq.args);

  // If missing or failed, attempt auto-install then re-check
  if (!result.ok && autoInstall) {
    const installed = tryInstall(prereq);
    if (installed) {
      result = tryExecWithFallback(prereq.name, prereq.cmd, prereq.args);
    }
  }

  if (!result.ok) {
    const reason =
      result.reason === "timeout"
        ? "timed out (>10 s)"
        : result.reason === "not_found"
          ? "not found"
          : "execution failed";
    log(`  ${colour.red("✗")} ${colour.bold(prereq.name)} — ${reason}`);
    log(`    ${colour.dim(`Manual install: ${prereq.installHint}`)}`);
    failures++;
    continue;
  }

  const version = parseVersion(result.stdout);

  if (!version) {
    const versionLine =
      result.stdout.split("\n").find((l) => /\d+\.\d+/.test(l)) || result.stdout.split("\n")[0];
    log(
      `  ${colour.yellow("?")} ${colour.bold(prereq.name)} — could not parse version from: ${versionLine}`,
    );
    failures++;
    continue;
  }

  if (!meetsMinimum(version, prereq.minVersion)) {
    log(
      `  ${colour.red("✗")} ${colour.bold(prereq.name)} — found ${version.major}.${version.minor}, need ≥ ${prereq.minVersion.major}.${prereq.minVersion.minor}`,
    );
    log(`    ${colour.dim(`Upgrade: ${prereq.installHint}`)}`);
    failures++;
    continue;
  }

  const via = result.resolvedCmd !== prereq.cmd ? colour.dim(` (${result.resolvedCmd})`) : "";
  log(
    `  ${colour.green("✓")} ${colour.bold(prereq.name)} ${colour.dim(`${version.major}.${version.minor}`)}${via}`,
  );
}

log("");

if (failures > 0) {
  const hint = autoInstall
    ? ""
    : ` Run with ${colour.bold("--install")} to auto-install missing tools.`;
  log(`${colour.red(`${failures} prerequisite(s) not met.`) + hint}\n`);
  process.exit(1);
} else {
  log(colour.green("All prerequisites satisfied.\n"));
  process.exit(0);
}
