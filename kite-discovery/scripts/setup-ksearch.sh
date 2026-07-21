#!/usr/bin/env bash
# Kite Discovery CLI (ksearch) Bootstrap Script
#
# Ensures the ksearch CLI installed by the Passport bundle is available.
#
# Usage: bash scripts/setup-ksearch.sh [--help]
#
# Output: JSON to stdout.
#   {"status":"ok","cli_version":"ksearch 1.0.4","installed_via":"path","binary":"/path/to/ksearch"}
#   {"status":"ok","cli_version":"ksearch 1.0.4","installed_via":"passport-bundle","binary":"/home/user/.kpass/bin/ksearch"}
#   {"status":"error","error":"..."}
#
# Exit codes:
#   0  ksearch is installed.
#   1  ksearch could not be found.
set -euo pipefail

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Kite Discovery CLI (ksearch) Bootstrap"
  echo ""
  echo "Ensures ksearch is installed and available on PATH."
  echo "Checks PATH and the standard Kite Passport bundle install locations."
  echo ""
  echo "Usage: bash scripts/setup-ksearch.sh"
  echo ""
  echo "Lookup order:"
  echo "  1. Check if ksearch is already on PATH"
  echo "  2. Check \${KPASS_INSTALL_DIR:-\$HOME/.kpass}/bin/ksearch"
  echo "  3. Check \$HOME/.local/bin/ksearch"
  echo ""
  echo "Output: JSON to stdout"
  echo "  {\"status\":\"ok\",\"cli_version\":\"...\",\"installed_via\":\"...\"}"
  echo "  {\"status\":\"error\",\"error\":\"...\"}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# Sanitize a string for safe JSON interpolation (strip newlines, escape quotes)
sanitize_for_json() {
  # shellcheck disable=SC1003 # tr's char-class '"\\' matches literal " and \, not an escape attempt
  printf '%s' "$1" | tr -d '\n' | tr '"\\' '__'
}

report_binary() {
  local binary="$1" installed_via="$2" raw_version version_output binary_output

  raw_version=$("$binary" --version 2>/dev/null || echo "unknown")
  version_output=$(sanitize_for_json "$raw_version")
  binary_output=$(sanitize_for_json "$binary")
  echo "{\"status\":\"ok\",\"cli_version\":\"${version_output}\",\"installed_via\":\"${installed_via}\",\"binary\":\"${binary_output}\"}"
}

# ---------------------------------------------------------------------------
# Locate the binary
# ---------------------------------------------------------------------------
if command -v ksearch &>/dev/null; then
  report_binary "$(command -v ksearch)" "path"
  exit 0
fi

PASSPORT_BINARY="${KPASS_INSTALL_DIR:-$HOME/.kpass}/bin/ksearch"
if [[ -x "$PASSPORT_BINARY" ]]; then
  report_binary "$PASSPORT_BINARY" "passport-bundle"
  exit 0
fi

LOCAL_BINARY="$HOME/.local/bin/ksearch"
if [[ -x "$LOCAL_BINARY" ]]; then
  report_binary "$LOCAL_BINARY" "passport-bundle"
  exit 0
fi

# ---------------------------------------------------------------------------
# Not installed
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # single-quoted on purpose: \n and $HOME must stay literal in this JSON string, not expand
printf '%s\n' '{"status":"error","error":"ksearch was not found. Install the Kite Passport bundle, which includes kpass and ksearch:\n\n  curl -fsSL https://agentpassport.ai/install.sh | bash\n\nThen restart your shell or add $HOME/.local/bin to PATH."}'
exit 1
