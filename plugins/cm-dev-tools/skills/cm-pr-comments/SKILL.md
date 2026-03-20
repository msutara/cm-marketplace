---
name: cm-pr-comments
description: >
  Triage, categorize, and resolve PR review comments across all Config Manager
  repositories. Fetches open and closed threads, distinguishes human from bot
  feedback, assesses risk, presents a prioritized summary, and implements fixes
  with the full build → test → fleet-review cycle when required.
triggers:
  - check pr comments
  - triage comments
  - address review
  - pr feedback
  - resolve threads
  - review comments
  - pr comment triage
  - handle comments
  - fix pr comments
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
  review_status_option: e70217cf
---

# CM PR Comment Triage & Resolution

Systematic workflow for triaging and resolving PR review comments across all
Config Manager repositories.

## Step 1 — Fetch PR Comments

Retrieve **all** review threads for the target PR — both open and resolved.

### Open (unresolved) threads

```powershell
gh pr view {PR_NUMBER} --repo msutara/{repo} --json reviewThreads `
  --jq '.reviewThreads[] | select(.isResolved == false)'
```

### Closed (resolved) threads

Closed threads from human reviewers often contain valid suggestions that were
dismissed rather than implemented. Always inspect them.

```powershell
gh pr view {PR_NUMBER} --repo msutara/{repo} --json reviewThreads `
  --jq '.reviewThreads[] | select(.isResolved == true)'
```

## Step 2 — Categorize Comments

For every thread determine:

1. **Author type** — Human reviewer vs Bot (GitHub Copilot, Merlin, dependabot)
2. **Status** — Open (unresolved) vs Closed (resolved)
3. **Type** — Bug fix request, Style suggestion, Question, Security concern, Test request

Present the results as a table:

```markdown
| # | Author | Type  | Status | File:Line    | Summary                    |
| - | ------ | ----- | ------ | ------------ | -------------------------- |
| 1 | human  | bug   | open   | routes.go:42 | Missing nil check          |
| 2 | copilot| style | closed | web.go:15    | Rename variable            |
| 3 | human  | sec   | closed | auth.go:8    | Token not masked in logs   |
```

## Step 3 — Evaluate Each Comment

### Open human comments

- Read the full thread including any back-and-forth replies.
- Determine whether a code change is needed or pushback with reasoning is appropriate.
- If a code change is needed, assess risk:
  - **Trivially safe** (string change, typo, comment fix) → mark as *safe to quick-fix*.
  - **Logic / security / structural change** → mark as *full flow required*.

### Closed human comments

- Verify whether the suggestion was actually implemented or merely dismissed.
- If the improvement is valid and was **not** implemented, flag it for user consideration.
- **Never silently ignore a closed human comment.** Always present it to the user.

### Bot comments (open or closed)

- Check whether the issue is already addressed by existing code.
- If genuinely actionable → flag as needing a fix.
- If false positive → note as dismissible.

## Step 4 — Present Triage Summary

```markdown
## PR #{NUMBER} Comment Triage — {repo}

### 🔴 Must Fix (open, human, requires code change)

1. **routes.go:42** — Missing nil check before dereference
   - Risk: Logic change → full flow required
   - Suggested fix: Add `if resp == nil { return errNoResponse }` before L43

### 🟡 Consider (closed human, valid suggestion)

2. **auth.go:8** — Token visible in debug logs
   - Was closed but never implemented
   - Ask user: implement token masking?

### 🟢 Dismiss (bot, false positive, or already addressed)

3. **web.go:15** — Copilot suggested variable rename
   - Style-only, current name is fine

### Summary

- Must fix: 1 (1 full-flow, 0 quick-fix)
- Consider: 1
- Dismiss: 1
```

## Step 5 — Implement Fixes (with User Approval)

### Full-flow fixes

For every comment marked *full flow required*:

1. Implement the fix.
2. Build — ensure no compilation errors.
3. Test — run all tests, ensure passing.
4. Lint — run project linters.
5. Fleet review — launch 4–5 parallel code-review agents with varied models.
6. Address any fleet findings, then re-run steps 2–5.
7. Push to the **PR branch** (never to main).

### Quick fixes

For comments marked *safe to quick-fix*:

1. **Ask the user first** — explain why skipping the full flow is safe.
2. Implement the fix.
3. Build and test.
4. Push to the PR branch.

### Resolve the thread

After pushing a fix, resolve the corresponding review thread via GraphQL:

```powershell
$threadId = "{THREAD_NODE_ID}"
$mutation = "mutation { resolveReviewThread(input: {threadId: ""$threadId""}) { thread { isResolved } } }"
gh api graphql -f query=$mutation
```

## Step 6 — Handle Unresolvable Comments

If a comment cannot be addressed in this PR cycle:

1. Create a GitHub issue tracking the deferred work.
2. Add the issue to the project board as **Backlog**.

   ```powershell
   $itemId = gh project item-add PVT_kwHOAgHix84BPSxN --owner msutara --url {ISSUE_URL} --format json | ConvertFrom-Json | Select-Object -ExpandProperty id
   ```

3. Resolve the thread with a comment linking to the new issue.

   ```powershell
   gh api graphql -f query='mutation {
     addComment(input: {subjectId: "{THREAD_NODE_ID}", body: "Deferred to #{ISSUE_NUMBER} — tracked on the project board."}) {
       commentEdge { node { id } }
     }
   }'
   ```

## Safety Rules

- **NEVER** dismiss a human reviewer comment without presenting it to the user first.
- **NEVER** resolve a thread without implementing the fix or getting explicit user approval to defer.
- **Always** check **both** open and closed threads.
- For any logic, concurrency, or structural change: full build → test → fleet-review cycle.
- Push fixes to the **PR branch**, not main.
- After merge: prune stale remote refs, delete merged local branches, verify a clean working tree.
