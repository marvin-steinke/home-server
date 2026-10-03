#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]] || [[ -z "$1" ]]; then
  printf 'Usage: %s <revision>\n' "${0##*/}" >&2
  exit 2
fi

if ! command -v argocd >/dev/null 2>&1; then
  printf 'Required command not found: argocd\n' >&2
  exit 1
fi

revision="$1"
argocd app set home-server --revision "$revision"
argocd app wait home-server --sync --health --timeout 900
