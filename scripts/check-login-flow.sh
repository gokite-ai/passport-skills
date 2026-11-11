#!/usr/bin/env bash
# Checks that the authenticate-user skill still documents the browser-first login.
#
# Why: the skill sets the real number of emails, codes, redirects and tabs a CLI
# user pays to sign in (docs/login-step-counts.md). An edit that drops the browser
# path, or that goes back to promising a second email, quietly puts those counts
# back up without failing validate.sh or the markdown lint.
#
# Usage: bash scripts/check-login-flow.sh
# Exit codes:
#   0  Every check passed
#   1  One or more checks failed
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/authenticate-user/SKILL.md"
COUNTS="$REPO_ROOT/docs/login-step-counts.md"
ERRORS=0

echo "==> Checking the authenticate-user login flow"
echo ""

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "  FAIL: missing file: ${1#"$REPO_ROOT"/}"
    ERRORS=$((ERRORS + 1))
    return 1
  fi
}

must_contain() {
  local file="$1" needle="$2"
  if grep -qF -- "$needle" "$file"; then
    echo "  [OK] ${file#"$REPO_ROOT"/} names '$needle'"
  else
    echo "  FAIL: ${file#"$REPO_ROOT"/} no longer names '$needle'"
    ERRORS=$((ERRORS + 1))
  fi
}

must_not_contain() {
  local file="$1" needle="$2"
  if grep -qF -- "$needle" "$file"; then
    echo "  FAIL: ${file#"$REPO_ROOT"/} still says '$needle'"
    ERRORS=$((ERRORS + 1))
  else
    echo "  [OK] ${file#"$REPO_ROOT"/} does not say '$needle'"
  fi
}

browser_flow_comes_first() {
  local browser signup
  browser=$(grep -n -m1 -E '^## Sign In' "$SKILL" | cut -d: -f1)
  signup=$(grep -n -m1 -E '^## .*(Login vs Signup|Messaging After)' "$SKILL" | cut -d: -f1)
  if [[ -z "$browser" ]]; then
    echo "  FAIL: authenticate-user/SKILL.md has no '## Sign In' section"
    ERRORS=$((ERRORS + 1))
  elif [[ -z "$signup" || "$browser" -lt "$signup" ]]; then
    echo "  [OK] the browser sign-in section (line $browser) comes before the signup sections"
  else
    echo "  FAIL: a signup section (line $signup) comes before the browser sign-in (line $browser)"
    ERRORS=$((ERRORS + 1))
  fi
}

if require_file "$SKILL"; then
  must_contain "$SKILL" "kpass login --output json"
  must_contain "$SKILL" "kpass login status"
  must_contain "$SKILL" "browser_unavailable"
  must_not_contain "$SKILL" "sends both emails"
  # The four checks above all pass against the pre-change skill, so on their own
  # they would not catch a revert. An agent reads top to bottom: the browser flow
  # has to be the first one it meets.
  browser_flow_comes_first
fi

if require_file "$COUNTS"; then
  must_contain "$COUNTS" "New user, CLI, browser on the machine, to first spending approval"
fi

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "FAILED: $ERRORS error(s) found"
  exit 1
fi
echo "PASSED: All checks passed"
