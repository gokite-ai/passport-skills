#!/usr/bin/env bash
# Tests scripts/list-affected-releases.sh against a throwaway git repository
# whose tags each hold a known mix of hardened and vulnerable setup copies.
#
# The case that matters most is the hardened fixture (v2.0.0). The real
# hardened copy still PRINTS "curl ... | bash" in its --help text and in its
# JSON error envelope, and still runs node -e and python3 -c with the path as a
# separate argument. A classifier that greps loosely calls that copy affected.
# Each vulnerable fixture is the hardened text plus one change, so a flip from
# fixed to affected shows which single rule fired.
#
# Usage: bash scripts/test-list-affected-releases.sh
# Exit codes:
#   0  every case passed (prints PASSED)
#   1  at least one case failed (prints FAILED)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/list-affected-releases.sh"
ADVISORY=docs/security/2026-11-24-skill-setup-installer.md
ALLOWLIST='^https://cli(\.staging)?\.gokite\.ai$'

COPIES=(
  attach-session/scripts/setup.sh
  authenticate-user/scripts/setup.sh
  request-session/scripts/setup.sh
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CEILING_DIRECTORIES="$WORK"
mkdir -p "$HOME"

REPO="$WORK/repo"
OUT="$WORK/stdout"
ERR="$WORK/stderr"
RC=0
CASES=0
FAILURES=0

ok() {
  CASES=$((CASES + 1))
  echo "  [OK] $1"
}

bad() {
  CASES=$((CASES + 1))
  FAILURES=$((FAILURES + 1))
  {
    echo "  [FAIL] $1"
    echo "         expected: ${2//$'\n'/ }"
    echo "         got:      ${3//$'\n'/ }"
  } >&2
}

expect() {
  if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1" "$2" "$3"; fi
}

# It runs from a directory outside every repository on purpose.
run_in() {
  local repo="$1"
  shift
  RC=0
  (cd "$WORK" && bash "$SCRIPT" -C "$repo" "$@") >"$OUT" 2>"$ERR" || RC=$?
}

run() { run_in "$REPO" "$@"; }

# Same as run_in, with a directory prepended to the script's PATH only.
run_in_with_path() {
  local repo="$1" dir="$2"
  shift 2
  RC=0
  (cd "$WORK" && PATH="$dir:$PATH" bash "$SCRIPT" -C "$repo" "$@") >"$OUT" 2>"$ERR" || RC=$?
}

summary() { echo "exit $RC, stdout: $(cat "$OUT")"; }

expect_ref() {
  run --ref "$2"
  expect "$1" "exit 0, stdout: $3" "$(summary)"
}

# A second argument pins the reason. Two guards that both exit 1 with a message
# are otherwise interchangeable, so a case can pass on the wrong one.
expect_loud_failure() {
  local want="${2-}"
  if [[ "$RC" -eq 1 && ! -s "$OUT" && -s "$ERR" ]] &&
    { [[ -z "$want" ]] || grep -qF -e "$want" "$ERR"; }; then
    ok "$1"
  else
    bad "$1" "exit 1, empty stdout, stderr naming '${want:-any reason}'" \
      "exit $RC, stdout: $(cat "$OUT"), stderr: $(cat "$ERR")"
  fi
}

hardened_copy() {
  cat <<'COPY'
#!/usr/bin/env bash
set -euo pipefail
SKILLS_JSON="$SCRIPT_DIR/../skills.json"
get_installer_base() {
  local base="${KPASS_BASE_URL:-https://cli.gokite.ai}"
  [[ $base =~ ^https://cli(\.staging)?\.gokite\.ai$ ]] || { echo "bad installer base: $base" >&2; exit 1; }
  printf '%s' "$base"
}
INSTALLER_BASE="$(get_installer_base)"
echo "  2. Try: curl -fsSL ${INSTALLER_BASE}/install.sh | bash"
node -e 'console.log(require(process.argv[1])[process.argv[2]])' "$SKILLS_JSON" "$field"
python3 -c "import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$SKILLS_JSON" "$field"
curl -fsSL --proto '=https' "${INSTALLER_BASE}/install.sh" -o "$INSTALL_SCRIPT"
bash "$INSTALL_SCRIPT" >&2
cat <<EOF
{"status":"error","error":"Install manually:\n\n  macOS / Linux:  curl -fsSL ${INSTALLER_BASE}/install.sh | bash\n"}
EOF
COPY
}

render_copy() {
  case "$1" in
    hardened) hardened_copy ;;
    unconstrained-base) hardened_copy | grep -vF -e "$ALLOWLIST" ;;
    curl-pipe-if)
      hardened_copy
      cat <<'LINE'
if curl -fsSL "${INSTALLER_BASE}/install.sh" | bash >&2; then
  :
fi
LINE
      ;;
    curl-pipe-bare)
      hardened_copy
      cat <<'LINE'
