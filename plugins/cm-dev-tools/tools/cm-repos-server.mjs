#!/usr/bin/env node

/**
 * cm-repos-server.mjs — MCP stdio server wrapping cm-dev-tools bash scripts.
 *
 * Exposes 8 tools for multi-repo Config Manager operations.
 * Each tool spawns the corresponding bash script, captures stdout (JSON where
 * supported) and stderr (diagnostics) separately.
 *
 * Transport: stdio (JSON-RPC over stdin/stdout)
 *
 * All scripts support --json for structured output.
 */

import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const execFileAsync = promisify(execFile);
const log = (msg) => process.stderr.write(`[cm-repos] ${msg}\n`);

// ── Path resolution ──────────────────────────────────────────────────────────

const __filename = fileURLToPath(import.meta.url);
const toolsDir = dirname(__filename);
const scriptsDir = resolve(toolsDir, "..", "scripts");

// ── Bash resolution ──────────────────────────────────────────────────────────

function resolveBash() {
  if (process.platform === "win32") {
    const gitBash = "C:\\Program Files\\Git\\bin\\bash.exe";
    if (existsSync(gitBash)) return gitBash;
  }
  return "bash";
}

const BASH = resolveBash();

// ── REPO_BASE auto-detection ─────────────────────────────────────────────────
// Mirrors the discovery logic in scripts/lib/load-project.sh:
//   1. Explicit CM_REPO_BASE env var (must contain .cm/project.json)
//   2. Walk up from cwd looking for .cm/project.json
//   3. Fallback: ~/repo/.cm/project.json

function detectRepoBase() {
  // 1. Explicit env var
  if (process.env.CM_REPO_BASE) {
    if (existsSync(join(process.env.CM_REPO_BASE, ".cm", "project.json"))) {
      return process.env.CM_REPO_BASE;
    }
    log(
      `CM_REPO_BASE set to ${process.env.CM_REPO_BASE} but .cm/project.json not found there; unsetting to allow auto-detection`,
    );
    delete process.env.CM_REPO_BASE;
  }

  // 2. Walk up from cwd
  let dir = process.cwd();
  const root = process.platform === "win32" ? `${dir.split("\\")[0]}\\` : "/";
  while (true) {
    if (existsSync(join(dir, ".cm", "project.json"))) return dir;
    const parent = dirname(dir);
    if (parent === dir || parent === root) break;
    dir = parent;
  }

  // 3. Fallback: ~/repo
  const home = process.env.USERPROFILE || process.env.HOME || "";
  if (home) {
    const fallback = join(home, "repo");
    if (existsSync(join(fallback, ".cm", "project.json"))) return fallback;
  }

  return null;
}

const REPO_BASE = detectRepoBase();
if (REPO_BASE) {
  log(`Repo base: ${REPO_BASE}`);
  process.env.CM_REPO_BASE = REPO_BASE;
} else {
  log("Warning: could not detect CM_REPO_BASE — scripts will attempt their own detection");
}

// ── Input validation ─────────────────────────────────────────────────────────

const SAFE_NAME = /^[a-zA-Z0-9_.-]+$/;
const SAFE_SEMVER = /^v\d+\.\d+\.\d+$/;
const SAFE_GO_VERSION = /^v?[a-zA-Z0-9._+-]+$/;
const SAFE_GO_MODULE = /^[a-zA-Z0-9.-]+\/[a-zA-Z0-9._\-/]+$/;
const SAFE_GH_URL = /^https:\/\/github\.com\/[a-zA-Z0-9._-]+\/[a-zA-Z0-9._-]+\/(issues|pull)\/\d+$/;

function validateRepoName(name) {
  if (!SAFE_NAME.test(name) || name === "." || name === "..")
    throw new Error(`Invalid repo name: ${name}`);
  return name;
}

function validateVersion(v) {
  if (!SAFE_SEMVER.test(v)) throw new Error(`Invalid version: ${v}`);
  return v;
}

function validateGoVersion(v) {
  if (!SAFE_GO_VERSION.test(v)) throw new Error(`Invalid Go version: ${v}`);
  return v;
}

function validateGoModule(m) {
  if (!SAFE_GO_MODULE.test(m)) throw new Error(`Invalid Go module path: ${m}`);
  return m;
}

function validateGhUrl(u) {
  if (!SAFE_GH_URL.test(u)) throw new Error(`Invalid GitHub URL: ${u}`);
  return u;
}

// ── Script runner ────────────────────────────────────────────────────────────

/**
 * Spawn a bash script and return structured output.
 *
 * @param {string}   scriptName  Filename in ../scripts/ (e.g. "repo-status.sh")
 * @param {string[]} args        Arguments after the script path
 * @param {object}   [opts]
 * @param {number}   [opts.timeout=120000]  Kill after this many ms
 * @param {boolean}  [opts.json=true]       Append --json flag to args
 * @returns {Promise<object>} Parsed JSON from stdout, or a wrapped result
 */
