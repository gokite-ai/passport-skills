#!/usr/bin/env bash
# Kite Passport CLI Bootstrap Script
#
# Ensures the kpass CLI is installed, on PATH, and at least MIN_CLI_VERSION.
# Tries multiple installation methods in order of preference.
#
# Usage: bash setup.sh [--help]
#
# Output: JSON to stdout.
#   {"status":"ok","cli_version":"kpass v1.6.0","installed_via":"existing"}
#   {"status":"ok","cli_version":"kpass v1.6.0","installed_via":"npm"}
#   {"status":"ok","cli_version":"kpass v1.6.0","installed_via":"go"}
#   {"status":"error","error":"..."}
#
# Exit codes:
#   0  kpass >= MIN_CLI_VERSION is available.
#   1  Could not install (or upgrade to) a suitable kpass.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Version pins. skills.json is the source of truth when present (repo root
# layout: ../skills.json; skill-local layout: ../../skills.json). The constants
# below are the fallback for standalone skill installs where skills.json does
# not ship — scripts/validate.sh checks in CI that they stay in sync with
# skills.json, because a drifted fallback silently installs a CLI the skills
# cannot drive.
DEFAULT_CLI_VERSION="1.9.0"  # install target = skills.json max_cli_version
DEFAULT_MIN_CLI_VERSION="1.5.0"  # floor = skills.json min_cli_version (pre-release tag dropped)

SKILLS_JSON=""
for candidate in "$SCRIPT_DIR/../skills.json" "$SCRIPT_DIR/../../skills.json"; do
  if [[ -f "$candidate" ]]; then
    SKILLS_JSON="$candidate"
    break
  fi
done

read_skills_json_field() {
  local field="$1"
  if command -v jq &>/dev/null; then
    jq -r ".${field}" "$SKILLS_JSON"
  elif command -v node &>/dev/null; then
    node -e 'console.log(require(process.argv[1])[process.argv[2]])' "$SKILLS_JSON" "$field"
  elif command -v python3 &>/dev/null; then
    python3 -c "import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$SKILLS_JSON" "$field"
  else
    return 1
  fi
}

CLI_VERSION="$DEFAULT_CLI_VERSION"
MIN_CLI_VERSION="$DEFAULT_MIN_CLI_VERSION"
if [[ -n "$SKILLS_JSON" ]]; then
  if PARSED=$(read_skills_json_field max_cli_version 2>/dev/null) && [[ -n "$PARSED" && "$PARSED" != "null" ]]; then
    CLI_VERSION="$PARSED"
  fi
  if PARSED=$(read_skills_json_field min_cli_version 2>/dev/null) && [[ -n "$PARSED" && "$PARSED" != "null" ]]; then
    MIN_CLI_VERSION="${PARSED%%-*}"  # drop pre-release tag for numeric compare
  fi
fi

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Kite Passport CLI Bootstrap"
  echo ""
  echo "Ensures kpass >= ${MIN_CLI_VERSION} is installed and available on PATH."
  echo "If not found (or too old), attempts to install it automatically."
  echo ""
  echo "Usage: bash setup.sh"
  echo ""
  echo "Installation order:"
  echo "  1. Check if kpass >= ${MIN_CLI_VERSION} is already on PATH"
  echo "  2. Try: npm install -g kpass@${CLI_VERSION}"
  echo "  3. Try: go install github.com/gokite-ai/passport-cli/cmd/kpass@v${CLI_VERSION}"
  echo "  4. Fail with installation instructions"
  echo ""
  echo "Output: JSON to stdout"
  echo "  {\"status\":\"ok\",\"cli_version\":\"...\",\"installed_via\":\"...\"}"
  echo "  {\"status\":\"error\",\"error\":\"...\"}"
  exit 0
fi

