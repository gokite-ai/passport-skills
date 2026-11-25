#!/usr/bin/env bash
# Proves scripts/validate.sh Check 8 catches a drifted skill setup.sh copy.
#
# The hardening of scripts/setup.sh once landed without reaching the three
# skill-bundled copies, and nothing failed. Check 8 is the guard against a
# repeat; this test is the guard against Check 8 silently ceasing to work.
# It runs validate.sh on an untouched copy of the repo (must pass), appends one
# line to one skill copy, and runs it again (must fail and name that file).
#
# Usage: bash scripts/test-setup-drift.sh
# Exit codes:
#   0  validate.sh passes undrifted and fails naming the drifted copy
#   1  either run behaved differently
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIFTED="attach-session/scripts/setup.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# A worktree's .git is a file pointing outside the copy, and node_modules is
# large but read-only here, so skip the former and symlink the latter.
COPY="$WORK/repo"
mkdir -p "$COPY"
shopt -s dotglob nullglob
for entry in "$REPO_ROOT"/*; do
  case "$(basename "$entry")" in
    .git|node_modules) continue ;;
  esac
  cp -R "$entry" "$COPY/"
done
shopt -u dotglob nullglob
# validate.sh Check 5 needs js-yaml, and a dangling symlink here would surface
# as the undrifted copy failing to validate, which reads like the wrong bug.
[[ -d "$REPO_ROOT/node_modules" ]] || fail "node_modules is missing; run npm ci first"
ln -s "$REPO_ROOT/node_modules" "$COPY/node_modules"
[[ -f "$COPY/$DRIFTED" ]] || fail "copy is missing $DRIFTED"

if ! out="$(bash "$COPY/scripts/validate.sh" 2>&1)"; then
  printf '%s\n' "$out" | sed 's/^/    /'
  fail "validate.sh exited non-zero on an undrifted copy"
fi
echo "PASS: undrifted copy validates"

echo '# drift' >> "$COPY/$DRIFTED"

status=0
out="$(bash "$COPY/scripts/validate.sh" 2>&1)" || status=$?
if [[ "$status" -ne 1 ]]; then
  printf '%s\n' "$out" | sed 's/^/    /'
  fail "validate.sh exited $status on a drifted copy, want 1"
fi
echo "PASS: drifted copy fails validation"

# Anchored on Check 8's own wording so this stays a Check 8 test even if
# Check 7, which reports on the same paths, changes the shape of its message.
if ! grep -qF "FAIL: $DRIFTED differs from scripts/setup.sh" <<< "$out"; then
  printf '%s\n' "$out" | sed 's/^/    /'
  fail "validate.sh failed but did not name $DRIFTED"
fi
echo "PASS: failure names $DRIFTED"

for other in authenticate-user/scripts/setup.sh request-session/scripts/setup.sh; do
  if grep -qF "FAIL: $other differs" <<< "$out"; then
    printf '%s\n' "$out" | sed 's/^/    /'
    fail "validate.sh blamed undrifted $other"
  fi
done
echo "PASS: undrifted copies are not blamed"

echo "PASSED: validate.sh catches a drifted skill setup.sh copy and names it"