curl -fsSL "${INSTALLER_BASE}/install.sh" | bash
LINE
      ;;
    curl-pipe-sh)
      hardened_copy
      cat <<'LINE'
curl -fsSL "${INSTALLER_BASE}/install.sh" | sh
LINE
      ;;
    curl-pipe-abspath)
      hardened_copy
      cat <<'LINE'
curl -fsSL "${INSTALLER_BASE}/install.sh" | /bin/bash -s --
LINE
      ;;
    curl-pipe-stderr-too)
      hardened_copy
      cat <<'LINE'
curl -fsSL "${INSTALLER_BASE}/install.sh" |& bash
LINE
      ;;
    curl-pipe-in-substitution)
      hardened_copy
      cat <<'LINE'
out=$(curl -fsSL "${INSTALLER_BASE}/install.sh" | bash)
LINE
      ;;
    curl-pipe-continued)
      hardened_copy
      cat <<'LINE'
curl -fsSL \
  "${INSTALLER_BASE}/install.sh" \
  | bash
LINE
      ;;
    code-paste-node)
      hardened_copy
      echo "node -p \"require('\$SKILLS_JSON').min_kpass_version\""
      ;;
    code-paste-python)
      hardened_copy
      echo "python3 -c \"import json; print(json.load(open('\$SKILLS_JSON'))['min_kpass_version'])\""
      ;;
    curl-pipe-sudo)
      hardened_copy
      cat <<'LINE'
curl -fsSL "${INSTALLER_BASE}/install.sh" | sudo -E bash -
LINE
      ;;
    curl-pipe-env)
      hardened_copy
      cat <<'LINE'
curl -fsSL "${INSTALLER_BASE}/install.sh" | /usr/bin/env bash
LINE
      ;;
    curl-pipe-after-semicolon)
      hardened_copy
      cat <<'LINE'
cd "$HOME"; curl -fsSL "${INSTALLER_BASE}/install.sh" | bash
LINE
      ;;
    code-paste-node-e)
      hardened_copy
      echo "node -e \"require('\$SKILLS_JSON').min_kpass_version\""
      ;;
    code-paste-braced)
      hardened_copy
      echo "node -p \"require('\${SKILLS_JSON}').min_kpass_version\""
      ;;
    code-paste-escaped-quote)
      hardened_copy
      echo "node -p \"require(\\\"\$SKILLS_JSON\\\").min_kpass_version\""
      ;;
    code-paste-spliced-quote)
      hardened_copy
      echo "node -p 'require(\"'\"\$SKILLS_JSON\"'\").min_kpass_version'"
      ;;
    code-paste-python2)
      hardened_copy
      echo "python -c \"import json; print(json.load(open('\$SKILLS_JSON')))\""
      ;;
    curl-pipe-trailing-pipe)
      hardened_copy
      cat <<'LINE'
curl -fsSL "${INSTALLER_BASE}/install.sh" |
  bash
LINE
      ;;
    curl-pipe-sudo-before-curl)
      hardened_copy
      cat <<'LINE'
sudo curl -fsSL "${INSTALLER_BASE}/install.sh" | bash
LINE
      ;;
    code-paste-unquoted-splice)
      hardened_copy
      cat <<'LINE'
node -p 'require("'$SKILLS_JSON'").min_kpass_version'
LINE
      ;;
    code-paste-unquoted-splice-python)
      hardened_copy
      cat <<'LINE'
