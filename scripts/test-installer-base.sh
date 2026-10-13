#!/usr/bin/env bash
set -euo pipefail

# Test that the installer fallback in authenticate-user, request-session,
# attach-session, kite-discovery, scripts/setup.sh, and scripts/setup-ksearch.sh
# honours KPASS_BASE_URL (production default).

TESTDIR="$(mktemp -d)"
trap 'rm -rf "$TESTDIR"' EXIT

# Stub curl that logs the URL and exits successfully
cat > "$TESTDIR/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    http*) echo "$arg" >> "$CURL_LOG"; exit 0;;
  esac
done
exit 1
STUB
chmod +x "$TESTDIR/curl"

# Stub .installer-base file
echo "https://cli.gokite.ai" > "$TESTDIR/.installer-base"

export PATH="$TESTDIR:$PATH"
export CURL_LOG="$TESTDIR/curl.log"
export HOME="$TESTDIR"

SCRIPTS=(
  "authenticate-user/scripts/setup.sh"
  "request-session/scripts/setup.sh"
  "attach-session/scripts/setup.sh"
  "kite-discovery/scripts/setup-ksearch.sh"
  "scripts/setup.sh"
  "scripts/setup-ksearch.sh"
)

pass=0
total=0

for script in "${SCRIPTS[@]}"; do
  # Test 1: with KPASS_BASE_URL set to staging
  : > "$CURL_LOG"
  export KPASS_BASE_URL="https://cli.staging.gokite.ai"
  output=$(bash "$script" 2>&1 || true)
  
  total=$((total + 1))
  if grep -q "https://cli.staging.gokite.ai/install.sh" "$CURL_LOG" && \
     echo "$output" | grep -q "https://cli.staging.gokite.ai/install"; then
    pass=$((pass + 1))
    echo "PASS: $script with KPASS_BASE_URL=staging"
  else
    echo "FAIL: $script with KPASS_BASE_URL=staging"
    echo "  Expected: https://cli.staging.gokite.ai/install.sh"
    echo "  Got (curl): $(cat "$CURL_LOG")"
    echo "  Got (hint): $(echo "$output" | grep -o 'https://[^ ]*install[^ ]*' | head -1)"
  fi
  
  # Test 2: with KPASS_BASE_URL unset (production default)
  : > "$CURL_LOG"
  unset KPASS_BASE_URL
  output=$(bash "$script" 2>&1 || true)
  
  total=$((total + 1))
  if grep -q "https://cli.gokite.ai/install.sh" "$CURL_LOG" && \
     echo "$output" | grep -q "https://cli.gokite.ai/install"; then
    pass=$((pass + 1))
    echo "PASS: $script with KPASS_BASE_URL unset"
  else
    echo "FAIL: $script with KPASS_BASE_URL unset"
    echo "  Expected: https://cli.gokite.ai/install.sh"
    echo "  Got (curl): $(cat "$CURL_LOG")"
    echo "  Got (hint): $(echo "$output" | grep -o 'https://[^ ]*install[^ ]*' | head -1)"
  fi
done

echo ""
if [ "$pass" -eq "$total" ]; then
  echo "PASS $pass/$total"
  exit 0
else
  echo "FAIL $pass/$total"
  exit 1
fi
