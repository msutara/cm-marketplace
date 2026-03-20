# CM Marketplace — Code Review

Generated: 2026-03-20 · Repository: `msutara/cm-marketplace` · Version: `1.0.0`

---

## How to Use This Document

This document is structured for use by external AI coding agents. Each issue
includes:

- A unique **Issue ID** for tracking
- The **file path(s)** affected with line numbers where applicable
- A **severity** rating (High / Medium / Low)
- A **root cause** description
- An **exact fix** showing the old code and replacement

Work through issues in descending severity order. Each fix is independent
unless a dependency is noted. After applying all fixes, run
`markdownlint-cli2 "**/*.md" "#node_modules"` from the repo root to confirm
no new markdown violations were introduced.

---

## Summary

| ID | Severity | File(s) | Title |
| --- | --- | --- | --- |
| [H1](#h1-double-pop-location-corrupts-working-directory) | High | `tag-all.ps1` | Double `Pop-Location` corrupts working directory |
| [H2](#h2-markdownlint-cli2-arguments-passed-with-embedded-quotes) | High | `validate-repo.ps1` | markdownlint-cli2 arguments include stray double quotes |
| [H3](#h3-hardcoded-developer-path-in-four-scripts) | High | 4 scripts | Hardcoded `C:\Users\marius\repo` prevents portability |
| [M1](#m1-model-diversity-counts-are-wrong-in-cm-fleet-reviewskillmd) | Medium | `cm-fleet-review/SKILL.md` | Model-diversity counts off by one (9→10, 3→4 Claude) |
| [M2](#m2-inconsistent-frontmatter-trigger-key-in-cm-parity-checkskillmd) | Medium | `cm-parity-check/SKILL.md` | `trigger_phrases` should be `triggers` for consistency |
| [M3](#m3-cm-fleet-reviewskillmd-missing-triggers-frontmatter-key) | Medium | `cm-fleet-review/SKILL.md` | `triggers:` frontmatter key absent |
| [M4](#m4-module-self-exclusion-check-is-a-substring-match-in-sync-depsps1) | Medium | `sync-deps.ps1` | Self-exclusion uses substring match, not exact match |
| [M5](#m5-temp-files-never-cleaned-up-in-validate-repops1) | Medium | `validate-repo.ps1` | Temp output files accumulate and are never removed |
| [M6](#m6-pluginjson-missing-agents-field) | Medium | `plugin.json` | `plugin.json` missing `agents` field |
| [L1](#l1-gitignore-contains-python-and-unrelated-entries) | Low | `.gitignore` | Python and unrelated entries in `.gitignore` |
| [L2](#l2-validate-allps1-and-repo-statusps1--repobase-not-exposed-as-optional-parameter) | Low | `validate-all.ps1` `repo-status.ps1` | `$repoBase` not exposed as an optional parameter |
| [L3](#l3-contributingmd-plugin-manifest-template-missing-agents-field) | Low | `CONTRIBUTING.md` | Plugin manifest template missing `agents` field |

---

## High Severity

---

### H1: Double `Pop-Location` corrupts working directory

**File:** `plugins/cm-dev-tools/scripts/tag-all.ps1`
**Lines:** 49, 57, 69, 75 (inside `try` block) and 82 (inside `finally` block)

#### Root Cause

`Push-Location` is called at line 43 and the matching `Pop-Location` is in the
`finally` block at line 82. In PowerShell, `finally` **always** executes when a
`try` block exits — including when `return` is used. The four early-return paths
each call `Pop-Location` before `return`, so the location stack is popped
**twice**: once explicitly and once by the `finally` block. The second pop
removes an unrelated entry from the stack, silently changing the working
directory to an unexpected location for all subsequent loop iterations.

#### Verification

Run the following snippet in PowerShell to confirm the behavior:

```powershell
Push-Location C:\Windows
try { Pop-Location; return } finally { Pop-Location }
# Result: working directory changes unexpectedly because the stack is over-popped
```

#### Fix

Remove the four redundant `Pop-Location` calls inside the `try` block. The
`finally` block handles cleanup for every exit path (normal, `return`, and
exception).

**`plugins/cm-dev-tools/scripts/tag-all.ps1` — remove lines 49, 57, 69, 75**

```diff
         if ($status) {
             Write-Error "$repo has uncommitted changes — aborting"
-            Pop-Location
             return
         }

         # Verify on main branch
         $branch = git branch --show-current 2>$null
         if ($branch -ne 'main') {
             Write-Error "$repo is on branch '$branch', not 'main' — aborting"
-            Pop-Location
             return
         }

         if ($DryRun) {
             Write-Output "[DRY RUN] Would tag $repo at $Version"
         }
         else {
             Write-Output "Tagging $repo at $Version..."
             git tag $Version 2>&1
             if ($LASTEXITCODE -ne 0) {
                 Write-Error "Failed to create tag $Version in $repo"
-                Pop-Location
                 return
             }
             git push origin $Version 2>&1
             if ($LASTEXITCODE -ne 0) {
                 Write-Error "Failed to push tag $Version in $repo"
-                Pop-Location
                 return
             }
```

After the fix, the `try/finally` block should look like:

```powershell
    Push-Location $path
    try {
        # Verify clean working tree
        $status = git status --porcelain 2>$null
        if ($status) {
            Write-Error "$repo has uncommitted changes — aborting"
            return
        }

        # Verify on main branch
        $branch = git branch --show-current 2>$null
        if ($branch -ne 'main') {
            Write-Error "$repo is on branch '$branch', not 'main' — aborting"
            return
        }

        if ($DryRun) {
            Write-Output "[DRY RUN] Would tag $repo at $Version"
        }
        else {
            Write-Output "Tagging $repo at $Version..."
            git tag $Version 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to create tag $Version in $repo"
                return
            }
            git push origin $Version 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to push tag $Version in $repo"
                return
            }
            Write-Output "  ✅ $repo tagged and pushed $Version"
        }
    }
    finally {
        Pop-Location
    }
```

---

### H2: markdownlint-cli2 arguments passed with embedded quotes

**File:** `plugins/cm-dev-tools/scripts/validate-repo.ps1`
**Line:** 74

#### Root Cause

```powershell
$mdStep = Run-Step -Name 'markdownlint' -Command 'markdownlint-cli2' -Args @('"**/*.md"', '"#node_modules"')
```

The `Run-Step` function passes arguments via `Start-Process -ArgumentList`.
With `Start-Process`, each array element is passed verbatim as a command-line
argument — there is no shell that strips surrounding quotes. The literal
characters `"**/*.md"` (including the double-quote characters) are received by
the process, not the bare glob `**/*.md`. Many CLIs treat a leading `"` as part
of the argument rather than a shell quoting construct, which causes
`markdownlint-cli2` to find no matching files and exit with a false success or
an unhelpful error.

#### Fix

Remove the embedded double quotes from each argument string.

**`plugins/cm-dev-tools/scripts/validate-repo.ps1`, line 74**

```diff
-        $mdStep = Run-Step -Name 'markdownlint' -Command 'markdownlint-cli2' -Args @('"**/*.md"', '"#node_modules"')
+        $mdStep = Run-Step -Name 'markdownlint' -Command 'markdownlint-cli2' -Args @('**/*.md', '#node_modules')
```

---

### H3: Hardcoded developer path in four scripts

**Files:**

| File | Line |
| --- | --- |
| `plugins/cm-dev-tools/scripts/repo-status.ps1` | 24 |
| `plugins/cm-dev-tools/scripts/sync-deps.ps1` | 22 |
| `plugins/cm-dev-tools/scripts/tag-all.ps1` | 27 |
| `plugins/cm-dev-tools/scripts/validate-all.ps1` | 25 |

#### Root Cause

Every script that needs to locate the five CM repositories hardcodes:

```powershell
$repoBase = 'C:\Users\marius\repo'
```

This path only works on the original developer's machine. Any other user who
installs the plugin cannot run these scripts without editing the source. The
path also encodes the developer's Windows username, which is a minor information
disclosure.

#### Fix

Expose `$RepoBase` as an **optional** parameter with the current path as the
default value. Users who clone repos to a different location override the
parameter; the developer's workflow continues unchanged.

**`plugins/cm-dev-tools/scripts/repo-status.ps1`** — replace the `param` block
and `$repoBase` assignment:

```diff
 param(
-    [string]$Repo
+    [string]$Repo,
+    [string]$RepoBase = 'C:\Users\marius\repo'
 )

-$repoBase = 'C:\Users\marius\repo'
```

Then replace every reference to `$repoBase` in the script with `$RepoBase`
(note the capital `B` to match the parameter name).

Apply the equivalent change to the other three scripts:

**`sync-deps.ps1`** — add `$RepoBase` parameter, remove inline assignment:

```diff
 param(
     [Parameter(Mandatory)]
     [string]$SourceModule,

     [Parameter(Mandatory)]
-    [string]$Version
+    [string]$Version,
+    [string]$RepoBase = 'C:\Users\marius\repo'
 )

-$repoBase = 'C:\Users\marius\repo'
```

Replace `$repoBase` → `$RepoBase` throughout the script body.

**`tag-all.ps1`** — add `$RepoBase` parameter, remove inline assignment:

```diff
 param(
     [Parameter(Mandatory)]
     [string]$Version,

-    [switch]$DryRun
+    [switch]$DryRun,
+    [string]$RepoBase = 'C:\Users\marius\repo'
 )

-$repoBase = 'C:\Users\marius\repo'
```

Replace `$repoBase` → `$RepoBase` throughout the script body.

**`validate-all.ps1`** — add `$RepoBase` parameter, remove inline assignment:

```diff
 param(
     [switch]$SkipLint,
-    [switch]$SkipMarkdown
+    [switch]$SkipMarkdown,
+    [string]$RepoBase = 'C:\Users\marius\repo'
 )

 $scriptDir = $PSScriptRoot
 $validateScript = Join-Path $scriptDir 'validate-repo.ps1'

 $repos = @( ... )

-$repoBase = 'C:\Users\marius\repo'
```

Replace `$repoBase` → `$RepoBase` throughout the script body.

Also update the `.SYNOPSIS`/`.DESCRIPTION` block of each affected script to
document the new `RepoBase` parameter, for example:

```powershell
.PARAMETER RepoBase
    Root directory containing the CM repos. Defaults to C:\Users\marius\repo.
    Override when repos are cloned to a different location.
```

---

## Medium Severity

---

### M1: Model-diversity counts are wrong in cm-fleet-review/SKILL.md

**File:** `plugins/cm-dev-tools/skills/cm-fleet-review/SKILL.md`
**Lines:** 19, 283, 286

#### Root Cause

The Agent Roster table lists **10 agents** each using a distinct model:

| Agent | Model | Provider |
| --- | --- | --- |
| 1 | claude-opus-4.6 | Claude |
| 2 | gpt-5.1-codex | GPT |
| 3 | gpt-5.3-codex | GPT |
| 4 | claude-sonnet-4.5 | Claude |
| 5 | gemini-3-pro-preview | Gemini |
| 6 | claude-sonnet-4.6 | Claude |
| 7 | gpt-5.2-codex | GPT |
| 8 | gpt-5.1-codex-max | GPT |
| 9 | claude-sonnet-4 | Claude |
| 10 | gpt-5.1 | GPT |

There are **4 Claude agents** (1, 4, 6, 9) and **10 distinct models** total.
Three places in the document state incorrect numbers.

#### Fix

**Line 19** — intro paragraph:

```diff
-Every agent reviews the **full changed files** (not just diffs) to catch
-inconsistencies, stale comments, and cross-file issues. Model diversity across
-3 Claude + 5 GPT + 1 Gemini variants maximizes perspective coverage.
+Every agent reviews the **full changed files** (not just diffs) to catch
+inconsistencies, stale comments, and cross-file issues. Model diversity across
+4 Claude + 5 GPT + 1 Gemini variants maximizes perspective coverage.
```

**Lines 283–287** — Model Diversity section:

```diff
-The fleet uses 9 distinct models across 3 providers to maximize perspective
+The fleet uses 10 distinct models across 3 providers to maximize perspective
 diversity and minimize shared blind spots:

-- **Claude** (3 agents): opus-4.6, sonnet-4.6, sonnet-4.5, sonnet-4
+- **Claude** (4 agents): opus-4.6, sonnet-4.6, sonnet-4.5, sonnet-4
 - **GPT** (5 agents): 5.1-codex, 5.3-codex, 5.2-codex, 5.1-codex-max, 5.1
 - **Gemini** (1 agent): 3-pro-preview
```

---

### M2: Inconsistent frontmatter trigger key in cm-parity-check/SKILL.md

**File:** `plugins/cm-dev-tools/skills/cm-parity-check/SKILL.md`
**Line:** 7

#### Root Cause

Every other skill that lists trigger phrases uses the key `triggers:` in YAML
frontmatter. `cm-parity-check/SKILL.md` uses `trigger_phrases:` instead. If the
host runtime (Copilot CLI or Claude Code) discovers skills by reading the `triggers:`
key, it will not register any trigger phrases for this skill and the user will
not be able to activate it by the documented phrases.

```yaml
# cm-parity-check — WRONG key
trigger_phrases:
  - parity check
  ...

# all other skills — correct key
triggers:
  - parity check
  ...
```

#### Fix

**`plugins/cm-dev-tools/skills/cm-parity-check/SKILL.md`, line 7:**

```diff
-trigger_phrases:
+triggers:
```

---

### M3: cm-fleet-review/SKILL.md missing `triggers` frontmatter key

**File:** `plugins/cm-dev-tools/skills/cm-fleet-review/SKILL.md`

#### Root Cause

The frontmatter block for `cm-fleet-review` contains only `name` and
`description`. Unlike every other skill, it has no `triggers:` key. Trigger
phrases are documented only in the body under "Trigger Phrases". If the runtime
parses frontmatter to register skills, `cm-fleet-review` will not activate on
any trigger phrase.

Current frontmatter:

```yaml
---
name: cm-fleet-review
description: >
  10-agent multi-perspective code review fleet...
---
```

#### Fix

Add a `triggers:` key to the frontmatter using the phrases already documented
in the "Trigger Phrases" section of the document body:

```diff
 ---
 name: cm-fleet-review
 description: >
   10-agent multi-perspective code review fleet for the Config Manager project.
   Launches parallel review agents with diverse AI models, each with a specific
   role and mandatory checklist. This is the core quality gate for cm.
   USE FOR: fleet review, run fleet, multi-model review, 10 agent review,
   cm review, code review fleet, review changes, run code review,
   multi-perspective review, launch fleet.
+triggers:
+  - "fleet review"
+  - "run fleet"
+  - "multi-model review"
+  - "10 agent review"
+  - "cm review"
+  - "code review fleet"
+  - "review changes"
+  - "run code review"
+  - "multi-perspective review"
+  - "launch fleet"
 ---
```

---

### M4: Module self-exclusion check is a substring match in sync-deps.ps1

**File:** `plugins/cm-dev-tools/scripts/sync-deps.ps1`
**Line:** 47

#### Root Cause

The script is supposed to skip updating a repo's own dependency on itself.
The self-exclusion check is:

```powershell
$moduleLine = ($content -split "`n" | Where-Object { $_ -match '^module ' })[0]
if ($moduleLine -match [regex]::Escape($SourceModule)) { continue }
```

The PowerShell `-match` operator tests whether the right-hand side appears
**anywhere** in the left-hand string. If `$SourceModule` is
`github.com/msutara/config-manager-core`, this test will also skip a module
whose declaration line is:

```text
module github.com/msutara/config-manager-core-extended
```

because `config-manager-core` is a substring of `config-manager-core-extended`.
The correct check extracts the module path from the declaration and compares it
for **equality**.

#### Fix

Replace the substring `-match` with an exact extraction and equality check:

```diff
-    # Skip self
-    $moduleLine = ($content -split "`n" | Where-Object { $_ -match '^module ' })[0]
-    if ($moduleLine -match [regex]::Escape($SourceModule)) { continue }
+    # Skip self — extract module path and compare exactly
+    $moduleLine = ($content -split "`n" | Where-Object { $_ -match '^module ' })[0]
+    $thisModule = ($moduleLine -replace '^module\s+', '').Trim()
+    if ($thisModule -eq $SourceModule) { continue }
```

---

### M5: Temp files never cleaned up in validate-repo.ps1

**File:** `plugins/cm-dev-tools/scripts/validate-repo.ps1`
**Lines:** 38–39

#### Root Cause

`Run-Step` redirects stdout and stderr to fixed-path temp files:

```powershell
-RedirectStandardOutput "$env:TEMP\cm-$Name-out.txt"
-RedirectStandardError  "$env:TEMP\cm-$Name-err.txt"
```

These files are read after the process exits but never deleted. Over repeated
validation runs the files accumulate in the temp directory. Additionally, if
two instances of `validate-all.ps1` are invoked simultaneously (unlikely but
possible), they would share the same file names and corrupt each other's output
because `$Name` only varies between `build`, `test`, `lint`, and `markdownlint`
— not between repos.

#### Fix

Use a unique temp name per invocation (incorporate `[System.IO.Path]::GetRandomFileName()`)
and delete the files in a `finally` block inside `Run-Step`:

```diff
 function Run-Step {
     param([string]$Name, [string]$Command, [string[]]$Args)
     $step = @{ name = $Name; success = $false; output = ''; duration = '' }
     $sw = [System.Diagnostics.Stopwatch]::StartNew()
+    $outFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "cm-$Name-$([System.IO.Path]::GetRandomFileName())-out.txt")
+    $errFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "cm-$Name-$([System.IO.Path]::GetRandomFileName())-err.txt")
     try {
         $proc = Start-Process -FilePath $Command -ArgumentList $Args -WorkingDirectory $RepoPath `
-            -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\cm-$Name-out.txt" `
-            -RedirectStandardError "$env:TEMP\cm-$Name-err.txt"
-        $stdout = Get-Content "$env:TEMP\cm-$Name-out.txt" -Raw -ErrorAction SilentlyContinue
-        $stderr = Get-Content "$env:TEMP\cm-$Name-err.txt" -Raw -ErrorAction SilentlyContinue
+            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile `
+            -RedirectStandardError $errFile
+        $stdout = Get-Content $outFile -Raw -ErrorAction SilentlyContinue
+        $stderr = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
         $step.output = if ($stdout) { $stdout.Trim() } else { $stderr.Trim() }
         $step.success = $proc.ExitCode -eq 0
     }
     catch {
         $step.output = $_.Exception.Message
     }
+    finally {
+        Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
+    }
     $sw.Stop()
     $step.duration = "$([math]::Round($sw.Elapsed.TotalSeconds, 1))s"
     return $step
 }
```

---

### M6: plugin.json missing `agents` field

**File:** `plugins/cm-dev-tools/.claude-plugin/plugin.json`

#### Root Cause

The README and RELEASES.md document two custom agents shipped with `cm-dev-tools`
(CMDeveloper and CMReviewer). The plugin manifest `plugin.json` only declares
`name`, `version`, `description`, and `skills`. There is no `agents` field,
which may prevent the host runtime from discovering or installing the agents
when the plugin is installed.

Current manifest:

```json
{
  "name": "cm-dev-tools",
  "version": "1.0.0",
  "description": "...",
  "skills": "skills/"
}
```

#### Fix

Add an `agents` field pointing to the directory or listing the agent files.
If no agents directory exists yet, create `plugins/cm-dev-tools/agents/` and
add stub agent files, then register them:

```diff
 {
   "name": "cm-dev-tools",
   "version": "1.0.0",
   "description": "Config Manager development toolkit: 7 workflow skills (scaffold, fleet review, release, PR lifecycle, parity check, PR comments, docs sync) + PowerShell helper scripts + 2 custom agents. No external dependencies — uses built-in Copilot CLI agents and shell commands.",
-  "skills": "skills/"
+  "skills": "skills/",
+  "agents": "agents/"
 }
```

Create the agents directory with the two agent files referenced in the README
(`CMDeveloper.agent.md` and `CMReviewer.agent.md`) if they do not already exist.
The README's Contributing guide explains the agent file format.

---

## Low Severity

---

### L1: .gitignore contains Python and unrelated entries

**File:** `.gitignore`

#### Root Cause

The `.gitignore` file includes entries for Python byte-compiled files
(`*.pyc`, `*.pyo`, `__pycache__/`, `*.egg-info/`) and a generic `build/`
directory. This repository contains only PowerShell scripts and Markdown files;
Go builds happen in separate repos. The entries are harmless but add noise and
may mislead contributors about the stack.

#### Fix

Remove the irrelevant entries:

```diff
 node_modules/
-__pycache__/
-*.pyc
-*.pyo
-*.egg-info/
-build/
 .env
 .env.*
 .DS_Store
 Thumbs.db
 logs/
 reports/
 *.jsonl
```

---

### L2: validate-all.ps1 and repo-status.ps1 — $RepoBase not exposed as optional parameter

> **Note:** This is the companion documentation note to [H3](#h3-hardcoded-developer-path-in-four-scripts).
> The fix described in H3 is sufficient. This entry records the scope of
> affected files for completeness.

**Files:**

- `plugins/cm-dev-tools/scripts/validate-all.ps1` — `$repoBase` used at line 25, 30
- `plugins/cm-dev-tools/scripts/repo-status.ps1` — `$repoBase` used at line 24, 29

Both files must receive the same `[string]$RepoBase = 'C:\Users\marius\repo'`
parameter addition described in H3. The example in `validate-repo.ps1`'s help
block also references the hardcoded path and should be updated to use `{RepoBase}`
as a placeholder:

**`validate-repo.ps1`, line 14:**

```diff
-.EXAMPLE
-    .\validate-repo.ps1 -RepoPath "C:\Users\marius\repo\config-manager-core"
+.EXAMPLE
+    .\validate-repo.ps1 -RepoPath "C:\path\to\your\repos\config-manager-core"
```

---

### L3: CONTRIBUTING.md plugin manifest template missing `agents` field

**File:** `CONTRIBUTING.md`

#### Root Cause

The "Adding a New Plugin" section shows a template for `plugin.json` that
does not include the `agents` field, even though the shipped `cm-dev-tools`
plugin registers agents. New contributors following the guide will not know
to include agents in their manifests.

#### Fix

Update the template to show the optional `agents` field:

**Before** (`CONTRIBUTING.md`, "Create the plugin manifest" section):

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "What this plugin provides",
  "skills": "skills/"
}
```

**After:**

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "What this plugin provides",
  "skills": "skills/",
  "agents": "agents/"
}
```

Add a note below the template:

> The `agents` field is optional. Omit it if the plugin does not ship custom agents.

---

## Notes for Agents Applying These Fixes

1. **H1 and H3 are independent.** Apply them in either order.
2. **M6 and L3 are related** — once `plugin.json` gains the `agents` field,
   update `CONTRIBUTING.md` to match. Apply M6 first, then L3.
3. **M1 is documentation-only.** No functional code changes needed — update
   three text strings in one file.
4. **After all fixes**, run `markdownlint-cli2 "**/*.md" "#node_modules"` from
   the repo root to verify no markdown lint violations were introduced. The
   repo's `.markdownlint.json` configuration allows:
   - `MD013` (line length) — disabled
   - `MD024` (duplicate headings) — siblings-only mode
   - `MD033` (inline HTML) — `<br>` allowed
5. **Hardcoded GitHub project IDs** (e.g., `PVT_kwHOAgHix84BPSxN`,
   `PVTSSF_lAHOAgHix84BPSxNzg9vkrk`, and the status option hashes in
   `project-board.ps1` and several SKILL.md frontmatter blocks) are
   intentionally left out of this review. They are project-specific constants
   that only the repository owner can update and are clearly labelled as such in
   context. A future enhancement could make them configurable via a shared
   config file, but that is beyond the scope of this review.
