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

summary() { echo "exit $RC, stdout: $(cat "$OUT")"; }

expect_ref() {
  run --ref "$2"
  expect "$1" "exit 0, stdout: $3" "$(summary)"
}

expect_loud_failure() {
  if [[ "$RC" -eq 1 && ! -s "$OUT" && -s "$ERR" ]]; then
    ok "$1"
  else
    bad "$1" "exit 1, empty stdout, a message on stderr" "exit $RC, stdout: $(cat "$OUT"), stderr: $(cat "$ERR")"
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
  v1.0.0 v1.2.0 v1.3.0 v1.4.0 v1.5.0 v1.6.0 v1.7.0 v1.8.0 v1.9.0 v1.9.1
  v1.9.2 v1.10.0 v1.11.0 v1.12.0 v1.13.0 v1.14.0 v1.15.0 v1.16.0 v1.17.0
  v2.1.0 v2.2.0 v2.3.0 v3.1.0
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

SHALLOW_REPO="$WORK/shallow"
git clone -q --depth 1 --no-local "file://$REPO" "$SHALLOW_REPO"
run_in "$SHALLOW_REPO"
expect_loud_failure "a shallow clone fails rather than listing the few tags it has"

NO_TAGS_REPO="$WORK/no-tags"
new_repo "$NO_TAGS_REPO"
commit_copies "$NO_TAGS_REPO" untagged curl-pipe-if curl-pipe-if curl-pipe-if
git -C "$NO_TAGS_REPO" tag nightly-2026
run_in "$NO_TAGS_REPO"
expect_loud_failure "listing a repository with no v* tags fails"
run_in "$NO_TAGS_REPO" --ref HEAD
expect_loud_failure "--ref in a repository with no v* tags fails"
run_in "$NO_TAGS_REPO" --check
expect_loud_failure "--check in a repository with no v* tags fails"

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
