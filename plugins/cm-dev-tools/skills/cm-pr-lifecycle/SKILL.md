---
name: cm-pr-lifecycle
description: >
  Full PR lifecycle management for the Config Manager project. Orchestrates the
  entire flow from local validation through fleet review, commit, push, PR
  creation, project board updates, CI monitoring, comment triage, and merge.
  Enforces the strict cm development workflow across all CM Go repos with
  mandatory safety gates at every irreversible step.
  USE FOR: create pr, submit pr, pr workflow, push and pr, cm pr, full pr cycle,
  run pr workflow, pr lifecycle, submit changes.
---

# CM PR Lifecycle

End-to-end PR lifecycle management for the Config Manager project. Drives every
change through the full validation pipeline — build, test, lint, fleet review,
fix loop, staged diff approval, commit, push, PR creation, project board update,
CI monitoring, comment resolution, and merge — with mandatory user approval gates
before every irreversible action.

## Project Context

Read project context from `.cm/project.json` if available. Discovery order:
`$CM_REPO_BASE` → cwd → parent directory → `$HOME/repo`. If no manifest is found,
ask the user for the required values before proceeding.

```bash
# Discover project manifest: $CM_REPO_BASE → cwd → parent → $HOME/repo (optional — ask user for context if unavailable)
_cm="${CM_REPO_BASE:+$CM_REPO_BASE/.cm/project.json}"
[ -f "${_cm:-}" ] || _cm=".cm/project.json"          # cwd
[ -f "$_cm" ] || _cm="../.cm/project.json"            # parent dir
[ -f "$_cm" ] || _cm="$HOME/repo/.cm/project.json"   # fallback
if [ -f "$_cm" ]; then
  jq '.' "$_cm"
else
  echo "No manifest found — ask the user for owner, repo names, and other context."
fi
```

