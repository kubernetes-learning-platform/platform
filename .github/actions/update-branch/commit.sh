#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?}" "${REPO:?}" "${BRANCH:?}" "${MESSAGE:?}" "${GITHUB_OUTPUT:?}"

work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/update-branch.XXXXXX")"
trap 'rm -rf "$work"' EXIT

base="$(git rev-parse HEAD)"
base_tree="$(git rev-parse 'HEAD^{tree}')"
entries="$work/entries.jsonl"
: >"$entries"

git add -A
while IFS= read -r -d '' status && IFS= read -r -d '' path; do
  if [[ "$status" == D ]]; then
    jq -n --arg path "$path" '{path: $path, mode: "100644", type: "blob", sha: null}' >>"$entries"
    continue
  fi
  if [[ -L "$path" ]]; then
    echo "::error file=$path::The update bot doesn't commit symlinks."
    exit 1
  fi
  mode=100644
  [[ ! -x "$path" ]] || mode=100755
  base64 -w0 "$path" >"$work/content"
  blob="$(jq -n --rawfile content "$work/content" '{content: $content, encoding: "base64"}' |
    gh api "repos/$REPO/git/blobs" --input - --jq .sha)"
  jq -n --arg path "$path" --arg mode "$mode" --arg sha "$blob" \
    '{path: $path, mode: $mode, type: "blob", sha: $sha}' >>"$entries"
  echo "Changed: $path"
done < <(git diff --cached --name-status --no-renames -z HEAD)

if [[ ! -s "$entries" ]]; then
  echo "::error::There are no changes to commit."
  exit 1
fi

tree="$(jq -s --arg base "$base_tree" '{base_tree: $base, tree: .}' "$entries" |
  gh api "repos/$REPO/git/trees" --input - --jq .sha)"
commit="$(jq -n --arg message "$MESSAGE" --arg tree "$tree" --arg parent "$base" \
  '{message: $message, tree: $tree, parents: [$parent]}' |
  gh api "repos/$REPO/git/commits" --input - --jq .sha)"

if gh api "repos/$REPO/git/ref/heads/$BRANCH" --silent 2>/dev/null; then
  gh api -X PATCH "repos/$REPO/git/refs/heads/$BRANCH" -f sha="$commit" -F force=true --silent
else
  gh api "repos/$REPO/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$commit" --silent
fi

echo "Committed $commit to $BRANCH"
echo "sha=$commit" >>"$GITHUB_OUTPUT"