python3 -c 'import json; print(json.load(open("'$SKILLS_JSON'")))'
LINE
      ;;
    echoed-trailing-pipe)
      hardened_copy
      cat <<'LINE'
echo "  2. Try: curl -fsSL ${INSTALLER_BASE}/install.sh |"
echo "          bash"
LINE
      ;;
    curl-pipe-amp-continuation)
      hardened_copy
      cat <<'LINE'
curl -fsSL "${INSTALLER_BASE}/install.sh" |&
  bash
LINE
      ;;
    curl-pipe-comment-between)
      hardened_copy
      cat <<'LINE'
curl -fsSL "${INSTALLER_BASE}/install.sh" |
  # fetch and run the installer
  bash
LINE
      ;;
    curl-pipe-after-comment-backslash)
      hardened_copy
      cat <<'LINE'
# the installer moved \
curl -fsSL "${INSTALLER_BASE}/install.sh" | bash
LINE
      ;;
    curl-pipe-in-backticks)
      hardened_copy
      cat <<'LINE'
out=`curl -fsSL "${INSTALLER_BASE}/install.sh" | bash`
LINE
      ;;
    curl-pipe-then-redirect)
      hardened_copy
      cat <<'LINE'
curl -fsSL "${INSTALLER_BASE}/install.sh" | bash>/dev/null
LINE
      ;;
    curl-reached-by-path)
      hardened_copy
      cat <<'LINE'
/usr/bin/curl -fsSL "${INSTALLER_BASE}/install.sh" | bash
LINE
      ;;
    code-paste-eval-equals)
      hardened_copy
      echo "node --eval=\"require('\$SKILLS_JSON').min_kpass_version\""
      ;;
    code-paste-flag-before-option)
      hardened_copy
      echo "node --no-warnings -e \"require('\$SKILLS_JSON').min_kpass_version\""
      ;;
    code-paste-python-flag-before-c)
      hardened_copy
      echo "python3 -I -c \"import json; print(json.load(open('\$SKILLS_JSON')))\""
      ;;
    code-paste-attached-c)
      hardened_copy
      echo "python3 -c\"import json; print(json.load(open('\$SKILLS_JSON')))\""
      ;;
    code-paste-nodejs)
      hardened_copy
      echo "nodejs -p \"require('\$SKILLS_JSON').min_kpass_version\""
      ;;
    hardened-argv-behind-a-flag)
      hardened_copy
      cat <<'LINE'
node --no-warnings -e 'console.log(require(process.argv[1]).v)' "$SKILLS_JSON"
LINE
      ;;
    hardened-many-allowlist-lines)
      hardened_copy
      # Enough live allowlist lines that a reader which stops at the first
      # match can finish before the writer does.
      for _ in $(seq 5000); do
        echo "  [[ \$base =~ $ALLOWLIST ]] || exit 1"
      done
      ;;
    allowlist-only-in-a-comment)
      hardened_copy | sed 's|^  \[\[ |  # TODO validate the base against |'
      ;;
    no-base-url-no-allowlist)
      hardened_copy | grep -vF -e 'KPASS_BASE_URL' -e "$ALLOWLIST"
      ;;
    *) echo "test bug: unknown variant '$1'" >&2; return 1 ;;
  esac
}

new_repo() {
  git -c init.defaultBranch=main init -q "$1"
  git -C "$1" config user.name fixture
  git -C "$1" config user.email fixture@example.invalid
  git -C "$1" config commit.gpgsign false
  git -C "$1" config tag.gpgsign false
}

commit_copies() {
  local repo="$1" message="$2" variant path i=0
  shift 2
  for variant in "$@"; do
    path="${COPIES[$i]}"
    i=$((i + 1))
    case "$variant" in
      absent) rm -f "${repo:?}/${path:?}" ;;
      real)
        mkdir -p "$repo/$(dirname "$path")"
        cp "$ROOT_DIR/$path" "$repo/$path"
        ;;
      *)
        mkdir -p "$repo/$(dirname "$path")"
        render_copy "$variant" >"$repo/$path"
        ;;
    esac
  done
  git -C "$repo" add -A
  git -C "$repo" commit -q --allow-empty -m "$message"
}

release() {
  commit_copies "$REPO" "$@"
  git -C "$REPO" tag "$1"
}

