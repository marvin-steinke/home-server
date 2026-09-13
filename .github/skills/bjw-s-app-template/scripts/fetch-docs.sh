#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ $# == 1 ]] || fail "Usage: bash $0 <exact-app-template-version>"
version=$1
[[ $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail "Expected a stable X.Y.Z version, got: $version"
tag="app-template-$version"
upstream=https://github.com/bjw-s-labs/helm-charts.git
repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd -P)
cache_base=${XDG_CACHE_HOME:-${HOME:?HOME must be set}/.cache}
[[ $cache_base == /* ]] || fail 'XDG_CACHE_HOME must be an absolute path outside the repository.'

physical_path() {
  local candidate=$1 suffix=
  while [[ ! -d $candidate ]]; do
    suffix="/$(basename "$candidate")$suffix"
    candidate=$(dirname "$candidate")
  done
  printf '%s%s\n' "$(cd "$candidate" && pwd -P)" "$suffix"
}

cache_base=$(physical_path "$cache_base")
case "$cache_base/" in
  "$repository/"*) fail 'The documentation cache must be outside the repository.' ;;
esac
mkdir -p "$cache_base/bjw-s-app-template"
cache_root=$(cd "$cache_base/bjw-s-app-template" && pwd -P)
case "$cache_root/" in
  "$repository/"*) fail 'The documentation cache must be outside the repository.' ;;
esac
destination="$cache_root/$version"
docs_relative=docs/src/content/docs/app-template

valid_cache() {
  [[ -f "$destination/.cache-source" &&
     -f "$destination/$docs_relative/getting-started.md" &&
     -d "$destination/$docs_relative/reference" ]] || return 1
  local source cached_tag commit
  {
    IFS= read -r source
    IFS= read -r cached_tag
    IFS= read -r commit
  } < "$destination/.cache-source" || return 1
  [[ $source == "$upstream" && $cached_tag == "$tag" && $commit =~ ^[0-9a-f]{40}$ ]]
}

if [[ -e $destination || -L $destination ]]; then
  valid_cache || fail "Incomplete cache: $destination. Remove this version directory explicitly and retry."
  printf '%s\n' "$destination/$docs_relative"
  exit 0
fi

command -v git >/dev/null || fail 'Git >=2.25 is required for the initial fetch.'
lock="$cache_root/.$version.lock"
mkdir "$lock" 2>/dev/null || fail "Fetch already in progress: $lock. Retry after it finishes; remove a stale lock only when no fetch is running."
staging=
cleanup() {
  [[ -z $staging ]] || rm -rf "$staging"
  rmdir "$lock"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
staging=$(mktemp -d "$cache_root/.$version.XXXXXX")
export GIT_TERMINAL_PROMPT=0
git clone --quiet --depth 1 --single-branch --branch "$tag" --filter=blob:none --no-checkout \
  "$upstream" "$staging/source" >&2 || fail "Could not fetch $tag from $upstream. Check network access and the exact chart version."
git -C "$staging/source" sparse-checkout init --cone >&2
git -C "$staging/source" sparse-checkout set "$docs_relative" charts/other/app-template >&2
git -C "$staging/source" -c advice.detachedHead=false checkout --quiet --detach "$tag" >&2
[[ -f "$staging/source/$docs_relative/getting-started.md" &&
   -d "$staging/source/$docs_relative/reference" ]] || fail "Release $tag does not contain the expected documentation."
commit=$(git -C "$staging/source" rev-parse HEAD)
printf '%s\n' "$upstream" "$tag" "$commit" > "$staging/source/.cache-source"
[[ ! -e $destination && ! -L $destination ]] || fail "Cache appeared during fetch: $destination. Retry to use it."
mv "$staging/source" "$destination"
printf '%s\n' "$destination/$docs_relative"