#!/usr/bin/env bash
# Tests EVERY copy of version_at_least in this repo against one case table.
#
# The comparison is deliberately duplicated into each skill's setup script
# (they must run standalone from a skills install, with no shared lib to
# source), which is exactly why a single copy under test is not enough: the
# copy CI happened to exercise was correct while another drifted. This finds
# every definition and drives the same cases through each.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# version_at_least A B -> expected exit (0 = A >= B, 1 = A < B)
CASES=(
  "6.0.0 6.0.0 0"
  "6.0.1 6.0.0 0"
  "5.9.9 6.0.0 1"
  "6.0.0-rc.1 6.0.0 1"          # a pre-release ranks BELOW its release
  "6.0.0 6.0.0-rc.1 0"
  "6.0.0-rc.2 6.0.0-rc.1 0"
  "6.0.0-rc.1 6.0.0-rc.1 0"
  "6.1.0-rc.1 6.0.0 0"
  "6.0.0+build.1 6.0.0 0"       # build metadata is ignored (SemVer §10)
  "6.0.0 6.0.0+build.1 0"
  "6.0.0-rc.1+build.1 6.0.0 1"
  "garbage 6.0.0 1"             # unparseable counts as too old
)

fail=0
scripts=$(grep -rl '^version_at_least()' "$ROOT_DIR" --include='setup*.sh' | sort)
[[ -n "$scripts" ]] || { echo "FAIL: no version_at_least definitions found" >&2; exit 1; }

while IFS= read -r script; do
  rel="${script#"$ROOT_DIR"/}"
  # Extract just the function body so the script's side effects never run.
  fn=$(sed -n '/^version_at_least()/,/^}/p' "$script")
  [[ -n "$fn" ]] || { echo "FAIL: $rel defines version_at_least but the body could not be extracted" >&2; fail=1; continue; }
  for case in "${CASES[@]}"; do
    read -r a b want <<<"$case"
    got=0
    bash -c "$fn"$'\n'"version_at_least \"\$1\" \"\$2\"" _ "$a" "$b" || got=$?
    if [[ "$got" != "$want" ]]; then
      echo "FAIL: $rel: version_at_least $a $b exited $got, want $want" >&2
      fail=1
    fi
  done
  echo "  [OK] $rel version_at_least passes ${#CASES[@]} cases"
done <<<"$scripts"

if [[ $fail -ne 0 ]]; then
  echo "FAILED: a version comparison copy has drifted" >&2
  exit 1
fi
echo "PASSED: every version_at_least copy agrees on ${#CASES[@]} cases"