This provides: repo names, owner, paths (sibling repos under the manifest's parent directory), dependency order,
reference repo, and project board IDs (project ID, field IDs, status option IDs).
All values below are derived from the manifest.

---

## Input

| Parameter | Required | Source | Description |
| --- | --- | --- | --- |
| Repo | Yes | Auto-detect from `cwd` | Any CM repo listed in the manifest |
| Branch name | No | Auto-generate from title | Feature branch (never `main`) |
| PR title | Yes | User-provided | Conventional commit style |
| Issue number | No | User-provided | GitHub issue to close |

---

## Safety Rules

These rules are **permanent and non-negotiable**:

- ❌ **NEVER** push to `main` directly
- ❌ **NEVER** commit before user reviews staged changes
- ❌ **NEVER** merge without explicit user approval
- ❌ **NEVER** take irreversible actions autonomously
- ✅ **ALWAYS** include the `Co-authored-by` trailer
- ✅ **ALWAYS** run the full validation pipeline before pushing
- ⚠️ If admin bypass is used (pushing directly to main), the validation pipeline
  is **even more critical**

---

## Execution Protocol

### Phase 1 — Local Validation

Run all quality gates in the repo root. Every gate must pass before proceeding.

```bash
go build ./...
go test ./...
golangci-lint run
```

If any markdown files changed:

```bash
markdownlint-cli2 "**/*.md" "#node_modules"
```

**If any gate fails** → fix the issue and re-run all gates from the top.

### Phase 2 — Fleet Review

Invoke the `cm-fleet-review` skill (or replicate its protocol):

1. Launch **11 parallel review agents** with diverse models
2. Each agent reviews with its assigned perspective and mandatory checklist
3. Collect all findings
4. Filter to confidence **≥ 80**
5. If actionable findings exist → proceed to Phase 3
6. If clean → proceed to Phase 4

### Phase 3 — Fleet Fix Loop

Iterate until the fleet review is clean:

1. **Fix** all genuine findings (bugs, security gaps, missing coverage)
2. **Dismiss** false positives with documented reasoning
3. **Re-run Phase 1** (build + test + lint) — all gates must pass
4. **Re-run targeted fleet review** — only agents whose perspective is relevant
   to the changes made
5. **Repeat** until no actionable findings remain

### Phase 4 — Stage and Review

```bash
git add -A
git diff --staged
```

Present the staged diff to the user.

🔴 **STOP — wait for explicit user approval before committing.**

Do **not** proceed until the user confirms the diff is acceptable.

### Phase 5 — Commit

Commit with a conventional commit message:

```text
feat(plugin-name): short description

Longer description of what changed and why.

Closes #XX

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

Rules:

- Use the appropriate prefix: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`
- Scope should match the repo/component (e.g., `core`, `network`, `update`,
  `tui`, `web`)
- Always include the `Co-authored-by` trailer
- Reference the issue if provided (`Closes #XX`)

### Phase 6 — Push

Push to the feature branch. **Never push to `main`.**

```bash
git push origin {branch-name}
```

If the branch does not exist on the remote, use:

```bash
git push -u origin {branch-name}
```

### Phase 7 — Create PR

Create the pull request via `gh` CLI:

```bash
gh pr create --title "{title}" --body "{body}" --base main --head {branch-name}
```

The PR body must include:

- **Summary** — what changed and why
- **Issue reference** — `Closes #XX` (if applicable)
- **Test coverage** — confirmation that tests pass and cover the changes
- **Fleet review status** — confirmation that fleet review passed clean

Example body template:

```markdown
## Summary

{Description of changes}

## Related Issue

Closes #{issue_number}

## Validation

- ✅ `go build ./...` — pass
- ✅ `go test ./...` — pass
- ✅ `golangci-lint run` — pass
- ✅ Fleet review (11 agents) — clean

## Test Coverage

{Note on test coverage for new/changed code}
```

### Phase 8 — Project Board

Add the PR to the GitHub project and set its status to the value of
`.project_board.statuses.Review` from `.cm/project.json` (the status option ID
configured under the `Review` key):

```bash
gh project item-add {PROJECT_NUMBER} --owner {OWNER} --url {PR_URL}
```

Then update the item status to the review status defined in `.cm/project.json`
(from the marketplace repo root):

```bash
./plugins/cm-dev-tools/scripts/project-board.sh --url {PR_URL} --status {REVIEW_STATUS}
```

### Phase 9 — Monitor CI

Check CI status after push:

```bash
gh pr checks {PR_NUMBER}
```

- ✅ All checks pass → proceed to Phase 10 (or wait for reviewer comments)
- ❌ Any check fails → diagnose the failure, fix, and return to **Phase 1**

Poll periodically if checks are still running. Do not proceed until all checks
have a final status.

### Phase 10 — Address PR Comments

Fetch PR comments:

```bash
gh pr view {PR_NUMBER} --comments
```

For each comment thread:

| Commenter | Action |
| --- | --- |
| **Human reviewer** | Evaluate: fix the code **or** push back with reasoning |
| **Bot** (Copilot, etc.) | Check if already addressed; skip if resolved |

Risk assessment for fixes:

- **Trivially safe** (typo, string change, comment fix): ask user if skipping the
  full flow is OK, explain why it is safe. Let the user decide.
- **Any logic, concurrency, or structural change**: full **Phase 1–3** cycle
  (build → test → lint → fleet review → fix loop).

After fixing:

1. Push the fix
2. Resolve the comment thread
3. Re-check CI (Phase 9)

### Phase 11 — Merge

🔴 **STOP — NEVER merge without explicit user approval.**

When the user approves:

```bash
gh pr merge {PR_NUMBER} --squash --delete-branch
```

Post-merge cleanup:

```bash
# Update project board status to the completion status from .cm/project.json

# Prune stale remote refs
git remote update origin --prune

# Delete local feature branch
git checkout main
git pull origin main
git branch -d {branch-name}

# Verify clean working tree
git status
```

---

## Phase Summary

| Phase | Gate | Reversible |
| --- | --- | --- |
| 1. Local Validation | build + test + lint must pass | ✅ Yes |
| 2. Fleet Review | 11-agent review, filter ≥ 80 confidence | ✅ Yes |
| 3. Fleet Fix Loop | iterate until clean | ✅ Yes |
| 4. Stage and Review | **user approval required** | ✅ Yes |
| 5. Commit | conventional commit + trailer | ⚠️ Amend only |
| 6. Push | feature branch only, never main | ⚠️ Force-push only |
| 7. Create PR | gh pr create | ⚠️ Close to undo |
| 8. Project Board | set status from manifest | ✅ Yes |
| 9. Monitor CI | all checks must pass | ✅ Yes |
| 10. PR Comments | triage + fix + resolve threads | ✅ Yes |
| 11. Merge | **user approval required**, squash merge | ❌ No |

---

## Error Recovery

| Failure | Recovery |
| --- | --- |
| Build fails | Fix compilation errors, re-run Phase 1 |
| Tests fail | Fix failing tests, re-run Phase 1 |
| Lint fails | Fix lint violations, re-run Phase 1 |
| Fleet findings | Fix genuine issues, dismiss false positives, re-run Phase 1–2 |
| CI fails after push | Diagnose, fix locally, full Phase 1–3, push again |
| PR comment requires logic change | Full Phase 1–3 cycle, push, resolve thread |
| Merge conflict | Rebase onto `main`, re-run Phase 1, force-push branch |
