---
name: cm-fleet-review
description: >
  11-agent multi-perspective code review fleet for the Config Manager project.
  Launches parallel review agents with diverse AI models, each with a specific
  role and mandatory checklist. This is the core quality gate for cm.
  USE FOR: fleet review, run fleet, multi-model review, 11 agent review,
  cm review, code review fleet, review changes, run code review,
  multi-perspective review, launch fleet.
---

# CM Fleet Review

Orchestrates an 11-agent parallel code review using diverse AI models, each with
a specific role and mandatory checklist. This is THE core quality gate for the
Config Manager project.

Every agent reviews the **full changed files** (not just diffs) to catch
inconsistencies, stale comments, and cross-file issues. Model diversity across
4 Claude + 6 GPT + 1 Gemini variants maximizes perspective coverage.

---

## Agent Roster

### Group A — General Perspectives

| # | Role | Model | Focus |
| --- | --- | --- | --- |
| 1 | Architect/Designer | claude-opus-4.6 | SOLID, layering, coupling, abstraction, API shape |
| 2 | Correctness/Edge Cases | gpt-5.1-codex | Logic bugs, off-by-one, nil/empty, error handling, boundary analysis |
| 3 | Security Overview | gpt-5.3-codex | Auth, injection, access control, data exposure |
| 4 | Test Coverage | claude-sonnet-4.5 | Missing tests, assertion quality, coverage gaps |
| 5 | Operational/Deploy | gemini-3-pro-preview | Config, logging, graceful degradation, observability |

### Group B — Specialized Checklists

| # | Role | Model | Focus |
| --- | --- | --- | --- |
| 6 | Deep Security | claude-sonnet-4.6 | Path traversal, URL normalization, sanitization trace, template injection |
| 7 | Unicode/Encoding | gpt-5.2-codex | C0/C1 control chars, multi-byte rune handling, UTF-8 edge cases |
| 8 | Test Quality | gpt-5.1-codex-max | Flaky patterns, httptest usage, error path testing, test isolation |
| 9 | Lint/Consistency | claude-sonnet-4 | errcheck, nolint justifications, DRY violations, import consistency |
| 10 | Template/Contract | gpt-5.1 | URL generation, type mismatches, error propagation, display consistency |

### Group C — Platform Reviewer Simulation

| # | Role | Model | Focus |
| --- | --- | --- | --- |
| 11 | GitHub Copilot Perspective | gpt-5.4 | Simulates GitHub's Copilot auto-reviewer. **Key behavior: Copilot checks if patterns fixed in the diff exist unfixed in other files** — this is its primary comment source. Also checks: unvalidated external inputs, missing existence guards, defensive coding gaps (unchecked return values, empty vars in paths, unquoted vars), inconsistent patterns across files, stale docs/comments/counts, regex consistency, UUOC, error output to stderr, path traversal via `.`/`..`. Every value from JSON/env/user input must be validated. Every file/dir access must be guarded. |

---

## Mandatory Checklists

These checklists are **mandatory** — each agent MUST work through every checkbox
in its assigned checklist. Do not skip items.

### Agent 2 — Correctness/Edge Cases

```text
□ Boundary values: min, max, min-1, max+1 for every numeric input
□ Alias/normalization values: inputs that map to other values — tested before AND after normalization
□ Normalization ordering: does validation happen before or after input transformation
□ Boundary combinations: boundary/alias values combined with other parameters
□ Off-by-one in loops: <= vs <, starting index, step arithmetic, fence-post errors
□ Empty/zero/nil: every code path handles these explicitly
□ Error paths: every error return tested, unreachable error branches
□ Integer overflow/underflow: can arithmetic on user inputs wrap
□ State mutation ordering: does the order of field updates matter
```

### Agent 6 — Deep Security

