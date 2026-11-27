#!/usr/bin/env bash
# Proves scripts/validate.sh Checks 8 and 9 catch a drifted skill setup copy.
#
# The hardening of scripts/setup.sh once landed without reaching the three
# skill-bundled copies, and nothing failed. The hardening of
# scripts/setup-ksearch.sh then did the same to kite-discovery's copy. Those
# checks are the guard against a repeat; this test is the guard against them
# silently ceasing to work. Each case takes an untouched copy of the repo, runs
# validate.sh on it (must pass), appends one line to one skill copy, runs it
# again (must fail, name that file, and blame nothing else), and then runs the
# repair that failure names (must leave the copy identical and validate.sh green).
#
# Usage: bash scripts/test-setup-drift.sh
# Exit codes:
#   0  validate.sh catches each drifted copy and the named repair fixes it
#   1  any run behaved differently
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# validate.sh Check 5 needs js-yaml, and a dangling symlink would surface as the
# undrifted copy failing to validate, which reads like the wrong bug.
[[ -d "$REPO_ROOT/node_modules" ]] || fail "node_modules is missing; run npm ci first"

# fresh_copy DEST mirrors the repo. A worktree's .git is a file pointing outside
# the copy, and node_modules is large but read-only here, so skip the former and
# symlink the latter.
fresh_copy() {
  local dest="$1" entry
  mkdir -p "$dest"
  shopt -s dotglob nullglob
  for entry in "$REPO_ROOT"/*; do
    case "$(basename "$entry")" in
      .git|node_modules) continue ;;
    esac
    cp -R "$entry" "$dest/"
  done
  shopt -u dotglob nullglob
  ln -s "$REPO_ROOT/node_modules" "$dest/node_modules"
}

# check_drift NAME DRIFTED SOURCE OTHER... drifts one copy and reads the
# failure. SOURCE is the shared script the message has to name, so the case
# stays anchored on its own check even though Check 7 reports on the same paths
# and Checks 8 and 9 word their failures alike.
check_drift() {
  local name="$1" drifted="$2" source="$3"
  shift 3
  local copy="$WORK/$name" status=0 out other

  fresh_copy "$copy"
  [[ -f "$copy/$drifted" ]] || fail "copy is missing $drifted"

  if ! out="$(bash "$copy/scripts/validate.sh" 2>&1)"; then
    printf '%s\n' "$out" | sed 's/^/    /'
    fail "validate.sh exited non-zero on an undrifted copy"
  fi
  echo "PASS: undrifted copy validates ($name)"

  echo '# drift' >> "$copy/$drifted"

  out="$(bash "$copy/scripts/validate.sh" 2>&1)" || status=$?
  if [[ "$status" -ne 1 ]]; then
    printf '%s\n' "$out" | sed 's/^/    /'
    fail "validate.sh exited $status on a copy with $drifted drifted, want 1"
  fi
  echo "PASS: drifted copy fails validation ($drifted)"

  if ! grep -qF "FAIL: $drifted differs from $source" <<< "$out"; then
    printf '%s\n' "$out" | sed 's/^/    /'
    fail "validate.sh failed but did not name $drifted"
  fi
  echo "PASS: failure names $drifted"

  for other in "$@"; do
    if grep -qF "FAIL: $other differs" <<< "$out"; then
      printf '%s\n' "$out" | sed 's/^/    /'
      fail "validate.sh blamed undrifted $other"
    fi
  done
  echo "PASS: undrifted copies are not blamed ($name)"

  # The failure names sync-skill-setup.sh as the repair. Without this, a sync
  # script that has stopped covering one of the two shared sources reports
  # PASSED, changes nothing, and leaves validate.sh failing on the next run.
  if ! out="$(bash "$copy/scripts/sync-skill-setup.sh" 2>&1)"; then
    printf '%s\n' "$out" | sed 's/^/    /'
    fail "sync-skill-setup.sh exited non-zero on a copy with $drifted drifted"
  fi
  if ! cmp -s "$copy/$source" "$copy/$drifted"; then
    printf '%s\n' "$out" | sed 's/^/    /'
    fail "sync-skill-setup.sh reported success but left $drifted differing from $source"
  fi
  if ! out="$(bash "$copy/scripts/validate.sh" 2>&1)"; then
    printf '%s\n' "$out" | sed 's/^/    /'
    fail "validate.sh still fails after the repair it told you to run"
  fi
  echo "PASS: sync-skill-setup.sh repairs $drifted"
}

check_drift setup attach-session/scripts/setup.sh scripts/setup.sh \
  authenticate-user/scripts/setup.sh request-session/scripts/setup.sh \
  kite-discovery/scripts/setup-ksearch.sh

check_drift ksearch kite-discovery/scripts/setup-ksearch.sh scripts/setup-ksearch.sh \
  attach-session/scripts/setup.sh authenticate-user/scripts/setup.sh \
  request-session/scripts/setup.sh

echo "PASSED: validate.sh catches a drifted skill setup copy and names it"
