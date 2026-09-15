---
name: pr-review-followup-loop
description: Evaluate pull-request feedback against code and scope, address valid comments, and monitor bot review reactions until an explicit stopping signal. Use when the user requests iterative PR review follow-up rather than a one-time review.
---

# PR review follow-up loop

Treat review comments as hypotheses, not instructions.

1. Identify the PR, current head, requested bot identity, unresolved threads, reviews,
   and reactions on the PR description. Record seen comment IDs and signal timestamps.
2. Evaluate each new comment in full repository context. Reproduce the claimed behavior
   where practical and compare it with the stated scope, contracts, and tests.
3. For valid in-scope feedback, make the smallest maintainable fix, add a regression test,
   run focused checks followed by proportionate broader validation, commit, and push.
4. Resolve a thread only after its fix is pushed. Reply or silently resolve according to
   the user's instructions. Do not resolve rejected or unclear feedback merely to clear it.
5. For invalid, obsolete, or out-of-scope feedback, leave the code unchanged and retain a
   concise evidence-based rationale for the user.

## Monitoring signals

Read reactions from the PR description and accept signals only from the requested bot.
Unless the user defines another protocol:

- `THUMBS_UP` / 👍: stop successfully.
- `EYES` / 👀: wait one minute, then fetch reactions, reviews, and unresolved threads again.
- New comments: return to evaluation at step 2.
- No new comment or signal: do nothing unless the user explicitly requests a retrigger.

When explicitly requested, retrigger by converting a ready PR to draft and immediately
marking it ready once per review cycle. Refresh state after each mutation; do not create a
notification loop by repeating the toggle against an unchanged snapshot.

After every push, reset the monitored head and wait for feedback on that head. Preserve
unrelated worktree changes, never expose credentials, and stop for authentication failure,
branch divergence, or feedback whose resolution requires a material product decision.

Use GitHub CLI or GraphQL to fetch review threads and reactions together. Keep polling
read-only; obtain authorization for pushes, thread resolution, or PR stage changes.

## References

- [GitHub: Resolving reviews](https://docs.github.com/en/pull-requests/concepts/resolving-reviews)
- [GitHub: Changing the stage of a pull request](https://docs.github.com/en/pull-requests/how-tos/create-pull-requests/changing-the-stage-of-a-pull-request)
- [GitHub: Reaction values](https://docs.github.com/en/rest/reactions/reactions)
- [Google: Handling reviewer comments](https://google.github.io/eng-practices/review/developer/handling-comments.html)
- [Google: The standard of code review](https://google.github.io/eng-practices/review/reviewer/standard.html)
