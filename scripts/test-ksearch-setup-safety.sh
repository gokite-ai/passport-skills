#!/usr/bin/env bash
# Proves the installer hardening holds in scripts/setup-ksearch.sh and in every
# skill-bundled copy of it. The copies are byte-identical today; this test is
# what fails when one stops being hardened, and it says which one.
#
# Each case runs a copy with a stub curl first on PATH, no ksearch reachable,
# and a throwaway HOME. The stub logs its full argv and, per STUB_MODE, writes a
# would-be installer whose only effect is to create a marker file, so "the
# installer ran" is a file that exists and "it did not" is a file that does not.
#
# Usage: bash scripts/test-ksearch-setup-safety.sh
# Exit codes:
#   0  every case passed for every copy (prints PASSED)
#   1  at least one case failed, or the environment cannot host the test
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

COPIES=(
  scripts/setup-ksearch.sh
  kite-discovery/scripts/setup-ksearch.sh
)

# Two of these pin a regression the rest of the list misses. A sibling subdomain
# fails a regex widened to any *.gokite.ai host, which is the shape a takeover of
# one DNS record would need. A base that ends in the official host fails only
# while the regex keeps its leading anchor, because an unanchored match finds
# that host anywhere in the value. The allowlist names two hosts, not a domain,
# and it has to match the whole value.
REFUSED_BASES=(
  "https://evil.example"
  "http://cli.gokite.ai"
  "https://cli.gokite.ai.evil.example"
  "https://cli.gokite.ai/x"
  "https://attacker.gokite.ai"
  "https://evil.example/?u=https://cli.gokite.ai"
)

if command -v ksearch &>/dev/null; then
  echo "FAIL: a real ksearch is reachable at $(command -v ksearch); this test needs a PATH without one" >&2
  exit 1
fi
for copy in "${COPIES[@]}"; do
  [[ -f "$REPO_ROOT/$copy" ]] || { echo "FAIL: missing copy $copy" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

unset KPASS_BASE_URL KPASS_INSTALL_DIR
export HOME="$WORK/home"
export CURL_LOG="$WORK/curl.log"
export INSTALLER_MARKER="$WORK/installer-ran"
BASE_MARKER="$WORK/base-expanded"
RUN_CWD="$WORK/cwd"
OUT="$WORK/stdout"
ERR="$WORK/stderr"
mkdir -p "$HOME" "$RUN_CWD" "$WORK/bin"

REFUSED_BASES+=("https://cli.gokite.ai\$(touch $BASE_MARKER)")

cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
out="" prev=""
for arg in "$@"; do
  [[ "$prev" == "-o" ]] && out="$arg"
  prev="$arg"
done
body="#!/usr/bin/env bash"$'\n'"touch \"$INSTALLER_MARKER\""$'\n'
case "${STUB_MODE:-}" in
  ok) rc=0 ;;
  download-fails) rc=22 ;;
  redirect-refused) rc=47 ;;
  non-script) body="touch \"$INSTALLER_MARKER\""$'\n'; rc=0 ;;
  *) echo "stub curl: unknown STUB_MODE '${STUB_MODE:-}'" >&2; exit 99 ;;
esac
if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
exit "$rc"
STUB
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"

FAILED=0
COPY=""
CASE=""

expect() {
  local what="$1"; shift
  if "$@"; then
    echo "PASS: $COPY | $CASE | $what"
  else
    echo "FAIL: $COPY | $CASE | $what"
    FAILED=$((FAILED + 1))
    sed 's/^/    stdout: /' "$OUT"
    sed 's/^/    stderr: /' "$ERR"
    if [[ -s "$CURL_LOG" ]]; then
      sed 's/^/    curl:   /' "$CURL_LOG"
    fi
  fi
}

not() { ! "$@"; }

# run_setup MODE BASE runs the current copy with STUB_MODE=MODE and
# KPASS_BASE_URL=BASE (unset when BASE is empty). Sets STATUS; stdout and
# stderr land in $OUT and $ERR.
run_setup() {
  local mode="$1" base="$2"
  : > "$CURL_LOG"
  rm -f "$INSTALLER_MARKER" "$BASE_MARKER"
  STATUS=0
  (
    cd "$RUN_CWD"
    unset KPASS_BASE_URL
    [[ -n "$base" ]] && export KPASS_BASE_URL="$base"
    STUB_MODE="$mode" bash "$REPO_ROOT/$COPY" > "$OUT" 2> "$ERR"
  ) || STATUS=$?
}

curl_calls() { grep -c '' "$CURL_LOG" || true; }

for COPY in "${COPIES[@]}"; do
  for base in "${REFUSED_BASES[@]}"; do
    CASE="refused base $base"
    run_setup ok "$base"
    expect "exit status 1 (got $STATUS)" test "$STATUS" -eq 1
    expect "curl never invoked ($(curl_calls) calls)" test ! -s "$CURL_LOG"
    expect "base string not expanded as code" test ! -e "$BASE_MARKER"
    expect "no ok envelope on stdout" not grep -qF '"status":"ok"' "$OUT"
  done

  CASE="download fails (curl exit 22)"
  run_setup download-fails ""
  expect "exit status 1 (got $STATUS)" test "$STATUS" -eq 1
  expect "installer did not run" test ! -e "$INSTALLER_MARKER"
  expect "stdout says Install manually" grep -qF 'Install manually' "$OUT"

  CASE="redirect refused (curl exit 47)"
  run_setup redirect-refused ""
  expect "exit status 1 (got $STATUS)" test "$STATUS" -eq 1
  expect "installer did not run" test ! -e "$INSTALLER_MARKER"
  expect "stdout says Install manually" grep -qF 'Install manually' "$OUT"

  CASE="non-script body"
  run_setup non-script ""
  expect "exit status 1 (got $STATUS)" test "$STATUS" -eq 1
  expect "installer did not run" test ! -e "$INSTALLER_MARKER"
  expect "stdout says Install manually" grep -qF 'Install manually' "$OUT"

  CASE="official base (KPASS_BASE_URL unset)"
  run_setup ok ""
  expect "curl invoked once ($(curl_calls) calls)" test "$(curl_calls)" -eq 1
  expect "asked for https://cli.gokite.ai/install.sh" grep -qE '(^| )https://cli\.gokite\.ai/install\.sh( |$)' "$CURL_LOG"
  expect "argv has --proto =https" grep -qF -- '--proto =https' "$CURL_LOG"
  expect "argv has --proto-redir =https" grep -qF -- '--proto-redir =https' "$CURL_LOG"
  expect "argv has --max-redirs 0" grep -qF -- '--max-redirs 0' "$CURL_LOG"
  expect "argv has -o" grep -qE '(^| )-o( |$)' "$CURL_LOG"
  expect "a well-formed download does run the installer" test -e "$INSTALLER_MARKER"

  CASE="official base (KPASS_BASE_URL=https://cli.staging.gokite.ai)"
  run_setup ok "https://cli.staging.gokite.ai"
  expect "curl invoked once ($(curl_calls) calls)" test "$(curl_calls)" -eq 1
  expect "asked for https://cli.staging.gokite.ai/install.sh" grep -qE '(^| )https://cli\.staging\.gokite\.ai/install\.sh( |$)' "$CURL_LOG"
done

echo ""
echo "summary: $FAILED failed"
if [[ "$FAILED" -gt 0 ]]; then
  echo "FAILED: $FAILED check(s) failed"
  exit 1
fi
echo "PASSED"
