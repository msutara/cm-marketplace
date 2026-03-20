---
name: cm-pr-lifecycle
description: >
  Full PR lifecycle management for the Config Manager project. Orchestrates the
  entire flow from local validation through fleet review, commit, push, PR
  creation, project board updates, CI monitoring, comment triage, and merge.
  Enforces the strict cm development workflow across all 5 Go repos with
  mandatory safety gates at every irreversible step.
triggers:
  - "create pr"
  - "submit pr"
  - "pr workflow"
  - "push and pr"
  - "cm pr"
  - "full pr cycle"
  - "run pr workflow"
  - "pr lifecycle"
  - "submit changes"
repos:
  - name: config-manager-core
    path: C:\Users\marius\repo\config-manager-core
    owner: msutara
  - name: cm-plugin-network
    path: C:\Users\marius\repo\cm-plugin-network
    owner: msutara
  - name: cm-plugin-update
    path: C:\Users\marius\repo\cm-plugin-update
    owner: msutara
  - name: config-manager-tui
    path: C:\Users\marius\repo\config-manager-tui
    owner: msutara
  - name: config-manager-web
    path: C:\Users\marius\repo\config-manager-web
    owner: msutara
github_project:
  id: PVT_kwHOAgHix84BPSxN
  status_field_id: PVTSSF_lAHOAgHix84BPSxNzg9vkrk
  in_progress_option: 47fc9ee4
  review_option: e70217cf
  done_option: "98236657"
---

# CM PR Lifecycle

End-to-end PR lifecycle management for the Config Manager project. Drives every
change through the full validation pipeline — build, test, lint, fleet review,
fix loop, staged diff approval, commit, push, PR creation, project board update,
CI monitoring, comment resolution, and merge — with mandatory user approval gates
before every irreversible action.

---

## Input

| Parameter | Required | Source | Description |
| --- | --- | --- | --- |
| Repo | Yes | Auto-detect from `cwd` | One of the 5 cm repos |
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

```powershell
go build ./...
go test ./...
golangci-lint run
```

If any markdown files changed:

```powershell
markdownlint-cli2 "**/*.md" "#node_modules"
```

**If any gate fails** → fix the issue and re-run all gates from the top.

### Phase 2 — Fleet Review

Invoke the `cm-fleet-review` skill (or replicate its protocol):

1. Launch **10 parallel review agents** with diverse models
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

```powershell
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

```powershell
git push origin {branch-name}
```

If the branch does not exist on the remote, use:

```powershell
git push -u origin {branch-name}
```

### Phase 7 — Create PR

Create the pull request via `gh` CLI:

```powershell
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
- ✅ Fleet review (10 agents) — clean

## Test Coverage

{Note on test coverage for new/changed code}
```

### Phase 8 — Project Board

Add the PR to the GitHub project and set status to **Review**:

```powershell
gh project item-add 1 --owner msutara --url {PR_URL}
```

Then update the item status to Review using the GraphQL API:

```powershell
gh api graphql -f query='
  mutation {
    updateProjectV2ItemFieldValue(
      input: {
        projectId: "PVT_kwHOAgHix84BPSxN"
        itemId: "{ITEM_ID}"
        fieldId: "PVTSSF_lAHOAgHix84BPSxNzg9vkrk"
        value: { singleSelectOptionId: "e70217cf" }
      }
    ) { projectV2Item { id } }
  }'
```

### Phase 9 — Monitor CI

Check CI status after push:

```powershell
gh pr checks {PR_NUMBER}
```

- ✅ All checks pass → proceed to Phase 10 (or wait for reviewer comments)
- ❌ Any check fails → diagnose the failure, fix, and return to **Phase 1**

Poll periodically if checks are still running. Do not proceed until all checks
have a final status.

### Phase 10 — Address PR Comments

Fetch PR comments:

```powershell
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

```powershell
gh pr merge {PR_NUMBER} --squash --delete-branch
```

Post-merge cleanup:

```powershell
# Update project board status to Done
gh api graphql -f query='
  mutation {
    updateProjectV2ItemFieldValue(
      input: {
        projectId: "PVT_kwHOAgHix84BPSxN"
        itemId: "{ITEM_ID}"
        fieldId: "PVTSSF_lAHOAgHix84BPSxNzg9vkrk"
        value: { singleSelectOptionId: "98236657" }
      }
    ) { projectV2Item { id } }
  }'

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
| 2. Fleet Review | 10-agent review, filter ≥ 80 confidence | ✅ Yes |
| 3. Fleet Fix Loop | iterate until clean | ✅ Yes |
| 4. Stage and Review | **user approval required** | ✅ Yes |
| 5. Commit | conventional commit + trailer | ⚠️ Amend only |
| 6. Push | feature branch only, never main | ⚠️ Force-push only |
| 7. Create PR | gh pr create | ⚠️ Close to undo |
| 8. Project Board | set status to Review | ✅ Yes |
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