```text
□ Every URL/path reaching a template or browser: can browser normalize /../ to hit unintended routes
□ Every API field displayed in UI: sanitized before rendering (trace data flow)
□ Every user-controlled path segment: validated against traversal
□ POST endpoint paths: validated before embedding in template URLs
□ Double-encoding: can %252e%252e bypass single-decode checks
□ Control characters in API responses: stripped before display
□ Error messages: do they leak internal paths, stack traces, secrets
□ HTTP headers: user-controlled values reflected without sanitization
```

### Agent 7 — Unicode/Encoding

```text
□ Every rune/character filter: handles Unicode C1 control chars (U+0080–U+009F)
□ Every string truncation: rune-aware (not byte-aware)
□ Every titleCase/uppercase: uses unicode.ToUpper + utf8.DecodeRuneInString
□ Multi-byte characters at truncation boundaries: no partial runes
□ String vs []byte conversions: any unnecessary allocations
□ URL encoding/decoding: handles non-ASCII paths correctly
□ JSON marshaling: preserves Unicode characters
```

### Agent 8 — Test Quality

```text
□ Error path tests: use closed httptest.Server (not hardcoded ports)
□ Flaky patterns: timing-dependent assertions, race conditions in parallel tests
□ Test isolation: each test creates own server/client
□ Assertion strength: error messages checked (not just err != nil)
□ Edge case coverage: empty input, nil, max-length, Unicode, concurrent access
□ Mock fidelity: mocks match real API behavior
□ Cleanup: httptest servers closed in defer
□ Table-driven tests: could similar test cases be consolidated
```

### Agent 9 — Lint/Consistency

```text
□ errcheck: every error return checked or nolint with justification
□ Param naming: matches usage
□ DRY: logic duplicated across 2+ functions
□ Import consistency: same packages imported same way
□ File ordering: generic/shared FIRST, then specific
□ Exported vs unexported: correct visibility
□ nolint directives: each has justification
□ Comment accuracy: describes what code actually does
□ Consistent error wrapping: fmt.Errorf with %w
```

### Agent 10 — Template/Contract

```text
□ Every URL in templates: correct prefix, no double slashes
□ Type safety: specific types not any/interface{}
□ Error propagation: errors from API surfaced to user
□ Display consistency: same data formatted same way
□ API field naming: matches backend json tags
□ Content-Type handling: JSON parsed as JSON
□ HTTP method correctness: GET for reads, POST for mutations
□ Status code handling: non-2xx produces user-visible errors
□ PR description: matches actual implementation
```

### Agent 11 — GitHub Copilot Perspective

```text
□ Fix propagation: for every pattern changed in the diff, check if the OLD
  pattern exists UNFIXED in any other file. Copilot reviews full files and
  cross-references what was fixed against what remains — this is its #1 source
  of comments.
□ Regex consistency: same input type must use same regex across all scripts
  (e.g., repo names validated identically in load-project.sh, init-project.sh,
  repo-status.sh)
□ Path traversal: every input used as a path segment rejects literal "." and
  ".." (dot-prefixed names like `.github` are valid)
□ Error output: every error-path echo uses "Error:" prefix + >&2
□ UUOC: no cat file | command — use $(<file) or direct argument
□ Manifest snippets: identical 5-line cascade (header + 4 checks with inline comments) in every skill/agent
□ Comment/wording: same pattern = same words across all files
□ Stale docs: counts, descriptions, examples match actual implementation
□ Unquoted $() assignments: must be VAR="$(...)" for space safety
□ Hardcoded values: status names, repo names, owner names should be
  manifest-driven or use placeholders
□ Else branches: error messages to stderr, consistent wording, exit on required
  paths
□ Script paths in skills: repo-root-relative, not cwd-relative
□ Usage/help text: hardcoded examples must match dynamic behavior. If a script
  reads statuses from manifest, usage text must not list fixed statuses.
□ Overly restrictive guards: validation must not block legitimate input. E.g.,
  a ".." check must not reject repo paths like "../sibling-repo". Test guards
  against real-world values.
□ CI workflow safety: every cd in CI must be in a subshell or use || exit 1 to
  propagate failures. Grep exit code 2 must not be silently swallowed.
□ Action versions: actions/checkout, setup-go, markdownlint-cli2-action — must
  be consistent across ci.yml, skills, and scaffold templates.
□ Untrimmed user input: EVERY read -rp value must be trimmed before validation.
  Whitespace-only input must be treated as empty.
□ Error message vs regex mismatch: if validation uses ^[A-Za-z0-9]..., the
  error message must describe that exact pattern, not a different one.
□ Mutually exclusive args: if --url and --item-id cannot coexist, the script
  must reject both being set — not silently prefer one.
□ Tilde expansion: ~ does not expand inside quotes or variable assignment. If
  user input may contain ~/path, handle expansion explicitly (e.g., substring
  check for ~/ prefix and replace with $HOME).
□ Manifest-missing exit: if a code path requires manifest data and the manifest
  is absent, it must exit 1 or return error — never silently fall through or
  continue with empty values.
```