new_repo "$REPO"
release v0.9.0 absent absent absent
release v1.0.0 unconstrained-base unconstrained-base unconstrained-base
release v1.2.0 curl-pipe-if curl-pipe-if curl-pipe-if
release v1.3.0 curl-pipe-bare curl-pipe-bare curl-pipe-bare
release v1.4.0 curl-pipe-sh curl-pipe-sh curl-pipe-sh
release v1.5.0 curl-pipe-abspath curl-pipe-abspath curl-pipe-abspath
release v1.6.0 curl-pipe-stderr-too curl-pipe-stderr-too curl-pipe-stderr-too
release v1.7.0 curl-pipe-in-substitution curl-pipe-in-substitution curl-pipe-in-substitution
release v1.8.0 curl-pipe-continued curl-pipe-continued curl-pipe-continued
release v1.9.0 curl-pipe-sudo curl-pipe-sudo curl-pipe-sudo
release v1.9.1 curl-pipe-env curl-pipe-env curl-pipe-env
release v1.9.2 curl-pipe-after-semicolon curl-pipe-after-semicolon curl-pipe-after-semicolon
release v1.10.0 code-paste-node code-paste-node code-paste-node
release v1.11.0 code-paste-python code-paste-python code-paste-python
release v1.12.0 code-paste-node-e code-paste-node-e code-paste-node-e
release v1.13.0 code-paste-braced code-paste-braced code-paste-braced
release v1.14.0 code-paste-escaped-quote code-paste-escaped-quote code-paste-escaped-quote
release v1.15.0 code-paste-spliced-quote code-paste-spliced-quote code-paste-spliced-quote
release v1.16.0 code-paste-python2 code-paste-python2 code-paste-python2
release v1.17.0 allowlist-only-in-a-comment allowlist-only-in-a-comment allowlist-only-in-a-comment
release v1.18.0 no-base-url-no-allowlist no-base-url-no-allowlist no-base-url-no-allowlist
release v1.8.1 curl-pipe-trailing-pipe curl-pipe-trailing-pipe curl-pipe-trailing-pipe
release v1.9.3 curl-pipe-sudo-before-curl curl-pipe-sudo-before-curl curl-pipe-sudo-before-curl
release v1.15.1 code-paste-unquoted-splice code-paste-unquoted-splice code-paste-unquoted-splice
release v1.16.1 code-paste-unquoted-splice-python code-paste-unquoted-splice-python code-paste-unquoted-splice-python
release v1.18.1 echoed-trailing-pipe echoed-trailing-pipe echoed-trailing-pipe
release v1.8.2 curl-pipe-amp-continuation curl-pipe-amp-continuation curl-pipe-amp-continuation
release v1.8.3 curl-pipe-comment-between curl-pipe-comment-between curl-pipe-comment-between
release v1.8.4 curl-pipe-after-comment-backslash curl-pipe-after-comment-backslash curl-pipe-after-comment-backslash
release v1.8.5 curl-pipe-in-backticks curl-pipe-in-backticks curl-pipe-in-backticks
release v1.8.6 curl-pipe-then-redirect curl-pipe-then-redirect curl-pipe-then-redirect
release v1.8.7 curl-reached-by-path curl-reached-by-path curl-reached-by-path
release v1.16.2 code-paste-eval-equals code-paste-eval-equals code-paste-eval-equals
release v1.16.3 code-paste-flag-before-option code-paste-flag-before-option code-paste-flag-before-option
release v1.16.4 code-paste-python-flag-before-c code-paste-python-flag-before-c code-paste-python-flag-before-c
release v1.16.5 code-paste-attached-c code-paste-attached-c code-paste-attached-c
release v1.16.6 code-paste-nodejs code-paste-nodejs code-paste-nodejs
release v1.18.2 hardened-many-allowlist-lines hardened-many-allowlist-lines hardened-many-allowlist-lines
release v1.18.3 hardened-argv-behind-a-flag hardened-argv-behind-a-flag hardened-argv-behind-a-flag
release v2.0.0 hardened hardened hardened
release v2.1.0 code-paste-node hardened hardened
release v2.2.0 hardened curl-pipe-if hardened
release v2.3.0 hardened hardened unconstrained-base
release v3.0.0 absent absent hardened
release v3.1.0 absent absent code-paste-python
commit_copies "$REPO" nightly curl-pipe-if curl-pipe-if curl-pipe-if
git -C "$REPO" tag nightly-2026

