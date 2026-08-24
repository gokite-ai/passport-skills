#!/usr/bin/env bash
#
# Kite Seller Agent CLI (kagent) Bootstrap Script
#
# Ensures the kagent CLI is installed and available. Installs via the same
# bundle installer the other setup scripts use — that installer provisions
# kpass, kagent, ksearch and passport-skills together, so a seller agent that
# already has kpass usually has this too.
#
# WHY THIS EXISTS SEPARATELY FROM setup.sh: setup.sh ensures kpass, which the
# user and buyer-agent groups drive. The seller-agent group drives kagent, a
# different binary — and nothing checked for it. A seller-agent skill would
# install cleanly against a bundle that never carried kagent and fail on its
# first command.
#
# kagent arrived in CLI 1.11.0. An older bundle installs kpass without it, so
# "the bundle is installed" is not the same as "kagent is present" — which is
# exactly what this script answers.
#
# Usage: bash scripts/setup-kagent.sh [--help]
#
# Output (JSON, stdout):
#   {"status":"ok","cli_version":"kagent 1.11.0","installed_via":"path","binary":"/path/to/kagent"}
#   {"status":"error","error":"..."}
#
# Exit codes:
#   0  kagent is installed (already present, or installed by this script).
#   1  Could not install it.
set -euo pipefail

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Kite Seller Agent CLI (kagent) Bootstrap"
  echo ""
  echo "Ensures kagent >= ${MIN_KAGENT_VERSION} is installed and available on PATH."
  echo "Checks PATH and the standard Kite Passport bundle install locations;"
  echo "installs the bundle automatically if not found."
  echo ""
  echo "Usage: bash scripts/setup-kagent.sh"
  echo ""
  echo "Lookup / install order:"
  echo "  1. Check if kagent is already on PATH"
  echo "  2. Check \${KPASS_INSTALL_DIR:-\$HOME/.kpass}/bin/kagent"
  echo "  3. Check \$HOME/.local/bin/kagent"
  echo "  4. Try: curl -fsSL https://cli.gokite.ai/install.sh | bash"
  echo "  5. Fail with installation instructions"
  echo ""
  echo "Output: JSON to stdout"
  echo "  {\"status\":\"ok\",\"cli_version\":\"...\",\"installed_via\":\"...\",\"binary\":\"...\"}"
  echo "  {\"status\":\"error\",\"error\":\"...\"}"
  exit 0
fi

# ---------------------------------------------------------------------------
# The floor
# ---------------------------------------------------------------------------
# skills.json declares min_kagent_version, and until now this script only
# checked that a kagent binary EXISTED — so any older one on PATH was accepted,
# including versions predating commands the seller-agent skills call.
DEFAULT_MIN_KAGENT_VERSION="1.11.0"  # floor = skills.json min_kagent_version

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_JSON=""
for candidate in "$SCRIPT_DIR/../skills.json" "$SCRIPT_DIR/../../skills.json"; do
  if [[ -f "$candidate" ]]; then SKILLS_JSON="$candidate"; break; fi
done

read_skills_json_field() {
  local field="$1"
  if command -v node &>/dev/null; then
    node -e 'console.log(require(process.argv[1])[process.argv[2]] ?? "")' "$SKILLS_JSON" "$field" 2>/dev/null
  elif command -v python3 &>/dev/null; then
    python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$SKILLS_JSON" "$field" 2>/dev/null
  fi
}

MIN_KAGENT_VERSION="$DEFAULT_MIN_KAGENT_VERSION"
if [[ -n "$SKILLS_JSON" ]]; then
  if PARSED=$(read_skills_json_field min_kagent_version) && [[ -n "$PARSED" && "$PARSED" != "null" ]]; then
    MIN_KAGENT_VERSION="${PARSED%%-*}"  # drop any pre-release tag for numeric compare
  fi
fi