async function runScript(scriptName, args = [], { timeout = 120_000, json = true } = {}) {
  const scriptPath = resolve(scriptsDir, scriptName);

  if (!existsSync(scriptPath)) {
    return { ok: false, tool: scriptName, data: null, error: `Script not found: ${scriptPath}` };
  }

  const fullArgs = [scriptPath, ...args];
  if (json) fullArgs.push("--json");

  try {
    const { stdout, stderr } = await execFileAsync(BASH, fullArgs, {
      timeout,
      maxBuffer: 10 * 1024 * 1024,
      env: { ...process.env },
      cwd: REPO_BASE || process.cwd(),
    });

    if (stderr.trim()) log(stderr.trim());

    const trimmed = stdout.trim();
    if (!trimmed) {
      return { ok: true, tool: scriptName, data: null, error: null };
    }

    try {
      return JSON.parse(trimmed);
    } catch {
      return { ok: true, tool: scriptName, data: { raw: trimmed }, error: null };
    }
  } catch (err) {
    // Timeout — process was killed
    if (err.killed) {
      return {
        ok: false,
        tool: scriptName,
        data: null,
        error: `Timed out after ${timeout / 1000}s`,
      };
    }

    // Non-zero exit — try to parse stdout as JSON (scripts emit ok:false JSON)
    const stdout = (err.stdout || "").trim();
    if (stdout) {
      try {
        return JSON.parse(stdout);
      } catch {
        // fall through — return stderr / raw output
      }
    }

    const stderr = (err.stderr || "").trim();
    return {
      ok: false,
      tool: scriptName,
      data: stdout ? { raw: stdout } : null,
      error: stderr || err.message || `Exit code ${err.code}`,
    };
  }
}

/** Format a runScript result as MCP tool output. */
function reply(result) {
  return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
}

// ── MCP Server ───────────────────────────────────────────────────────────────

const server = new McpServer({
  name: "cm-repos",
  version: "1.1.0",
});

// ── Tool 1: cm_repo_status ───────────────────────────────────────────────────

server.registerTool(
  "cm_repo_status",
  {
    title: "Repo Status",
    description:
      "Show git branch, dirty/clean status, and last tag for CM repos. " +
      "Omit repo to see all repos from the project manifest.",
    inputSchema: {
      repo: z
        .string()
        .optional()
        .describe("Repo name (e.g. 'config-manager-core'). Omit for all repos."),
    },
  },
  async ({ repo }) => {
    if (repo) validateRepoName(repo);
    const args = repo ? [repo] : [];
    return reply(await runScript("repo-status.sh", args, { timeout: 30_000 }));
  },
);

// ── Tool 2: cm_validate_repo ─────────────────────────────────────────────────

server.registerTool(
  "cm_validate_repo",
  {
    title: "Validate Repo",
    description:
      "Build, test, and lint a single CM repo. " +
      "Runs go build, go test, golangci-lint, and markdownlint.",
    inputSchema: {
      repo: z
        .string()
        .describe("Repo name (e.g. 'config-manager-core'). Resolved relative to CM_REPO_BASE."),
      skipLint: z.boolean().optional().describe("Skip golangci-lint step"),
      skipMarkdown: z.boolean().optional().describe("Skip markdownlint step"),
    },
  },
  async ({ repo, skipLint, skipMarkdown }) => {
    validateRepoName(repo);
    const repoPath = REPO_BASE ? resolve(REPO_BASE, repo) : repo;
    if (REPO_BASE && !repoPath.startsWith(REPO_BASE)) {
      return reply({
        ok: false,
        tool: "validate-repo.sh",
        data: null,
        error: "Path traversal rejected",
      });
    }
    const args = [repoPath];
    if (skipLint) args.push("--skip-lint");
    if (skipMarkdown) args.push("--skip-markdown");
    return reply(await runScript("validate-repo.sh", args, { timeout: 300_000 }));
  },
);

// ── Tool 3: cm_validate_all ──────────────────────────────────────────────────

server.registerTool(
  "cm_validate_all",
  {
    title: "Validate All Repos",
    description:
      "Build, test, and lint ALL CM repos from the project manifest. " +
      "Continues through failures and reports per-repo results.",
    inputSchema: {
      skipLint: z.boolean().optional().describe("Skip golangci-lint for all repos"),
      skipMarkdown: z.boolean().optional().describe("Skip markdownlint for all repos"),
    },
  },
  async ({ skipLint, skipMarkdown }) => {
    const args = [];
    if (skipLint) args.push("--skip-lint");
    if (skipMarkdown) args.push("--skip-markdown");
    return reply(await runScript("validate-all.sh", args, { timeout: 600_000 }));
  },
);