# Listed in version order, which differs from the order of the tag names as text.
EXPECTED=(
  v1.0.0 v1.2.0 v1.3.0 v1.4.0 v1.5.0 v1.6.0 v1.7.0 v1.8.0 v1.8.1 v1.8.2
  v1.8.3 v1.8.4 v1.8.5 v1.8.6 v1.8.7 v1.9.0 v1.9.1 v1.9.2 v1.9.3 v1.10.0
  v1.11.0 v1.12.0 v1.13.0 v1.14.0 v1.15.0 v1.15.1 v1.16.0 v1.16.1 v1.16.2
  v1.16.3 v1.16.4 v1.16.5 v1.16.6 v1.17.0 v2.1.0 v2.2.0 v2.3.0 v3.1.0
)

expect_ref "rule 1 alone: reads KPASS_BASE_URL with no allowlist is affected" v1.0.0 affected
expect_ref "rule 2 alone: 'if curl ... | bash' is affected" v1.2.0 affected
expect_ref "rule 2 alone: a bare 'curl ... | bash' line is affected" v1.3.0 affected
expect_ref "rule 2: a pipe into sh rather than bash is affected" v1.4.0 affected
expect_ref "rule 2: a pipe into an absolute shell path is affected" v1.5.0 affected
expect_ref "rule 2: a stderr-and-stdout pipe into bash is affected" v1.6.0 affected
expect_ref "rule 2: a pipe into bash inside a command substitution is affected" v1.7.0 affected
expect_ref "rule 2: a pipeline split over backslash continuations is affected" v1.8.0 affected
expect_ref "rule 3 alone: node -p with \$SKILLS_JSON inside the code is affected" v1.10.0 affected
expect_ref "rule 3 alone: python3 -c with \$SKILLS_JSON inside the code is affected" v1.11.0 affected
expect_ref "rule 2: a pipe into sudo bash is affected" v1.9.0 affected
expect_ref "rule 2: a pipe into env bash by absolute path is affected" v1.9.1 affected
expect_ref "rule 2: curl at command position after a semicolon is affected" v1.9.2 affected
expect_ref "rule 3: node -e with \$SKILLS_JSON inside the code is affected" v1.12.0 affected
expect_ref "rule 3: a braced \${SKILLS_JSON} inside the code is affected" v1.13.0 affected
expect_ref "rule 3: \$SKILLS_JSON behind escaped quotes is affected" v1.14.0 affected
expect_ref "rule 3: \$SKILLS_JSON spliced between quoted runs is affected" v1.15.0 affected
expect_ref "rule 3: python -c without a version suffix is affected" v1.16.0 affected
expect_ref "rule 2: a pipeline continued by a trailing pipe is affected" v1.8.1 affected
expect_ref "rule 2: a sudo prefix before curl is affected" v1.9.3 affected
expect_ref "rule 3: an unquoted '...'\$SKILLS_JSON'...' splice is affected" v1.15.1 affected
expect_ref "rule 3: the same unquoted splice under python3 -c is affected" v1.16.1 affected
expect_ref "rule 2: an echoed pipeline split over two echo lines is fixed" v1.18.1 fixed
expect_ref "rule 1: an allowlist that survives only in a comment is affected" v1.17.0 affected
expect_ref "rule 1: no allowlist and no KPASS_BASE_URL read is fixed" v1.18.0 fixed
expect_ref "hardened copy with printed curl | bash decoys and argv forms is fixed" v2.0.0 fixed
expect_ref "no copy path exists is not-shipped" v0.9.0 not-shipped
expect_ref "only the first copy vulnerable is affected" v2.1.0 affected
expect_ref "only the middle copy vulnerable is affected" v2.2.0 affected
expect_ref "only the last copy vulnerable is affected" v2.3.0 affected
expect_ref "one hardened copy and two absent paths is fixed" v3.0.0 fixed
expect_ref "one vulnerable copy and two absent paths is affected" v3.1.0 affected
expect_ref "a non-v tag resolves by --ref" nightly-2026 affected
expect_ref "a branch head resolves by --ref" HEAD affected
expect_ref "a commit id resolves by --ref" "$(git -C "$REPO" rev-parse v2.0.0)" fixed

