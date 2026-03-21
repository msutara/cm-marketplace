---
name: cm-parity-check
description: >
  Verify functional, security, test, and documentation parity between
  config-manager-tui (Bubble Tea terminal UI) and config-manager-web
  (htmx + Go templates web UI). Reports gaps without making changes.
  USE FOR: parity check, check parity, tui web sync, compare tui web,
  parity audit, ui parity, check ui parity, verify parity, parity report.
---

# TUI ↔ Web Parity Check

## Background

The Config Manager project enforces a **permanent parity rule**:

> config-manager-tui and config-manager-web MUST be kept functionally and
> test-wise identical.
>
> 1. Every feature implemented in one UI must exist in the other.
> 2. Every security pattern (sanitization, body limits, token masking, input
>    validation) must be applied identically in both.
> 3. Test coverage must match — same edge cases, same error paths, same
>    boundary conditions tested on both sides.
> 4. Documentation (README, CONTRIBUTING, API docs) must stay in sync.
> 5. When making changes to either UI, always check if the same change is
>    needed in the other.
> 6. This rule applies proactively: do not wait for a reviewer to find parity
>    gaps.

## Repos

| UI | Path | Stack |
| --- | --- | --- |
| TUI | `$CM_REPO_BASE/config-manager-tui` | Bubble Tea terminal UI |
| Web | `$CM_REPO_BASE/config-manager-web` | htmx + Go templates web UI |

## Procedure

Execute every step below **in order**. Do not skip steps.

### Step 1 — Inventory Features

Scan both repos and build a feature matrix.

**How to detect features:**

- **TUI:** scan `menu.go` for `MenuItem` definitions, scan `tui.go` for
  screen states, scan `views.go` for render functions.
- **Web:** scan `routes.go` for HTTP handlers, scan `templates/` for page
  templates, scan `web.go` for route registration.

Produce a table:

```markdown
| Feature | TUI | Web | Status |
| --- | --- | --- | --- |
| Dashboard / System Info | ✅ | ✅ | ✅ Parity |
| Update status view | ✅ | ✅ | ✅ Parity |
| Pending packages list | ✅ | ❌ | ⚠️ Gap |
| … | … | … | … |
```

Mark each row:

- **✅ Parity** — feature exists in both UIs.
- **⚠️ Gap** — feature exists in one UI but not the other.

### Step 2 — Inventory Security Patterns

Compare security implementations across both codebases.

| Pattern | TUI Location | Web Location | What to Check |
| --- | --- | --- | --- |
| Input sanitization (C0 + C1 control chars) | `menu.go:sanitizeText()` | `web.go:sanitizeForDisplay()` | Implementation logic matches |
| Body size limits | `apiclient.go:LimitReader` | `routes.go:http.MaxBytesReader` | Limit values are identical |
| Token masking in logs | `apiclient.go` | `web.go` | Masking pattern is identical |
| Path traversal prevention | `apiclient.go:cleanPluginPath` | `routes.go:cleanPluginPath` | Implementation logic matches |
| Error message sanitization | `menu.go:sanitizeBody()` | `routes.go` | Coverage is identical |

For each pattern, read the actual implementation in both repos and diff the
logic. Flag any divergence.

### Step 3 — Compare Test Coverage

For each feature identified in Step 1, locate the corresponding `*_test.go`
files in both repos and compare:

- **Edge cases** — empty input, nil, max-length strings, Unicode.
- **Error paths** — API unreachable, HTTP 403, 404, 500 responses.
- **Boundary conditions** — truncation, pagination, concurrent access.
- **Table-driven test consistency** — same test-case tables used on both sides.

Produce a per-feature comparison noting any test cases present in one repo but
missing from the other.

### Step 4 — Compare Documentation

Check the following files in both repos for content alignment:

| Document | What to Compare |
| --- | --- |
| `README.md` | Feature lists, badges, install instructions |
| `docs/USAGE.md` | Usage instructions, examples |
| `specs/SPEC.md` | Capability descriptions, supported operations |
| `CONTRIBUTING.md` | Contribution guidelines, development setup |

Flag any content that is present in one repo's docs but absent or contradictory
in the other.

### Step 5 — Generate Report

Compile all findings into a single report with this structure:

```markdown
# TUI ↔ Web Parity Report

## Summary

- ✅ Features in sync: X
- ⚠️ Feature gaps: Y
- 🔴 Security divergence: Z
- 📝 Doc mismatches: W

## Feature Gaps

### ⚠️ {Feature Name}

- **Present in:** TUI (`menu.go:L42`)
- **Missing from:** Web
- **Impact:** Medium — users on web cannot see {feature}
- **Suggested fix:** Add handler in `routes.go`, template in `templates/{name}.html`

## Security Divergence

### 🔴 {Pattern Name}

- **TUI implementation:** `sanitizeText()` strips C1 chars (U+0080–U+009F)
- **Web implementation:** Only strips ASCII controls (missing C1 range)
- **Risk:** Medium — C1 control chars could reach browser
- **Fix:** Update web sanitizer to match TUI

## Doc Mismatches

### 📝 {Doc Name}

- **TUI says:** "Supports 5 themes"
- **Web says:** "Supports 3 themes"
- **Fix:** Update web README

## Test Coverage Gaps

### 🧪 {Feature / File}

- **TUI tests:** 12 cases covering empty, nil, max-length, Unicode
- **Web tests:** 8 cases — missing nil and Unicode edge cases
- **Fix:** Add missing test cases to `web/{file}_test.go`
```

### Step 6 — Optionally Create Issues

Ask the user whether to create GitHub issues for each gap. If approved, run:

```bash
gh issue create --repo msutara/config-manager-web --title "Parity: Add {feature}" --body "{details}"
```

Create one issue per gap so they can be tracked and closed independently.

## Important Notes

- This skill **does not make changes** — it only reports gaps.
- The user decides which gaps to fix and in what order.
- Always scan **both** repos completely — neither is the "source of truth."
- Some intentional differences may exist (TUI has keyboard navigation, Web has
  mouse interaction) — flag these but do not treat them as bugs.
