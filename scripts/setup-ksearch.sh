#!/usr/bin/env bash
# Kite Discovery CLI (ksearch) Bootstrap Script
#
# Ensures the ksearch CLI is installed and available. Installs via the
# official bundle installer (https://cli.gokite.ai/install.sh) when missing --
# that installer provisions kpass, ksearch, and passport-skills together, so
# this mirrors scripts/setup.sh's auto-install behavior for consistency.
#
# Usage: bash scripts/setup-ksearch.sh [--help]
#
# Output: JSON to stdout.
#   {"status":"ok","cli_version":"ksearch 1.0.4","installed_via":"path","binary":"/path/to/ksearch"}
#   {"status":"ok","cli_version":"ksearch 1.0.4","installed_via":"passport-bundle","binary":"/home/user/.kpass/bin/ksearch"}
#   {"status":"ok","cli_version":"ksearch 1.0.4","installed_via":"installer","binary":"/home/user/.kpass/bin/ksearch"}
#   {"status":"error","error":"..."}
#
# Exit codes:
#   0  ksearch is installed (already present, or installed by this script).
#   1  ksearch could not be found or installed.
set -euo pipefail

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Kite Discovery CLI (ksearch) Bootstrap"
  echo ""
  echo "Ensures ksearch is installed and available on PATH."
  echo "Checks PATH and the standard Kite Passport bundle install locations;"
  echo "installs the bundle automatically if not found."
  echo ""
  echo "Usage: bash scripts/setup-ksearch.sh"
  echo ""
  echo "Lookup / install order:"
  echo "  1. Check if ksearch is already on PATH"
  echo "  2. Check \${KPASS_INSTALL_DIR:-\$HOME/.kpass}/bin/ksearch"
  echo "  3. Check \$HOME/.local/bin/ksearch"
  echo "  4. Try: curl -fsSL https://cli.gokite.ai/install.sh | bash"
  echo "  5. Fail with installation instructions"
  echo ""
  echo "Output: JSON to stdout"
  echo "  {\"status\":\"ok\",\"cli_version\":\"...\",\"installed_via\":\"...\",\"binary\":\"...\"}"
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

# try_locate INSTALLED_VIA — checks PATH, then the two known bundle install
# locations. Prints the ok envelope and returns 0 on the first match; returns
# 1 (no output) if ksearch isn't found anywhere. INSTALLED_VIA labels a match
# in one of the bundle locations, so callers can distinguish "already there"
# from "just installed" (a PATH match is always reported as "path").
try_locate() {
  local installed_via="$1"

  if command -v ksearch &>/dev/null; then
    report_binary "$(command -v ksearch)" "path"
    return 0
  fi

  local passport_binary="${KPASS_INSTALL_DIR:-$HOME/.kpass}/bin/ksearch"
  if [[ -x "$passport_binary" ]]; then
    report_binary "$passport_binary" "$installed_via"
    return 0
  fi

  local local_binary="$HOME/.local/bin/ksearch"
  if [[ -x "$local_binary" ]]; then
    report_binary "$local_binary" "$installed_via"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Step 1: Already installed?
# ---------------------------------------------------------------------------
try_locate "passport-bundle" && exit 0

# ---------------------------------------------------------------------------
# Step 2: Install via the official bundle installer
# ---------------------------------------------------------------------------
echo "ksearch not found. Installing the Kite Passport bundle (kpass + ksearch + skills) via the official installer (https://cli.gokite.ai/install.sh)..." >&2
if curl -fsSL https://cli.gokite.ai/install.sh | bash >&2; then
  # try_locate's bundle-path checks are PATH-independent, so run it before
  # exporting PATH. Otherwise the PATH-based "command -v" branch matches
  # first and mislabels the fresh install as "path" instead of "installer".
  try_locate "installer" && exit 0
  # The installer typically only updates shell startup files (.bashrc/.zshrc),
  # which this non-interactive script never sources. Export the standard
  # bundle locations directly in case anything downstream in this shell
  # needs ksearch on PATH.
  export PATH="${KPASS_INSTALL_DIR:-$HOME/.kpass}/bin:$HOME/.local/bin:$PATH"
fi
echo "Installer did not produce a ksearch binary in any known location." >&2

# ---------------------------------------------------------------------------
# Step 3: Nothing worked
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # single-quoted on purpose: \n and $HOME must stay literal in this JSON string, not expand
printf '%s\n' '{"status":"error","error":"Could not install ksearch. Install manually:\n\n  macOS / Linux:  curl -fsSL https://cli.gokite.ai/install.sh | bash\n  Windows:        irm https://cli.gokite.ai/install.ps1 | iex\n\nThen restart your shell or add $HOME/.local/bin to PATH."}'
exit 1
