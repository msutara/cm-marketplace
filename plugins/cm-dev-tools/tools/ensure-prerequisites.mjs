#!/usr/bin/env node

/**
 * ensure-prerequisites.mjs — preflight check for cm-marketplace tools.
 *
 * Verifies that every CLI tool required by the marketplace scripts and skills
 * is installed and meets the minimum version. Outputs a coloured summary to
 * stderr so it can run as a session-start hook without polluting stdout.
 *
 * Exit codes:
 *   0 — all prerequisites satisfied
 *   1 — one or more prerequisites missing or below minimum version
 */

import { execFileSync } from "node:child_process";

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
      shell: true, // required on Windows for .cmd wrappers and PATH resolution
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

// ── Prerequisite definitions ─────────────────────────────────────────────────

/**
 * @typedef {object} Prerequisite
 * @property {string}   name       - Display name
 * @property {string}   cmd        - Command to invoke
 * @property {string[]} args       - Arguments for version output
 * @property {{ major: number, minor: number }} minVersion
 * @property {string}   installHint - One-line install instruction
 */

/** @type {Prerequisite[]} */
const prerequisites = [
  {
    name: "bash",
    cmd: "bash",
    args: ["--version"],
    minVersion: { major: 4, minor: 0 },
    installHint: "brew install bash (macOS) · native on Linux · Git Bash on Windows",
  },
  {
    name: "git",
    cmd: "git",
    args: ["--version"],
    minVersion: { major: 2, minor: 30 },
    installHint: "https://git-scm.com/downloads",
  },
  {
    name: "node",
    cmd: "node",
    args: ["--version"],
    minVersion: { major: 20, minor: 0 },
    installHint: "https://nodejs.org/",
  },
  {
    name: "jq",
    cmd: "jq",
    args: ["--version"],
    minVersion: { major: 1, minor: 6 },
    installHint: "apt install jq · brew install jq · winget install jqlang.jq",
  },
  {
    name: "gh",
    cmd: "gh",
    args: ["--version"],
    minVersion: { major: 2, minor: 0 },
    installHint: "https://cli.github.com/",
  },
  {
    name: "shellcheck",
    cmd: "shellcheck",
    args: ["--version"],
    minVersion: { major: 0, minor: 9 },
    installHint: "apt install shellcheck · brew install shellcheck",
  },
];

// ── Main ─────────────────────────────────────────────────────────────────────

log(colour.bold("\n🔍 cm-marketplace prerequisite check\n"));

let failures = 0;

for (const prereq of prerequisites) {
  const result = tryExec(prereq.cmd, prereq.args);

  if (!result.ok) {
    const reason =
      result.reason === "timeout"
        ? "timed out (>10 s)"
        : result.reason === "not_found"
          ? "not found"
          : "execution failed";
    log(`  ${colour.red("✗")} ${colour.bold(prereq.name)} — ${reason}`);
    log(`    ${colour.dim(`Install: ${prereq.installHint}`)}`);
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

  log(
    `  ${colour.green("✓")} ${colour.bold(prereq.name)} ${colour.dim(`${version.major}.${version.minor}`)}`,
  );
}

log("");

if (failures > 0) {
  log(colour.red(`${failures} prerequisite(s) not met. Fix the above before continuing.\n`));
  process.exit(1);
} else {
  log(colour.green("All prerequisites satisfied.\n"));
  process.exit(0);
}
