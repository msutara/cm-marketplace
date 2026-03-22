---
name: cm-pr-comments
description: >
  Triage, categorize, and resolve PR review comments across all Config Manager
  repositories. Fetches open and closed threads, distinguishes human from bot
  feedback, assesses risk, presents a prioritized summary, and implements fixes
  with the full build → test → fleet-review cycle when required.
  USE FOR: check pr comments, triage comments, address review, pr feedback,
  resolve threads, review comments, pr comment triage, handle comments,
  fix pr comments.
---

# CM PR Comment Triage & Resolution

Systematic workflow for triaging and resolving PR review comments across all
Config Manager repositories.

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
reference repo, and project board IDs. All values below are derived from the manifest.

## Step 1 — Fetch PR Comments

Retrieve **all** review threads for the target PR — both open and resolved.

### Open (unresolved) threads

```bash
gh api graphql -f query='query {
  repository(owner: "{OWNER}", name: "{repo}") {
    pullRequest(number: {PR_NUMBER}) {
      reviewThreads(first: 100) {
        pageInfo { hasNextPage endCursor }
        nodes {
          isResolved
          comments(first: 10) {
            nodes { body path line author { login } }
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)'
```

> **Pagination**: if `pageInfo.hasNextPage` is `true`, re-query with
> `after: "{endCursor}"` to fetch remaining threads. Same applies to
> `comments` if a thread has more than 10 replies.

### Closed (resolved) threads

Closed threads from human reviewers often contain valid suggestions that were
dismissed rather than implemented. Always inspect them.

```bash
# Same query as above, filter for resolved threads:
# select(.isResolved == true)
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
## PR #{PR_NUMBER} Comment Triage — {repo}

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

### Fix Propagation (MANDATORY — apply BEFORE building/testing)

When fixing ANY review comment, **immediately search the entire repo** for the
same pattern. Reviewers (human and bot) check whether a fix was applied
everywhere — fixing one file and missing others guarantees another review round.

1. Identify the **pattern class** of the fix (regex, error format, code snippet,
   UUOC, path traversal, wording, etc.).
2. **Grep the entire repo** for that pattern class — scripts, skills, agents,
   docs, CI. Not just the file flagged.
3. Apply the fix to **every instance** found.
4. Run a quick consistency check: are all instances now identical/consistent?

Examples of pattern classes:

- `cat file | jq` → search ALL `$(cat` and `cat.*|` repo-wide
- Regex `[A-Za-z0-9._-]+` → search ALL regex validations, tighten consistently
- Error to stdout → search ALL error-path `echo`, ensure `>&2`
- Stale comment wording → search ALL files for the old wording
- Missing cwd check in manifest → check ALL manifest discovery snippets

### Full-flow fixes

For every comment marked *full flow required*:

1. Implement the fix **and propagate to all instances**.
2. Build — ensure no compilation errors.
3. Test — run all tests, ensure passing.
4. Lint — run project linters.
5. Fleet review — invoke the `cm-fleet-review` skill (5–11 parallel agents with varied models).
6. Address any fleet findings, then re-run steps 2–5.
7. Push to the **PR branch** (never to main).

### Quick fixes

For comments marked *safe to quick-fix*:

1. **Ask the user first** — explain why skipping the full flow is safe.
2. Implement the fix **and propagate to all instances**.
3. Build and test.
4. Push to the PR branch.

### Resolve the thread

After pushing a fix, resolve the corresponding review thread via GraphQL:

```bash
gh api graphql -f query="mutation {
  resolveReviewThread(input: {threadId: \"{THREAD_NODE_ID}\"}) {
    thread { isResolved }
  }
}"
```

## Step 6 — Handle Unresolvable Comments

If a comment cannot be addressed in this PR cycle:

1. Create a GitHub issue tracking the deferred work.
2. Add the issue to the project board (from the marketplace repo root).
   The `--status` value must match a key in `.project_board.statuses`
   from `.cm/project.json` (defaults: `Backlog`, `InProgress`, `Review`,
   `Done`):

   ```bash
   ./plugins/cm-dev-tools/scripts/project-board.sh --url {ISSUE_URL} --status Backlog
   ```

3. Resolve the thread with a reference to the new issue.

   ```bash
   gh api graphql -f query="mutation {
     resolveReviewThread(input: {threadId: \"{THREAD_NODE_ID}\"}) {
       thread { isResolved }
     }
   }"
   ```

   Then add a PR comment noting the deferral:

   ```bash
   _comment="$(mktemp)"
   echo "Deferred to #${ISSUE_NUMBER} — tracked on the project board." > "$_comment"
   gh pr comment {PR_NUMBER} --repo {OWNER}/{repo} --body-file "$_comment"
   rm -f "$_comment"
   ```

## Safety Rules

- **NEVER** dismiss a human reviewer comment without presenting it to the user first.
- **NEVER** resolve a thread without implementing the fix or getting explicit user approval to defer.
- **Always** check **both** open and closed threads.
- For any logic, concurrency, or structural change: full build → test → fleet-review cycle.
- Push fixes to the **PR branch**, not main.
- After merge: prune stale remote refs, delete merged local branches, verify a clean working tree.
