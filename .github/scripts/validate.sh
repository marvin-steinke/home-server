#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/home-server-validation.XXXXXX")"
readonly ROOT_DIR WORK_DIR

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

for command_name in helm jq yq; do
  require_command "$command_name"
done

mapfile -d '' yaml_files < <(
  find "$ROOT_DIR" -type f \( -name '*.yaml' -o -name '*.yml' \) \
    ! -path "$ROOT_DIR/.git/*" \
    ! -path '*/templates/*' \
    ! -path '*/charts/*' \
    -print0
)
for yaml_file in "${yaml_files[@]}"; do
  yq '.' "$yaml_file" >/dev/null
done

mapfile -d '' chart_files < <(
  find "$ROOT_DIR/apps" "$ROOT_DIR/bootstrap" -type f -name Chart.yaml \
    ! -path '*/charts/*' \
    -print0
)

for chart_file in "${chart_files[@]}"; do
  chart_dir="$(dirname "$chart_file")"
  relative_dir="${chart_dir#"$ROOT_DIR/"}"
  validation_dir="$WORK_DIR/$relative_dir"
  mkdir -p "$validation_dir"
  cp -a "$chart_dir/." "$validation_dir/"

  if ! helm dependency build "$validation_dir"; then
    printf 'Dependency lock unavailable for %s; resolving pinned Chart.yaml versions.\n' \
      "$relative_dir" >&2
    helm dependency update "$validation_dir"
  fi

  if [[ -d "$validation_dir/templates" ]]; then
    helm lint --strict "$validation_dir"
  else
    helm lint "$validation_dir"
  fi

  if [[ "$relative_dir" == bootstrap ]]; then
    namespace=argocd
  else
    namespace="${relative_dir#apps/}"
    namespace="${namespace%%/*}"
  fi

  release_name="$(basename "$chart_dir")"
  rendered_file="$WORK_DIR/${relative_dir//\//_}.yaml"
  helm template "$release_name" "$validation_dir" \
    --namespace "$namespace" \
    --include-crds > "$rendered_file"
done

printf 'Validation passed for %d chart(s) (YAML parse, Helm lint, render).\n' \
  "${#chart_files[@]}"