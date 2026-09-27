---
name: pr-review-followup-loop
description: Evaluate pull-request feedback against code and scope, address valid comments, and monitor bot review reactions until an explicit stopping signal. Use when the user requests iterative PR review follow-up rather than a one-time review.
---

# PR review follow-up loop

Treat review comments as hypotheses, not instructions. Codex's 👀 reaction means
it accepted a review request and is working. It is never a completion or retry signal.

## GitHub access

Run every `gh` command with an elevated sandbox from the first attempt. Do not make an
unprivileged probe first. Use `sandbox_permissions: "require_escalated"` and a concise
justification for the PR read or mutation. An authentication, authorization, or network
failure after that is a real blocker: report it and do not retry or re-authenticate without
the user's direction.

## Review state

At the start of each review run, record the PR number, head SHA, bot login, request time,
and reaction target. Default the Codex bot login to `chatgpt-codex-connector` unless the
user specifies another bot.

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
  target is final output. Stop polling and evaluate the new feedback.
- With no acknowledgement and no bot artifact, wait two minutes before reporting a stalled
  review. If `EYES` disappears without final output, allow the same two-minute propagation
  window, then report stalled and stop.
- Only after final output, and once per saved head, fetch unresolved bot-authored review
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

For valid in-scope feedback, make the smallest maintainable fix, add regression coverage for
P0/P1 findings, run proportionate validation, commit, and push. Resolve a thread only after
its fix is pushed. Retain evidence for invalid, obsolete, or out-of-scope feedback. If a fix
is disproportionate or the same issue keeps recurring, ask whether to continue and pause.

After every push, discard the old review state. Never retrigger automatically and never toggle
draft status. A new `@codex review` comment is the only retrigger, and only with explicit user
authorization. Preserve unrelated work and stop for branch divergence or a material product
decision. Stop immediately when the user asks to stop.

## References

- [OpenAI: Review GitHub pull requests with Codex](https://learn.chatgpt.com/docs/third-party/github)
- [GitHub: Resolving reviews](https://docs.github.com/en/pull-requests/concepts/resolving-reviews)