expect_ref "rule 2: a |& continuation is affected" v1.8.2 affected
expect_ref "rule 2: a comment between the pipe and the shell is affected" v1.8.3 affected
expect_ref "rule 2: a comment ending in a backslash hides nothing" v1.8.4 affected
expect_ref "rule 2: a pipeline inside backticks is affected" v1.8.5 affected
expect_ref "rule 2: a redirect straight after the shell is affected" v1.8.6 affected
expect_ref "rule 2: curl reached by a path is affected" v1.8.7 affected
expect_ref "rule 3: node --eval=code is affected" v1.16.2 affected
expect_ref "rule 3: a flag before -e is affected" v1.16.3 affected
expect_ref "rule 3: a flag before python3 -c is affected" v1.16.4 affected
expect_ref "rule 3: an attached python3 -c is affected" v1.16.5 affected
expect_ref "rule 3: the nodejs binary name is affected" v1.16.6 affected
expect_ref "rule 3: the argv form behind a flag is fixed" v1.18.3 fixed
expect_ref "rule 1: a copy with many live allowlist lines is fixed" v1.18.2 fixed

# Reading a copy is a step that can fail on its own. If its status is dropped,
# the listing prints a short list and exits 0, which reads exactly like a repo
# with few affected releases.
STUB_BIN="$WORK/stub-bin"
mkdir -p "$STUB_BIN"
printf '#!/bin/sh\nexit 3\n' >"$STUB_BIN/awk"
chmod +x "$STUB_BIN/awk"
run_in_with_path "$REPO" "$STUB_BIN"
expect_loud_failure "a copy that cannot be normalised fails instead of listing nothing"
run_in_with_path "$REPO" "$STUB_BIN" --ref v1.3.0
expect_loud_failure "--ref fails when a copy cannot be normalised"

# grep answers 1 for no match and 2 for an error. A rule that reads the error as
# "no match" calls a vulnerable copy fixed, which is the direction that matters.
GREP_STUB_BIN="$WORK/grep-stub-bin"
mkdir -p "$GREP_STUB_BIN"
printf '#!/bin/sh\nexit 2\n' >"$GREP_STUB_BIN/grep"
chmod +x "$GREP_STUB_BIN/grep"
run_in_with_path "$REPO" "$GREP_STUB_BIN" --ref v1.3.0
expect_loud_failure "a rule whose grep errors fails instead of reporting fixed" "grep exited"

# Only the allowlist awk fails here. The joiner's awk has to keep working, or
# the run would stop before any rule is reached.
AWK_RULE_STUB_BIN="$WORK/awk-rule-stub-bin"
mkdir -p "$AWK_RULE_STUB_BIN"
cat >"$AWK_RULE_STUB_BIN/awk" <<'STUB'
#!/bin/sh
for arg in "$@"; do
  case "$arg" in
    *ALLOWLIST_PATTERN*) exit 2 ;;
  esac
done
exec /usr/bin/awk "$@"
STUB
chmod +x "$AWK_RULE_STUB_BIN/awk"
run_in_with_path "$REPO" "$AWK_RULE_STUB_BIN" --ref v1.0.0
expect_loud_failure "an allowlist test that errors fails instead of guessing" "awk exited"

run
expect "listing prints exactly the affected v* tags in version order" \
  "exit 0, stdout: $(printf '%s\n' "${EXPECTED[@]}")" "$(summary)"

DEFAULT_REPO="$WORK/default-repo"
new_repo "$DEFAULT_REPO"
mkdir -p "$DEFAULT_REPO/scripts"
cp "$SCRIPT" "$DEFAULT_REPO/scripts/"
commit_copies "$DEFAULT_REPO" v1.0.0 curl-pipe-if curl-pipe-if curl-pipe-if
git -C "$DEFAULT_REPO" tag v1.0.0
RC=0
(cd / && bash "$DEFAULT_REPO/scripts/list-affected-releases.sh") >"$OUT" 2>"$ERR" || RC=$?
expect "without -C it reads the repository that holds the script, from any directory" \
  "exit 0, stdout: v1.0.0" "$(summary)"