---

Each agent receives this prompt with its role, checklist, and file contents
injected. The template MUST be used verbatim — do not paraphrase or abbreviate.

```text
You are reviewing a Go codebase change for [{REPO}].
Branch: {BRANCH} (PR #{PR_NUMBER})

ROLE: {ROLE_NAME}
PERSPECTIVE: {ROLE_DESCRIPTION}

REVIEW THE FULL FILES (not just diffs) — catch inconsistencies, stale comments, cross-file issues.

{CHECKLIST}

RULES:
- Only flag issues in code MODIFIED by this PR (not pre-existing)
- Score each finding 0-100 confidence
- Only report findings with confidence >= 75
- Be specific: file, line number, what's wrong, how to fix
- Do NOT flag: formatting, style preferences, things linters catch
- Do NOT suggest: over-engineering, premature abstraction, YAGNI changes

FILES TO REVIEW:
{FILE_CONTENTS}

Report findings as:
### [{SEVERITY}] {Title} (Confidence: {score})
- **File**: `{file}:{line}`
- **Issue**: {description}
- **Fix**: {concrete suggestion}

If no issues found, report: "✅ Clean — no issues found from {ROLE_NAME} perspective."
```

---

## Execution Protocol

### Step 1 — Auto-detect context

Determine the repo name, path, and branch automatically from the working
directory. Then collect the set of changed files.

```text
1. Repo name and path: infer from cwd
2. Current branch: git branch --show-current
3. Changed files (pick the first that returns results):
   a. git diff --name-only main...HEAD        (branch vs main)
   b. git diff --name-only --staged           (staged changes)
   c. git diff --name-only                    (unstaged changes)
4. Read full content of every changed file
```

### Step 2 — Determine iteration mode

- **First iteration** (default, or explicitly requested): review FULL changed
  files. All 11 agents run.
- **Targeted iteration** (after fixing findings from a previous run): review
  only the diff since the last commit. Only launch agents whose roles are
  relevant to the files/findings that changed.

Ask the user which mode to use if unclear. Default to first iteration.

### Step 3 — Launch agents

Launch ALL 11 agents **in parallel** using the `task` tool with
`mode: "background"`. Each agent uses its assigned model via the `model`
parameter.

```text
Agent  1: task(agent_type="code-review", model="claude-opus-4.6",      prompt=<template with Architect role>)
Agent  2: task(agent_type="code-review", model="gpt-5.1-codex",        prompt=<template with Correctness role>)
Agent  3: task(agent_type="code-review", model="gpt-5.3-codex",        prompt=<template with Security Overview role>)
Agent  4: task(agent_type="code-review", model="claude-sonnet-4.5",    prompt=<template with Test Coverage role>)
Agent  5: task(agent_type="code-review", model="gemini-3-pro-preview", prompt=<template with Operational role>)
Agent  6: task(agent_type="code-review", model="claude-sonnet-4.6",    prompt=<template with Deep Security role>)
Agent  7: task(agent_type="code-review", model="gpt-5.2-codex",        prompt=<template with Unicode role>)
Agent  8: task(agent_type="code-review", model="gpt-5.1-codex-max",    prompt=<template with Test Quality role>)
Agent  9: task(agent_type="code-review", model="claude-sonnet-4",      prompt=<template with Lint role>)
Agent 10: task(agent_type="code-review", model="gpt-5.1",              prompt=<template with Template/Contract role>)
Agent 11: task(agent_type="code-review", model="gpt-5.4",              prompt=<template with GitHub Copilot Perspective role>)
```

