#!/usr/bin/env bash
# Proves the installer hardening holds in EVERY skill-bundled copy of setup.sh,
# not only in scripts/setup.sh. The copies are byte-identical today; this test
# is what fails when one stops being hardened, and it says which one.
#
# Each case runs a copy with a stub curl first on PATH, no kpass reachable, and
# a throwaway HOME. The stub logs its full argv and, per STUB_MODE, writes a
# would-be installer whose only effect is to create a marker file, so "the
# installer ran" is a file that exists and "it did not" is a file that does not.
#
# Usage: bash scripts/test-skill-setup-safety.sh
# Exit codes:
#   0  every case passed for every copy (prints PASSED)
#   1  at least one case failed, or the environment cannot host the test
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

COPIES=(
  attach-session/scripts/setup.sh
  authenticate-user/scripts/setup.sh
  request-session/scripts/setup.sh
)

REFUSED_BASES=(
  "https://evil.example"
  "http://cli.gokite.ai"
  "https://cli.gokite.ai.evil.example"
  "https://cli.gokite.ai/x"
)

if command -v kpass &>/dev/null; then
  echo "FAIL: a real kpass is reachable at $(command -v kpass); this test needs a PATH without one" >&2
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
SKIPPED=0
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

# run_setup MODE BASE [ARGS...] runs the current copy with STUB_MODE=MODE and
# KPASS_BASE_URL=BASE (unset when BASE is empty). Sets STATUS; stdout and
# stderr land in $OUT and $ERR.
run_setup() {
  local mode="$1" base="$2"; shift 2
  : > "$CURL_LOG"
  rm -f "$INSTALLER_MARKER" "$BASE_MARKER"
  STATUS=0
  (
    cd "$RUN_CWD"
    unset KPASS_BASE_URL
    [[ -n "$base" ]] && export KPASS_BASE_URL="$base"
    STUB_MODE="$mode" bash "$REPO_ROOT/$COPY" "$@" > "$OUT" 2> "$ERR"
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

# Markers for the hostile-path cases. A directory-name payload can run only a
# RELATIVE `touch`, because a path component cannot hold a '/', so its effect
# lands in the run's cwd; a `touch` symlink is added to every variant bin below
# and the marker is checked both there and anywhere under $WORK.
DIR_MARKER_NAME="dir-marker"
JSON_MARKER="$WORK/json-marker"

# min_kpass_version is never spliced into code in either version — only the PATH
# is — so this value-level marker is an inert forward guard, not a catch for the
# old interpolation bug. It still must carry quotes and $(...) per the ticket,
# and every run must echo it verbatim, which is what proves the parser actually
# read the hostile-named path instead of silently falling back to the default.
HOSTILE_VERSION="6.8.9'\"; \$(touch $JSON_MARKER)"

# A shell payload ($(touch ...)) is inert inside a JS or Python string literal,
# so it cannot catch a reintroduced path interpolation; each parser needs a
# payload in ITS OWN language that breaks out of the single-quoted string the
# pre-hardening code spliced the path into. node and python3 cannot share one
# directory name: the parser compiles the whole program first, so whichever ran
# second would throw before its touch once the first had already fired. jq takes
# the path as argv in both versions, so no executable payload is possible and it
# keeps a shell-metacharacter-only name. The ticket-required ', ", ; and
# $(touch <marker>) ride in a trailing single-quoted literal so the spliced
# program still parses and the injected touch runs. Each name holds all four and
# no '/'.
SHELL_META="it's \"x\"; \$(touch $DIR_MARKER_NAME)"
declare -A HOSTILE_DIRNAME=(
  [jq]="$SHELL_META"
  [node]="x'+require(\"child_process\").execSync(\"touch $DIR_MARKER_NAME\")+'; \"\$(touch $DIR_MARKER_NAME)\" y"
  [python3]="x'+__import__(\"os\").system(\"touch $DIR_MARKER_NAME\")+'; \"\$(touch $DIR_MARKER_NAME)\" y"
)

# One hostile parent per variant, each with its own skills.json carrying the
# hostile version. The copies ship no skills.json, so setup.sh resolves the
# ../../skills.json candidate here, whose PATH carries the variant's payload.
declare -A HOSTILE_PARENT_DIR
for variant in jq node python3; do
  parent="$WORK/${HOSTILE_DIRNAME[$variant]}"
  mkdir -p "$parent"
  printf '{"min_kpass_version": "%s"}\n' "${HOSTILE_VERSION//\"/\\\"}" > "$parent/skills.json"
  HOSTILE_PARENT_DIR[$variant]="$parent"
done

BASH_BIN="$(command -v bash)"
DIRNAME_BIN="$(command -v dirname)"
TOUCH_BIN="$(command -v touch)"

# variant_bin NAME TOOL... builds $WORK/path-NAME holding only dirname, touch,
# and the listed tools, so PATH alone decides which parser branch setup.sh takes.
# touch is present so a payload's relative `touch` CAN run: its absent marker is
# the proof the path was read as data. setup.sh's own --help path never calls
# touch, so adding it does not change which parser branch is chosen.
variant_bin() {
  local name="$1"; shift
  local dir="$WORK/path-$name" tool
  mkdir -p "$dir"
  ln -sf "$DIRNAME_BIN" "$dir/dirname"
  ln -sf "$TOUCH_BIN" "$dir/touch"
  for tool in "$@"; do
    ln -sf "$(command -v "$tool")" "$dir/$tool"
  done
  printf '%s' "$dir"
}

run_help_restricted() {
  local copy_script="$1" path="$2"
  : > "$CURL_LOG"
  rm -f "$JSON_MARKER" "$RUN_CWD/$DIR_MARKER_NAME"
  STATUS=0
  (
    cd "$RUN_CWD"
    unset KPASS_BASE_URL
    PATH="$path" "$BASH_BIN" "$copy_script" --help > "$OUT" 2> "$ERR"
  ) || STATUS=$?
}

no_marker_anywhere() { [[ -z "$(find "$WORK" -name "$DIR_MARKER_NAME" -print -quit)" ]]; }

for COPY in "${COPIES[@]}"; do
  skill_dir="$(dirname "$(dirname "$COPY")")"
  for variant in jq node python3; do
    CASE="hostile path + skills.json via $variant"
    if ! command -v "$variant" &>/dev/null; then
      echo "SKIP: $COPY | $CASE | $variant is not installed"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    parent="${HOSTILE_PARENT_DIR[$variant]}"
    rm -rf "${parent:?}/$skill_dir"
    cp -R "$REPO_ROOT/$skill_dir" "$parent/"
    copy_script="$parent/$skill_dir/scripts/setup.sh"
    run_help_restricted "$copy_script" "$(variant_bin "$variant" "$variant")"
    expect "exit status 0 (got $STATUS)" test "$STATUS" -eq 0
    expect "help shows the hostile min_kpass_version verbatim" grep -qF -- "$HOSTILE_VERSION" "$OUT"
    expect "skills.json value not expanded as code" test ! -e "$JSON_MARKER"
    expect "directory name not expanded as code in cwd" test ! -e "$RUN_CWD/$DIR_MARKER_NAME"
    expect "directory name not expanded as code" no_marker_anywhere
  done
done

echo ""
echo "summary: $FAILED failed, $SKIPPED skipped"
if [[ "$FAILED" -gt 0 || "$SKIPPED" -gt 0 ]]; then
  echo "FAILED: $FAILED check(s) failed, $SKIPPED variant(s) skipped"
  exit 1
fi
echo "PASSED"
