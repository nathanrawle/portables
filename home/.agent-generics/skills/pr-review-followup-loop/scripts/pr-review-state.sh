#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf '%s\n' 'Usage: pr-review-state.sh --pr NUMBER --bot LOGIN --since RFC3339 --reaction-target pr|comment [--comment-id ID]'
}

pr=
bot=
since=
reaction_target=
comment_id=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr|--bot|--since|--reaction-target|--comment-id)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      case "$1" in
        --pr) pr="$2" ;;
        --bot) bot="$2" ;;
        --since) since="$2" ;;
        --reaction-target) reaction_target="$2" ;;
        --comment-id) comment_id="$2" ;;
      esac
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[[ "$pr" =~ ^[1-9][0-9]*$ ]] || { usage >&2; exit 2; }
bot="${bot%\[bot\]}"
[[ "$bot" =~ ^[A-Za-z0-9_-]+$ ]] || { usage >&2; exit 2; }
[[ -n "$since" ]] || { usage >&2; exit 2; }
case "$reaction_target" in
  pr) [[ -z "$comment_id" ]] || { usage >&2; exit 2; } ;;
  comment) [[ "$comment_id" =~ ^[1-9][0-9]*$ ]] || { usage >&2; exit 2; } ;;
  *) usage >&2; exit 2 ;;
esac

metadata="$(gh pr view "$pr" --json headRefOid,isDraft,state,url --jq '[.headRefOid, .isDraft, .state, .url] | @tsv')"
IFS=$'\t' read -r head draft state url <<<"$metadata"

case "$reaction_target" in
  pr) reaction_path="repos/{owner}/{repo}/issues/$pr/reactions" ;;
  comment) reaction_path="repos/{owner}/{repo}/issues/comments/$comment_id/reactions" ;;
esac

printf 'pr\t%s\nhead\t%s\ndraft\t%s\nstate\t%s\nurl\t%s\ntarget\t%s\n' \
  "$pr" "$head" "$draft" "$state" "$url" "$reaction_target"
[[ -z "$comment_id" ]] || printf 'comment-id\t%s\n' "$comment_id"

reactions="$(gh api --paginate "$reaction_path?per_page=100" \
  --jq ".[] | select((.user.login == \"$bot\" or .user.login == \"$bot[bot]\") and .created_at >= \"$since\") | .content")"
if [[ -n "$reactions" ]]; then
  while IFS= read -r reaction; do printf 'reaction\t%s\n' "$reaction"; done <<<"$reactions"
fi

reviews="$(gh api --paginate "repos/{owner}/{repo}/pulls/$pr/reviews?per_page=100" \
  --jq ".[] | select((.user.login == \"$bot\" or .user.login == \"$bot[bot]\") and .commit_id == \"$head\" and .submitted_at >= \"$since\") | [.state, .commit_id, .submitted_at, .html_url] | @tsv")"
if [[ -n "$reviews" ]]; then
  while IFS=$'\t' read -r review_state commit submitted_at review_url; do
    printf 'review\t%s\t%s\t%s\t%s\n' "$review_state" "$commit" "$submitted_at" "$review_url"
  done <<<"$reviews"
fi

comments="$(gh api --paginate "repos/{owner}/{repo}/issues/$pr/comments?since=$since&per_page=100" \
  --jq ".[] | select(.user.login == \"$bot\" or .user.login == \"$bot[bot]\") | [.id, .created_at, .html_url] | @tsv")"
if [[ -n "$comments" ]]; then
  while IFS=$'\t' read -r comment created_at comment_url; do
    printf 'comment\t%s\t%s\t%s\n' "$comment" "$created_at" "$comment_url"
  done <<<"$comments"
fi