### Step 4 — Collect and triage

As agents complete, read their results with `read_agent`. Then:

1. **Group** findings by severity: CRITICAL > HIGH > MEDIUM > LOW
2. **Deduplicate** — same file+line flagged by multiple agents counts once
   (list all agents that flagged it)
3. **Filter** — only surface findings with confidence >= 80
4. **Cross-reference** — if two or more agents flag the same area, escalate
   severity by one level

### Step 5 — Report

Output findings grouped by file, then by severity within each file.

```text
## Fleet Review Results — {REPO} ({BRANCH})

### Summary
- Agents reporting clean: X/11
- Total findings: Y (Z critical, W high, ...)
- Files reviewed: N

### Findings

#### `path/to/file.go`

##### [CRITICAL] Title (Confidence: 95)
- **Agents**: #2 Correctness, #6 Deep Security
- **Line**: 42
- **Issue**: description
- **Fix**: concrete suggestion

...

### Verdict
✅ Fleet review clean — ready to commit
   — or —
❌ N findings require attention before commit
```

---

## Agent Configuration Reference

Quick-reference table for programmatic agent launch.

| # | Agent Name | Model ID | Checklist |
| --- | --- | --- | --- |
| 1 | architect | claude-opus-4.6 | (general review) |
| 2 | correctness | gpt-5.1-codex | Correctness/Edge Cases |
| 3 | security-overview | gpt-5.3-codex | (general review) |
| 4 | test-coverage | claude-sonnet-4.5 | (general review) |
| 5 | operational | gemini-3-pro-preview | (general review) |
| 6 | deep-security | claude-sonnet-4.6 | Deep Security |
| 7 | unicode | gpt-5.2-codex | Unicode/Encoding |
| 8 | test-quality | gpt-5.1-codex-max | Test Quality |
| 9 | lint | claude-sonnet-4 | Lint/Consistency |
| 10 | template-contract | gpt-5.1 | Template/Contract |
| 11 | copilot-perspective | gpt-5.4 | GitHub Copilot Perspective |

---

## Model Diversity

The fleet uses 11 distinct models across 3 providers to maximize perspective
diversity and minimize shared blind spots:

- **Claude** (4 agents): opus-4.6, sonnet-4.6, sonnet-4.5, sonnet-4
- **GPT** (6 agents): 5.1-codex, 5.3-codex, 5.2-codex, 5.1-codex-max, 5.1, 5.4
- **Gemini** (1 agent): 3-pro-preview

No two agents in Group B share the same model.

---

## Iteration Workflow

```text
┌─────────────────────────────────────────┐
│  1. Run fleet review (all 11 agents)    │
│  2. Fix findings                        │
│  3. PROPAGATE fixes repo-wide           │
│  4. Build + test                        │
│  5. Run targeted fleet review           │
│     (only relevant agents, diff only)   │
│  6. If findings remain → go to 2        │
│  7. If clean → commit + push            │
└─────────────────────────────────────────┘
```

Repeat until the fleet reports clean. Only then proceed to commit.

### Step 3 — Fix Propagation (MANDATORY)

After fixing ANY finding, you MUST sweep the entire repo for the same pattern
class before moving on. **Never fix one instance and leave others.**

**Pattern sweep rules:**

1. **Regex fix** → grep ALL regex validations in ALL scripts. Same input type =
   same regex. All path-segment inputs must reject literal `.` and `..`
   (dot-prefixed names like `.github` are valid).
2. **Error message fix** → grep ALL `echo` calls on error paths. Ensure: `Error:`
   prefix, `>&2`, consistent wording.
