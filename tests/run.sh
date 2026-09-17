#!/usr/bin/env bash
# Harnais de test minimal : chaque tests/test_*.sh exporte des fonctions test_*.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
pass=0; fail=0; failed=()

assert() { # assert <description> <condition-exit-code>
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); failed+=("$1"); printf '  FAIL %s\n' "$1"; fi
}
export -f assert

for f in "$ROOT"/tests/test_*.sh; do
  [ -e "$f" ] || continue
  printf '%s\n' "$(basename "$f")"
  # shellcheck disable=SC1090
  source "$f"
  for fn in $(declare -F | awk '{print $3}' | grep '^test_' || true); do
    "$fn"
    unset -f "$fn"
  done
done

printf '\n%d passés, %d échoués\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then printf 'échecs:\n'; printf '  - %s\n' "${failed[@]}"; exit 1; fi