REAL_REPO="$WORK/real-copies"
new_repo "$REAL_REPO"
commit_copies "$REAL_REPO" v9.9.9 real real real
git -C "$REAL_REPO" tag v9.9.9
run_in "$REAL_REPO" --ref v9.9.9
expect "the three setup copies in this checkout are fixed" "exit 0, stdout: fixed" "$(summary)"

# Cloned at a v* tag on purpose. A shallow clone of the branch tip carries no
# v* tag at all, so the no-tags guard would answer for the shallow guard and
# the case would pass with the shallow guard deleted.
SHALLOW_REPO="$WORK/shallow"
git clone -q --depth 1 --no-local --branch v2.3.0 "file://$REPO" "$SHALLOW_REPO"
if [[ -z "$(git -C "$SHALLOW_REPO" tag -l 'v*')" ]]; then
  bad "the shallow fixture has a v* tag to be tempted by" "at least one v* tag" "none"
fi
run_in "$SHALLOW_REPO"
expect_loud_failure "a shallow clone fails rather than listing the few tags it has" "shallow clone"

NO_TAGS_REPO="$WORK/no-tags"
new_repo "$NO_TAGS_REPO"
commit_copies "$NO_TAGS_REPO" untagged curl-pipe-if curl-pipe-if curl-pipe-if
git -C "$NO_TAGS_REPO" tag nightly-2026
run_in "$NO_TAGS_REPO"
expect_loud_failure "listing a repository with no v* tags fails" "no v* tags"
run_in "$NO_TAGS_REPO" --ref HEAD
expect_loud_failure "--ref in a repository with no v* tags fails" "no v* tags"
run_in "$NO_TAGS_REPO" --check
expect_loud_failure "--check in a repository with no v* tags fails" "no v* tags"

# git show reports an unreadable blob the same way it reports an absent path.
# Answering not-shipped for a release that did ship a vulnerable copy is the
# dangerous direction, so the read must fail loudly instead.
# A directory copy keeps the loose objects, so only the three blobs go missing
# and every commit and tag still resolves.
UNREADABLE_REPO="$WORK/unreadable"
cp -r "$REPO" "$UNREADABLE_REPO"
for copy in "${COPIES[@]}"; do
  blob="$(git -C "$UNREADABLE_REPO" rev-parse "v1.3.0:$copy")"
  rm -f "$UNREADABLE_REPO/.git/objects/${blob:0:2}/${blob:2}"
done
if git -C "$UNREADABLE_REPO" rev-parse --verify --quiet v1.3.0 >/dev/null; then
  :
else
  bad "the unreadable fixture still resolves its tags" "v1.3.0 resolves" "it does not"
fi
run_in "$UNREADABLE_REPO" --ref v1.3.0
expect_loud_failure "a copy that cannot be read fails instead of reporting not-shipped" "cannot read"
# The listing streams tags as it goes, so the earlier ones are already out.
# What matters is that it stops, says why, and exits non-zero, so a caller
# cannot read the partial list as the whole one.
run_in "$UNREADABLE_REPO"
if [[ "$RC" -eq 1 ]] && grep -qF -e "cannot read" "$ERR" &&
  [[ "$(cat "$OUT")" != *v1.3.0* ]]; then
  ok "listing stops at the unreadable tag and exits non-zero"
else
  bad "listing stops at the unreadable tag and exits non-zero" \
    "exit 1, stdout without v1.3.0, stderr naming 'cannot read'" "$(summary)"
fi

# A rule reads text. A path that holds a tree or a symlink has none to read, so
# the verdict would otherwise come from a rule that saw a directory listing or a
# link target rather than the script.
NOT_A_FILE_REPO="$WORK/not-a-file"
new_repo "$NOT_A_FILE_REPO"
mkdir -p "$NOT_A_FILE_REPO/${COPIES[0]}/nested"
echo placeholder >"$NOT_A_FILE_REPO/${COPIES[0]}/nested/setup.sh"
git -C "$NOT_A_FILE_REPO" add -A
git -C "$NOT_A_FILE_REPO" commit -q -m v4.0.0
git -C "$NOT_A_FILE_REPO" tag v4.0.0
run_in "$NOT_A_FILE_REPO" --ref v4.0.0
expect_loud_failure "a copy path holding a directory fails instead of a verdict" "not a file"

