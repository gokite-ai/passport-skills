#!/usr/bin/env bash
# Copies each shared setup script over every skill-bundled copy of it.
#
# attach-session, authenticate-user and request-session each ship their own
# setup.sh, and kite-discovery ships its own setup-ksearch.sh, because a
# standalone skill install has no shared library to source. Hand-editing those
# copies is how the installer hardening landed in the shared scripts and nowhere
# else. The copies are produced by cp, never edited in place; scripts/validate.sh
# Checks 8 and 9 fail the build when one drifts.
#
# Usage: bash scripts/sync-skill-setup.sh [--check]
#   (no args)  overwrite every copy with its shared source
#   --check    change nothing; exit 1 listing each copy that differs
#
# Exit codes:
#   0  every copy matches its shared source (or was just synced)
#   1  --check found a difference, or a shared source is missing
#   2  bad usage
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# A copy is a file of the same name under any skill's scripts/ directory. The
# names are exact, so the setup.sh sweep never picks up a setup-ksearch.sh.
SOURCE_NAMES=(setup.sh setup-ksearch.sh)

CHECK=0
case "${1:-}" in
  --check) CHECK=1 ;;
  "") ;;
  *) echo "usage: bash scripts/sync-skill-setup.sh [--check]" >&2; exit 2 ;;
esac

# The same copies scripts/validate.sh Checks 7, 8 and 9 read, so a newly added
# copy is synced by the command the validation failure tells you to run.
# scripts/test-setup-drift.sh drifts one copy per source and runs this script on
# it, so a source dropped from the list above cannot report PASSED and do nothing.
copies() {
  local source="$1"
  find "$REPO_ROOT" -maxdepth 3 -name "$(basename "$source")" -path "*/scripts/*" \
    -not -path "*/node_modules/*" | grep -vxF "$source" | sort
}

DIFFERS=0
for name in "${SOURCE_NAMES[@]}"; do
  source="$REPO_ROOT/scripts/$name"
  if [[ ! -f "$source" ]]; then
    echo "FAIL: shared source not found: scripts/$name" >&2
    exit 1
  fi
  while IFS= read -r copy; do
    [[ -n "$copy" ]] || continue
    rel="${copy#"$REPO_ROOT"/}"
    if cmp -s "$source" "$copy"; then
      echo "  [OK] $rel matches scripts/$name"
    elif [[ "$CHECK" -eq 1 ]]; then
      echo "  DIFFERS: $rel"
      DIFFERS=$((DIFFERS + 1))
    else
      cp "$source" "$copy"
      echo "  synced $rel"
    fi
  done < <(copies "$source" || true)
done

if [[ "$DIFFERS" -gt 0 ]]; then
  echo "FAILED: $DIFFERS copy/copies differ from their shared source (run bash scripts/sync-skill-setup.sh)" >&2
  exit 1
fi
echo "PASSED: every skill setup copy matches its shared source"