# version_at_least A B — succeeds when A >= B. Numeric major.minor.patch;
# pre-release tags dropped. Fails on unparseable input, so an unreadable version
# counts as too old and gets reinstalled rather than silently accepted.
version_at_least() {
  local a="${1%%-*}" b="${2%%-*}"
  [[ "$a" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 1
  [[ "$b" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 1
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$a"
  IFS=. read -r b1 b2 b3 <<< "$b"
  a3=${a3:-0}; b3=${b3:-0}
  if ((a1 != b1)); then ((a1 > b1)); return; fi
  if ((a2 != b2)); then ((a2 > b2)); return; fi
  ((a3 >= b3))
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# Sanitize a string for safe JSON interpolation (strip newlines, escape quotes)
sanitize_for_json() {
  # shellcheck disable=SC1003 # tr's char-class '"\\' matches literal " and \, not an escape attempt
  printf '%s' "$1" | tr -d '\n' | tr '"\\' '__'
}

# Reports only a kagent that MEETS the floor. Returns 1 otherwise, so the caller
# moves on to the next install method rather than settling for what it found —
# an old binary earlier on PATH can shadow a fresh install, which is exactly the
# case a presence-only check waves through.
report_binary() {
  local binary="$1" installed_via="$2" raw_version version_output binary_output found

  raw_version=$("$binary" --version 2>/dev/null || echo "unknown")
  found=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+[0-9A-Za-z.-]*' <<< "$raw_version" | head -1 || true)
  if [[ -z "$found" ]] || ! version_at_least "$found" "$MIN_KAGENT_VERSION"; then
    echo "kagent at $binary reports '${raw_version}' — below the required ${MIN_KAGENT_VERSION} (or unreadable)." >&2
    return 1
  fi

  version_output=$(sanitize_for_json "$raw_version")
  binary_output=$(sanitize_for_json "$binary")
  echo "{\"status\":\"ok\",\"cli_version\":\"${version_output}\",\"installed_via\":\"${installed_via}\",\"binary\":\"${binary_output}\"}"
}

# try_locate INSTALLED_VIA — checks PATH, then the two known bundle install
# locations. Prints the ok envelope and returns 0 on the first match; returns
# 1 (no output) if kagent isn't found anywhere. INSTALLED_VIA labels a match
# in one of the bundle locations, so callers can distinguish "already there"
# from "just installed" (a PATH match is always reported as "path").
try_locate() {
  local installed_via="$1"

  if command -v kagent &>/dev/null; then
    report_binary "$(command -v kagent)" "path" && return 0
  fi

  local passport_binary="${KPASS_INSTALL_DIR:-$HOME/.kpass}/bin/kagent"
  if [[ -x "$passport_binary" ]]; then
    report_binary "$passport_binary" "$installed_via" && return 0
  fi

  local local_binary="$HOME/.local/bin/kagent"
  if [[ -x "$local_binary" ]]; then
    report_binary "$local_binary" "$installed_via" && return 0
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
echo "kagent not found. Installing the Kite Passport bundle (kpass + kagent + skills) via the official installer (https://cli.gokite.ai/install.sh)..." >&2
if curl -fsSL https://cli.gokite.ai/install.sh | bash >&2; then
  # try_locate's bundle-path checks are PATH-independent, so run it before
  # exporting PATH. Otherwise the PATH-based "command -v" branch matches
  # first and mislabels the fresh install as "path" instead of "installer".
  try_locate "installer" && exit 0
  # The installer typically only updates shell startup files (.bashrc/.zshrc),
  # which this non-interactive script never sources. Export the standard
  # bundle locations directly in case anything downstream in this shell
  # needs kagent on PATH.
  export PATH="${KPASS_INSTALL_DIR:-$HOME/.kpass}/bin:$HOME/.local/bin:$PATH"
fi
echo "Installer did not produce a kagent binary in any known location." >&2

# ---------------------------------------------------------------------------
# Step 3: Nothing worked
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # single-quoted on purpose: \n and $HOME must stay literal in this JSON string, not expand
printf '%s\n' '{"status":"error","error":"Could not install a kagent meeting the required minimum version. Install manually:\n\n  macOS / Linux:  curl -fsSL https://cli.gokite.ai/install.sh | bash\n  Windows:        irm https://cli.gokite.ai/install.ps1 | iex\n\nThen restart your shell or add $HOME/.local/bin to PATH."}'
exit 1
