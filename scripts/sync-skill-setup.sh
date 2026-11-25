#!/usr/bin/env bash
# Copies scripts/setup.sh over every skill-bundled copy of it.
#
# Each of attach-session, authenticate-user and request-session ships its own
# setup.sh because a standalone skill install has no shared library to source.
# Hand-editing those copies is how the installer hardening landed in
# scripts/setup.sh and nowhere else, leaving three copies piping an
# attacker-supplied URL into bash. The copies are produced by cp and never
# edited in place; scripts/validate.sh fails the build when one drifts.
#
# Usage: bash scripts/sync-skill-setup.sh [--check]
#   (no args)  overwrite every copy with scripts/setup.sh
#   --check    change nothing; exit 1 listing each copy that differs
#
# Exit codes:
#   0  every copy matches the shared source (or was just synced)
#   1  --check found a difference, or the shared source is missing
#   2  bad usage
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$REPO_ROOT/scripts/setup.sh"

CHECK=0
case "${1:-}" in
  --check) CHECK=1 ;;
  "") ;;
  *) echo "usage: bash scripts/sync-skill-setup.sh [--check]" >&2; exit 2 ;;
esac

if [[ ! -f "$SOURCE" ]]; then
  echo "FAIL: shared source not found: scripts/setup.sh" >&2
  exit 1
fi

# Same enumeration as scripts/validate.sh Check 7 and Check 8, so a newly added
# copy is synced by the command the validation failure tells you to run.
copies() {
  find "$REPO_ROOT" -maxdepth 3 -name "setup.sh" -path "*/scripts/*" \
    -not -path "*/node_modules/*" | grep -v "setup-ksearch" | grep -vxF "$SOURCE" | sort
}

DIFFERS=0
while IFS= read -r copy; do
  [[ -n "$copy" ]] || continue
  rel="${copy#"$REPO_ROOT"/}"
  if cmp -s "$SOURCE" "$copy"; then
    echo "  [OK] $rel matches scripts/setup.sh"
  elif [[ "$CHECK" -eq 1 ]]; then
    echo "  DIFFERS: $rel"
    DIFFERS=$((DIFFERS + 1))
  else
    cp "$SOURCE" "$copy"
    echo "  synced $rel"
  fi
done < <(copies || true)

if [[ "$DIFFERS" -gt 0 ]]; then
  echo "FAILED: $DIFFERS copy/copies differ from scripts/setup.sh (run bash scripts/sync-skill-setup.sh)" >&2
  exit 1
fi
echo "PASSED: every skill setup.sh copy matches scripts/setup.sh"