// ── Tool 4: cm_sync_deps ────────────────────────────────────────────────────

server.registerTool(
  "cm_sync_deps",
  {
    title: "Sync Dependencies",
    description:
      "Bump a Go module dependency across all downstream CM repos. " +
      "Runs go get + go mod tidy in each repo that imports the module.",
    inputSchema: {
      sourceModule: z
        .string()
        .describe("Full Go module path (e.g. 'github.com/msutara/config-manager-core')"),
      version: z.string().describe("Target version (semver like v0.5.0, or Go pseudo-version)"),
    },
  },
  async ({ sourceModule, version }) => {
    validateGoModule(sourceModule);
    validateGoVersion(version);
    const args = [sourceModule, version];
    return reply(await runScript("sync-deps.sh", args));
  },
);

// ── Tool 5: cm_tag_repo ─────────────────────────────────────────────────────

server.registerTool(
  "cm_tag_repo",
  {
    title: "Tag Repo (Not Yet Implemented)",
    description:
      "Create a git tag for a single repo. " +
      "NOTE: Single-repo tagging is not yet supported. " +
      "This tool fails fast to avoid accidentally tagging all repos. " +
      "Use cm_tag_all to tag all repos when that is your intent.",
    inputSchema: {
      repo: z.string().describe("Target repo name (single-repo tagging not yet implemented)"),
      version: z.string().describe("Semver tag (e.g. 'v1.2.3')"),
      dryRun: z.boolean().optional().describe("Simulate tagging without creating tags or pushing"),
    },
  },
  async ({ repo, version, dryRun }) => {
    throw new Error(
      `cm_tag_repo is not yet implemented for single repositories ` +
        `(requested repo: '${repo}', version: '${version}', dryRun: ${dryRun === true}). ` +
        "To tag all repos, use the cm_tag_all tool instead.",
    );
  },
);

// ── Tool 6: cm_tag_all ──────────────────────────────────────────────────────

server.registerTool(
  "cm_tag_all",
  {
    title: "Tag All Repos",
    description:
      "Create git tags across ALL CM repos in dependency order. " +
      "Validates clean working tree and main branch. " +
      "Skips repos already tagged at the target version.",
    inputSchema: {
      version: z.string().describe("Semver tag (e.g. 'v1.2.3')"),
      dryRun: z.boolean().optional().describe("Simulate tagging without creating tags or pushing"),
    },
  },
  async ({ version, dryRun }) => {
    validateVersion(version);
    const args = [version];
    if (dryRun) args.push("--dry-run");
    return reply(await runScript("tag-all.sh", args, { timeout: 300_000 }));
  },
);

// ── Tool 7: cm_project_add ──────────────────────────────────────────────────

server.registerTool(
  "cm_project_add",
  {
    title: "Project Board: Add Item",
    description:
      "Add a GitHub issue or PR to the CM project board by URL. " +
      "If the item is already on the board, returns its existing item ID.",
    inputSchema: {
      url: z.string().describe("GitHub issue or PR URL"),
    },
  },
  async ({ url }) => {
    validateGhUrl(url);
    const args = ["--url", url];
    return reply(await runScript("project-board.sh", args, { timeout: 30_000 }));
  },
);

// ── Tool 8: cm_project_status ───────────────────────────────────────────────

server.registerTool(
  "cm_project_status",
  {
    title: "Project Board: Update Status",
    description:
      "Update the status of an item on the CM project board. " +
      "Identify the item by GitHub URL or project-board item ID. " +
      "Valid statuses are defined in .cm/project.json (e.g. Backlog, In Progress, Done).",
    inputSchema: {
      url: z.string().optional().describe("GitHub issue/PR URL (mutually exclusive with itemId)"),
      itemId: z.string().optional().describe("Project board item ID (mutually exclusive with url)"),
      status: z
        .string()
        .describe(
          "Target status (e.g. 'Backlog', 'In Progress', 'Done'). Valid values are defined in .cm/project.json.",
        ),
    },
  },
  async ({ url, itemId, status }) => {
    if (url) validateGhUrl(url);
    if (itemId && !/^[A-Za-z0-9+/=_-]+$/.test(itemId)) {
      return reply({ ok: false, tool: "project-board.sh", data: null, error: "Invalid item ID" });
    }
    if (!/^[A-Za-z0-9 ]+$/.test(status)) {
      return reply({
        ok: false,
        tool: "project-board.sh",
        data: null,
        error: "Invalid status characters",
      });
    }
    const args = [];
    if (url) args.push("--url", url);
    if (itemId) args.push("--item-id", itemId);
    args.push("--status", status);
    return reply(await runScript("project-board.sh", args, { timeout: 30_000 }));
  },
);

// ── Connect transport ────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
log("Server started (stdio transport)");