3. **Code snippet fix** → grep ALL files containing that snippet. If a snippet
   appears in 8 files, fix all 8 — not just the one flagged.
4. **UUOC fix** (`cat file | X`) → grep ALL `$(cat` and `cat.*|` patterns
   repo-wide. Replace with `$(<file)` or direct arg.
5. **Path/traversal fix** → grep ALL inputs used as path segments. Validate
   every one.
6. **Stderr fix** → grep ALL error-path `echo` calls. Every one must use `>&2`.
7. **Comment/wording fix** → grep for the old wording repo-wide. Update every
   instance.

**Scope:** scripts, skills, agents, docs, CI — not just the file type flagged.

**Verification:** After propagation, run a consistency audit:

- Manifest discovery snippets identical everywhere
- Regex patterns consistent for same input types
- Error message format standardized
- Placeholder syntax consistent ({X} not $X or \<X\>)
- Script paths repo-root-relative in skills

---

## Trigger Phrases

This skill activates for any of the following phrases:

- "fleet review"
- "run fleet"
- "multi-model review"
- "11 agent review"
- "cm review"
- "code review fleet"
- "review changes"
- "run code review"
- "multi-perspective review"
- "launch fleet"

---

## Important Notes

- The checklists are **MANDATORY** — agents MUST work through every checkbox.
  Skipping checklist items defeats the purpose of the fleet.
- **First iteration** always reviews full files, not just diffs. This catches
  stale comments, doc/code mismatches, and cross-file inconsistencies.
- **Subsequent iterations**: ask the user whether to do full-file or diff-only
  review. Let the user decide the review depth.
- Model diversity is critical. Do not substitute models unless the specified
  model is unavailable.
- Only surface findings with confidence >= 80. Lower-confidence findings create
  noise and slow down the review cycle.
- Deduplicate across agents — if multiple agents flag the same line, report it
  once and list all flagging agents.
- This skill is the **pre-push quality gate**. Never push without a clean fleet
  review unless the user explicitly approves skipping.

---

## Severity Definitions

Use these severity levels consistently across all agents:

| Severity | Meaning | Action |
| --- | --- | --- |
| CRITICAL | Bug that will cause runtime failure, data loss, or security vulnerability | Must fix before commit |
| HIGH | Logic error, missing error handling, or significant test gap | Must fix before commit |
| MEDIUM | Code quality issue that increases maintenance burden or risk | Should fix; discuss if unsure |
| LOW | Minor improvement, readability, or optional refactor | Fix if convenient; safe to defer |

---

## Cross-Agent Escalation Rules

When multiple agents independently flag the same area of code, escalate:

- **2 agents** flag same file+line → escalate severity by one level
- **3+ agents** flag same file+line → escalate to CRITICAL regardless
- **Security + Correctness** overlap → always treat as CRITICAL
- **Unicode + Security** overlap → always treat as CRITICAL (encoding attacks)

---

## Error Handling

If an agent fails to complete (model timeout, rate limit, etc.):

1. Log which agent failed and the error reason
2. Do NOT block the review — report results from the agents that completed
3. Note in the summary which agents did not finish
4. Offer to re-run only the failed agents

If fewer than 7 agents complete successfully, warn the user that coverage is
degraded and recommend a re-run before committing.

---

## File Scope Rules

Not every file type needs all 11 agents. Use these rules to skip irrelevant
agents and save tokens:

| File Pattern | Skip Agents |
| --- | --- |
| `*_test.go` | #5 Operational, #10 Template/Contract |
| `*.md`, `*.txt` | #2 Correctness, #7 Unicode, #8 Test Quality |
| `go.mod`, `go.sum` | All except #9 Lint/Consistency |
| `*.tmpl`, `*.html` | #2 Correctness, #8 Test Quality |
| `Makefile`, `Dockerfile` | #7 Unicode, #10 Template/Contract |

When a skip rule applies, note it in the summary so the user knows why an
agent was not launched for a particular file.
