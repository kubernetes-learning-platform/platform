#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: lint/sync.sh [--check] [--dotnet] [--node] <repo-dir>

Copies the shared lint configs into the root of <repo-dir>:
  .editorconfig           always
  Directory.Build.props   with --dotnet
  biome.json              with --node

It records the platform commit and the flags in <repo-dir>/.lint-sync, which it
rewrites only when a copy or the flags change. Without --dotnet or --node it uses
the flags recorded there. platform itself gets no .lint-sync. It refuses to sync
from uncommitted changes in lint/, because .lint-sync must name a commit that
holds the copied files.

  --check   change nothing; show a diff for each copy that differs and exit 1 if
            any do. Check out platform at the commit in .lint-sync first, so only
            hand edits fail, not newer platform changes.
EOF
}

die() {
  echo "sync.sh: $1" >&2
  exit 2
}

bad_usage() {
  echo "sync.sh: $1" >&2
  echo >&2
  usage >&2
  exit 2
}

lint_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
platform_dir="$(dirname "$lint_dir")"
state_name=.lint-sync

check=false
dotnet=false
node=false
flags_given=false
target=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) check=true ;;
    --dotnet)
      dotnet=true
      flags_given=true
      ;;
    --node)
      node=true
      flags_given=true
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) bad_usage "unknown option: $1" ;;
    *)
      [[ -z "$target" ]] || bad_usage "give one repo directory, not several"
      target="$1"
      ;;
  esac
  shift
done

[[ -n "$target" ]] || bad_usage "no repo directory given"
[[ -d "$target" ]] || bad_usage "not a directory: $target"
target="$(cd "$target" && pwd)"
[[ "$target" != "$lint_dir" ]] || bad_usage "the target is lint/ itself"

is_platform=false
[[ "$target" != "$platform_dir" ]] || is_platform=true
state_file="$target/$state_name"

has_state=false
recorded_dotnet=false
recorded_node=false
if [[ "$is_platform" == false && -f "$state_file" && ! -L "$state_file" ]]; then
  has_state=true
  seen=" "
  while IFS='=' read -r key value; do
    [[ -n "$key" && "$key" != \#* ]] || continue
    [[ "$seen" != *" $key "* ]] || die "$key appears twice in $state_file"
    seen="$seen$key "
    case "$key" in
      commit)
        [[ "$value" =~ ^[0-9a-f]{40}$ ]] || die "bad commit in $state_file: $value"
        ;;
      dotnet | node)
        [[ "$value" == true || "$value" == false ]] || die "bad value in $state_file: $key=$value"
        if [[ "$key" == dotnet ]]; then recorded_dotnet="$value"; else recorded_node="$value"; fi
        ;;
      *) die "unknown key in $state_file: $key" ;;
    esac
  done <"$state_file"
  for key in commit dotnet node; do
    [[ "$seen" == *" $key "* ]] || die "$key is missing from $state_file"
  done
fi

if [[ "$flags_given" == false ]]; then
  dotnet="$recorded_dotnet"
  node="$recorded_node"
fi

files=(.editorconfig)
[[ "$dotnet" == false ]] || files+=(Directory.Build.props)
[[ "$node" == false ]] || files+=(biome.json)

for file in "${files[@]}" "$state_name"; do
  [[ ! -L "$target/$file" ]] || die "$target/$file is a symlink; replace it with a regular file"
done

commit=""
if [[ "$is_platform" == false && "$check" == false ]]; then
  commit="$(git -C "$platform_dir" rev-parse HEAD 2>/dev/null)" ||
    die "platform at $platform_dir is not a git checkout, so there is no commit to record"
  [[ -z "$(git -C "$platform_dir" status --porcelain -- lint)" ]] ||
    die "lint/ has uncommitted changes; commit them first so $state_name can name a commit that holds them"
fi

drift=false
changed=false
for file in "${files[@]}"; do
  src="$lint_dir/$file"
  dst="$target/$file"
  if cmp -s "$src" "$dst"; then
    echo "ok        $file"
  elif [[ "$check" == true ]]; then
    drift=true
    if [[ -e "$dst" ]]; then
      echo "differs   $file"
      diff -u --label "$file (repo)" --label "$file (platform/lint)" "$dst" "$src" || true
    else
      echo "missing   $file"
    fi
  else
    cp "$src" "$dst"
    changed=true
    echo "updated   $file"
  fi
done

if [[ "$is_platform" == false ]]; then
  if [[ "$check" == true ]]; then
    if [[ "$has_state" == false ]]; then
      drift=true
      echo "missing   $state_name"
    fi
  elif [[ "$changed" == true || "$has_state" == false || "$dotnet" != "$recorded_dotnet" || "$node" != "$recorded_node" ]]; then
    {
      echo "# Written by platform/lint/sync.sh. Don't edit."
      echo "commit=$commit"
      echo "dotnet=$dotnet"
      echo "node=$node"
    } >"$state_file"
    echo "updated   $state_name"
  fi
fi

if [[ "$drift" == true ]]; then
  echo "sync.sh: the copies above don't match platform/lint. Run lint/sync.sh from platform to update them." >&2
  exit 1
fi
