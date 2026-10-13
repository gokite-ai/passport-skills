#!/usr/bin/env bash
set -euo pipefail

# Test set-installer-base.sh behaviour
# Expected output: "PASS n/6" or "FAIL n/6"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "$TESTDIR"' EXIT

# Copy scripts/ directory and .installer-base to test dir
cp -r "$(dirname "${BASH_SOURCE[0]}")" "$TESTDIR/"
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../.installer-base" ]]; then
  cp "$(dirname "${BASH_SOURCE[0]}")/../.installer-base" "$TESTDIR/"
fi

SCRIPT="$TESTDIR/scripts/set-installer-base.sh"
BASE_FILE="$TESTDIR/.installer-base"

# Stub curl that logs the URL
cat > "$TESTDIR/scripts/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    http*install.sh) echo "$arg" >> "$CURL_LOG"; exit 0;;
  esac
done
exit 1
STUB
chmod +x "$TESTDIR/scripts/curl"

export HOME="$TESTDIR"
export CURL_LOG="$TESTDIR/curl.log"

pass=0
total=6

# Test 1: INSTALLER_ENV unset gives prod, and setup.sh uses it
unset INSTALLER_ENV
: > "$CURL_LOG"
bash "$SCRIPT" "" "$TESTDIR" >/dev/null 2>&1
setup_output=$(PATH="$TESTDIR/scripts:$PATH" bash "$TESTDIR/scripts/setup.sh" 2>&1 || true)
if [[ "$(cat "$BASE_FILE")" == "https://cli.gokite.ai" ]] && \
   echo "$setup_output" | grep -q "https://cli.gokite.ai/install" && \
   grep -q "https://cli.gokite.ai/install.sh" "$CURL_LOG"; then
  pass=$((pass + 1))
fi

# Test 2: argument "prod" gives prod
rm -f "$BASE_FILE"
if bash "$SCRIPT" prod "$TESTDIR" >/dev/null 2>&1 && \
   [[ "$(cat "$BASE_FILE")" == "https://cli.gokite.ai" ]]; then
  pass=$((pass + 1))
fi

# Test 3: argument "staging" gives staging, and setup.sh uses it
rm -f "$BASE_FILE"
: > "$CURL_LOG"
bash "$SCRIPT" staging "$TESTDIR" >/dev/null 2>&1
setup_output=$(PATH="$TESTDIR/scripts:$PATH" bash "$TESTDIR/scripts/setup.sh" 2>&1 || true)
if [[ "$(cat "$BASE_FILE")" == "https://cli.staging.gokite.ai" ]] && \
   echo "$setup_output" | grep -q "https://cli.staging.gokite.ai/install" && \
   grep -q "https://cli.staging.gokite.ai/install.sh" "$CURL_LOG"; then
  pass=$((pass + 1))
fi

# Test 4: argument "bogus" exits 1 and leaves file unchanged
echo "https://cli.gokite.ai" > "$BASE_FILE"
if ! bash "$SCRIPT" bogus "$TESTDIR" 2>/dev/null && \
   [[ "$(cat "$BASE_FILE")" == "https://cli.gokite.ai" ]]; then
  pass=$((pass + 1))
fi

# Test 5: --check on staging file exits 1
echo "https://cli.staging.gokite.ai" > "$BASE_FILE"
if ! bash "$SCRIPT" --check "$TESTDIR" 2>/dev/null; then
  pass=$((pass + 1))
fi

# Test 6: --check on prod file exits 0
echo "https://cli.gokite.ai" > "$BASE_FILE"
if bash "$SCRIPT" --check "$TESTDIR" >/dev/null 2>&1; then
  pass=$((pass + 1))
fi

if [[ "$pass" -eq "$total" ]]; then
  echo "PASS $pass/$total"
  exit 0
else
  echo "FAIL $pass/$total"
  exit 1
fi