# version_at_least A B — succeeds when A >= B. Compares numeric
# major.minor.patch; pre-release tags are dropped (so 1.5.0-rc.1 counts as
# 1.5.0). Fails on unparseable input so callers treat unknown versions as
# too old and reinstall.
version_at_least() {
  local a="${1%%-*}" b="${2%%-*}"
  [[ "$a" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 1
  [[ "$b" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 1
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$a"
  IFS=. read -r b1 b2 b3 <<< "$b"
  a3=${a3:-0}
  b3=${b3:-0}
  if ((a1 != b1)); then ((a1 > b1)); return; fi
  if ((a2 != b2)); then ((a2 > b2)); return; fi
  ((a3 >= b3))
}

# report_if_suitable VIA — if the kpass now reachable on PATH meets
# MIN_CLI_VERSION, print the ok envelope and exit 0. Otherwise return 1 so the
# caller can try the next install method. The post-install version re-check
# matters: an old binary earlier on PATH can shadow a fresh install.
report_if_suitable() {
  local via="$1"
  command -v kpass &>/dev/null || return 1
  local version_output installed_version
  version_output=$(kpass --version 2>/dev/null || echo "unknown")
  installed_version=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+[0-9A-Za-z.-]*' <<< "$version_output" | head -1 || true)
  if [[ -n "$installed_version" ]] && version_at_least "$installed_version" "$MIN_CLI_VERSION"; then
    echo "{\"status\":\"ok\",\"cli_version\":\"${version_output}\",\"installed_via\":\"${via}\"}"
    exit 0
  fi
  echo "kpass on PATH reports '${version_output}' — below required ${MIN_CLI_VERSION} (or unreadable)." >&2
  return 1
}

# ---------------------------------------------------------------------------
# Step 1: Already installed and recent enough?
# ---------------------------------------------------------------------------
report_if_suitable "existing" || true
if command -v kpass &>/dev/null; then
  echo "Upgrading to kpass@${CLI_VERSION}..." >&2
fi

# ---------------------------------------------------------------------------
# Step 2: Try npm install -g
# ---------------------------------------------------------------------------
if command -v npm &>/dev/null; then
  echo "Installing via npm..." >&2
  if npm install -g "kpass@${CLI_VERSION}" >&2; then
    report_if_suitable "npm" || true
  fi
  echo "npm install failed, or the kpass on PATH is still unsuitable." >&2
fi

# ---------------------------------------------------------------------------
# Step 3: Try go install
# ---------------------------------------------------------------------------
if command -v go &>/dev/null; then
  echo "Trying go install..." >&2
  if go install "github.com/gokite-ai/passport-cli/cmd/kpass@v${CLI_VERSION}" >&2; then
    report_if_suitable "go" || true
    # go install honors GOBIN when set, else GOPATH/bin — either may be off PATH.
    GO_BIN_DIR="$(go env GOBIN)"
    [[ -z "$GO_BIN_DIR" ]] && GO_BIN_DIR="$(go env GOPATH)/bin"
    GOBIN_PATH="$GO_BIN_DIR/kpass"
    if [[ -x "$GOBIN_PATH" ]]; then
      VERSION_OUTPUT=$("$GOBIN_PATH" --version 2>/dev/null || echo "unknown")
      INSTALLED_VERSION=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+[0-9A-Za-z.-]*' <<< "$VERSION_OUTPUT" | head -1 || true)
      if [[ -n "$INSTALLED_VERSION" ]] && version_at_least "$INSTALLED_VERSION" "$MIN_CLI_VERSION"; then
        echo "{\"status\":\"ok\",\"cli_version\":\"${VERSION_OUTPUT}\",\"installed_via\":\"go\",\"note\":\"Binary installed at ${GOBIN_PATH} but not on PATH (or an older kpass shadows it). Put ${GO_BIN_DIR} first on your PATH.\"}"
        exit 0
      fi
      echo "{\"status\":\"error\",\"error\":\"go install produced kpass at ${GOBIN_PATH} reporting '${VERSION_OUTPUT}' — below required ${MIN_CLI_VERSION} (or unreadable). Put ${GO_BIN_DIR} first on your PATH if an older kpass on PATH is shadowing it, or reinstall.\"}"
      exit 1
    fi
  fi
  echo "go install failed." >&2
fi

# ---------------------------------------------------------------------------
# Step 4: Nothing worked
# ---------------------------------------------------------------------------
cat <<EOF
{"status":"error","error":"Could not install kpass >= ${MIN_CLI_VERSION}. Install manually using one of these methods:\n\n  Option 1 (npm):  npm install -g kpass@${CLI_VERSION}\n  Option 2 (Go):   go install github.com/gokite-ai/passport-cli/cmd/kpass@v${CLI_VERSION}\n  Option 3 (source): git clone https://github.com/gokite-ai/passport-cli && cd passport-cli && make install\n\nThen ensure the binary is on your PATH (before any older kpass)."}
EOF
exit 1