SYMLINK_REPO="$WORK/symlinked-copy"
new_repo "$SYMLINK_REPO"
mkdir -p "$SYMLINK_REPO/$(dirname "${COPIES[0]}")" "$SYMLINK_REPO/scripts"
render_copy curl-pipe-bare >"$SYMLINK_REPO/scripts/setup.sh"
ln -s ../../scripts/setup.sh "$SYMLINK_REPO/${COPIES[0]}"
git -C "$SYMLINK_REPO" add -A
git -C "$SYMLINK_REPO" commit -q -m v5.0.0
git -C "$SYMLINK_REPO" tag v5.0.0
run_in "$SYMLINK_REPO" --ref v5.0.0
expect_loud_failure "a copy stored as a symlink fails instead of a verdict" "symlink"

run --ref no-such-ref
expect_loud_failure "an unresolvable --ref fails instead of printing not-shipped"
run --ref ''
expect_loud_failure "an empty --ref fails"
run --ref
expect_loud_failure "--ref without a value fails"
run --bogus
expect_loud_failure "an unknown argument fails"
run --ref v1.0.0 --check
expect_loud_failure "--ref with --check fails"

mkdir "$WORK/plain"
run_in "$WORK/plain"
expect_loud_failure "-C on a directory outside any git repository fails"

run --help
if [[ "$RC" -eq 0 && "$(cat "$OUT")" == *"Usage:"* ]]; then
  ok "--help prints usage and exits 0"
else
  bad "--help prints usage and exits 0" "exit 0, stdout containing Usage:" "$(summary)"
fi

write_advisory() {
  mkdir -p "$REPO/$(dirname "$ADVISORY")"
  {
    echo "# Fixture advisory"
    echo
    echo "Prose before the block names v9.9.9, which is not a list entry."
    echo "<!-- affected-releases:start -->"
    echo
    printf '%s\n' "$@"
    echo
    echo "<!-- affected-releases:end -->"
    echo "Prose after the block."
  } >"$REPO/$ADVISORY"
}

bullets=()
i=0
for tag in "${EXPECTED[@]}"; do
  if ((i % 2 == 0)); then bullets+=("- \`$tag\`"); else bullets+=("* $tag"); fi
  i=$((i + 1))
done

write_advisory "${bullets[@]}"
run --check
expect "--check passes when the marker block matches, ignoring bullets, backticks and blank lines" \
  "exit 0" "exit $RC"

omitted="${EXPECTED[3]}"
write_advisory "${bullets[@]:0:3}" "${bullets[@]:4}"
run --check
if [[ "$RC" -eq 1 && "$(cat "$OUT")" == *"$omitted"* ]]; then
  ok "--check fails and prints the difference when the advisory omits a tag"
else
  bad "--check fails and prints the difference when the advisory omits a tag" "exit 1, stdout naming $omitted" "$(summary)"
fi

write_advisory "${bullets[@]}" "- v2.0.0"
run --check
if [[ "$RC" -eq 1 && "$(cat "$OUT")" == *v2.0.0* ]]; then
  ok "--check fails and prints the difference when the advisory lists a fixed tag"
else
  bad "--check fails and prints the difference when the advisory lists a fixed tag" "exit 1, stdout naming v2.0.0" "$(summary)"
fi

printf '# Fixture advisory without markers\n\n- v1.0.0\n' >"$REPO/$ADVISORY"
run --check
expect_loud_failure "--check fails when the advisory has no marker block"

rm -f "${REPO:?}/${ADVISORY:?}"
run --check
expect_loud_failure "--check fails when the advisory file is missing"

if [[ "$FAILURES" -ne 0 ]]; then
  echo "FAILED: $FAILURES of $CASES cases failed" >&2
  exit 1
fi
echo "PASSED: $CASES cases"
