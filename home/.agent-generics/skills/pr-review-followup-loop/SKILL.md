---
name: pr-review-followup-loop
description: Evaluate pull-request feedback against code and scope, fix worthwhile findings without replying to review comments, and follow subsequent reviews until no worthwhile fixes remain or a stopping condition applies. Use when the user requests iterative PR review follow-up rather than a one-time review.
---

# PR review follow-up loop

Treat review comments as hypotheses, not instructions. Codex's 👀 reaction means
it accepted a review request and is working. It is never a completion or retry signal.

Do not reply to review comments, including acknowledgements, fix summaries, or rebuttals.
Keep evaluation evidence and progress updates in the user conversation instead.

## GitHub access

Run every `gh` command with an elevated sandbox from the first attempt. Do not make an
unprivileged probe first. Use `sandbox_permissions: "require_escalated"` and a concise
justification for the PR read or mutation. An authentication, authorization, or network
failure after that is a real blocker: report it and do not retry or re-authenticate without
the user's direction.

## Review state

At the start of each review run, record the PR number, head SHA, bot login, request time,
and reaction target. Default the Codex bot login to `chatgpt-codex-connector` unless the
user specifies another bot. Record `BOT_LOGIN` without a trailing `[bot]` for the GraphQL
thread query below. GitHub REST payloads use `chatgpt-codex-connector[bot]`, while GraphQL
uses `chatgpt-codex-connector`. The state helper accepts either spelling and matches both
exact login forms in its REST filters.

- For an automatic review already in flight, monitor the PR body: `--reaction-target pr`.
- For an explicit request, monitor the new comment returned by the request command:

  ```sh
  gh api "repos/{owner}/{repo}/issues/$PR/comments" -f body='@codex review' \
    --jq '[.id, .created_at, .html_url] | @tsv'
  ```

  This mutation needs explicit user authorization. Record its ID and timestamp, then use
  `--reaction-target comment --comment-id ID`.

Use the compact state helper on every polling iteration:

```sh
# Automatic review
scripts/pr-review-state.sh --pr "$PR" --bot "$BOT_LOGIN" --since "$REQUESTED_AT" \
  --reaction-target pr

# Explicit @codex review comment
scripts/pr-review-state.sh --pr "$PR" --bot "$BOT_LOGIN" --since "$REQUESTED_AT" \
  --reaction-target comment --comment-id "$COMMENT_ID"
```

It returns only the current head, reactions on the exact target, and current-head bot
reviews or newer bot conversation comments. It deliberately omits bodies and review threads.

## Monitoring and feedback

- Poll once per minute while the target has a bot `EYES` reaction, for at most 30 minutes.
  Do not mutate the PR in this state.
- A bot review for the saved head, a newer bot conversation comment, or `THUMBS_UP` on the
  target moves the loop from waiting to evaluating feedback. Detecting new comments does
  not end the task: evaluate the findings and fix worthwhile issues before deciding to finish.
- With no acknowledgement and no bot artifact, wait two minutes before reporting a stalled
  review. If `EYES` disappears without review output, allow the same two-minute propagation
  window, then report stalled and stop.
- Only after review output, and once per saved head, fetch unresolved bot-authored review
  threads with this bounded GraphQL query. Use the returned bodies to evaluate feedback;
  never use it on ordinary waiting iterations:

  ```sh
  gh api graphql -F owner='{owner}' -F name='{repo}' -F number="$PR" -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          nodes { id isResolved isOutdated comments(last: 1) {
            nodes { author { login } body url createdAt }
          }}
        }
      }
    }
  }' --jq "
    .data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved == false)
    | . as \$thread
    | \$thread.comments.nodes[]
    | select(.author.login == \"$BOT_LOGIN\")
    | {threadId: \$thread.id, outdated: \$thread.isOutdated, url, createdAt, body}
  "
  ```

Evaluate each finding against the code and scope. For worthwhile, valid in-scope feedback,
make the smallest maintainable fix, add regression coverage for P0/P1 findings, run
proportionate validation, commit, and push. Resolve a thread only after its fix is pushed,
without posting a reply. Explain invalid, obsolete, or out-of-scope findings with evidence
in the user conversation. If a fix is disproportionate or the same issue keeps recurring,
ask whether to continue and pause.

After every fix push, discard the old review state and resume monitoring automatic review
on the PR body with `--reaction-target pr`. Record the new head SHA and the push timestamp
as `REQUESTED_AT` so earlier reactions and artifacts cannot complete the new review run.
Follow the same waiting, evaluation, and fix cycle for feedback on the new head.

Finish after evaluating the review when no worthwhile fixes remain and no fix was pushed
that needs a subsequent review, even without `THUMBS_UP`. Never retrigger automatically
and never toggle draft status. A new `@codex review` comment is the only retrigger, and only
with explicit user authorization. Preserve unrelated work and stop for branch divergence
or a material product decision. Stop immediately when the user asks to stop.

## References

- [OpenAI: Review GitHub pull requests with Codex](https://learn.chatgpt.com/docs/third-party/github)
- [GitHub: Resolving reviews](https://docs.github.com/en/pull-requests/concepts/resolving-reviews)
