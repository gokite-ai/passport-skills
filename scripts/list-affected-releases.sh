#!/usr/bin/env bash
# Lists the tagged releases that shipped a vulnerable skill setup copy.
#
# Three skill-bundled copies of setup.sh ran an installer from any
# KPASS_BASE_URL. This script asks each tag what the copies looked like then,
# so the list of affected releases comes from the tags and never from memory.
# The advisory is docs/security/2026-11-24-skill-setup-installer.md.
#
# A ref is classified from the three copy paths at that ref:
#   affected     any copy that exists is vulnerable (matches a rule in VULN_RULES)
#   not-shipped  none of the three paths exists
#   fixed        otherwise
#
# Usage: bash scripts/list-affected-releases.sh [-C <dir>] [--ref <ref> | --check]
#   (no mode)    print each affected v* tag, one per line, in version order
#   --ref <ref>  print affected, fixed or not-shipped for one ref
#   --check      compare the listing with the advisory's marker block
#   -C <dir>     git repository to read (default: the repository holding this script)
#   -h, --help   print this usage
#
# Exit codes:
#   0  success (--check: the advisory matches the tags)
#   1  bad usage, a shallow clone, no v* tags, an unresolvable ref, a copy that
#      cannot be read, or --check found a difference
set -euo pipefail

COPY_PATHS=(
  attach-session/scripts/setup.sh
  authenticate-user/scripts/setup.sh
  request-session/scripts/setup.sh
)
readonly ADVISORY_PATH=docs/security/2026-11-24-skill-setup-installer.md
readonly START_MARKER='<!-- affected-releases:start -->'
readonly END_MARKER='<!-- affected-releases:end -->'

readonly RULE_READS_BASE_URL='[$]\{?KPASS_BASE_URL'
readonly RULE_ALLOWLIST='^https://cli(\.staging)?\.gokite\.ai$'

# curl's output piped into a shell. Anchored at command position, because the
# hardened copy prints this same text in its --help echo and in its JSON error
# envelope and neither must count. Any shell counts and so do the usual wrappers,
# so "| sh", "| /bin/bash", "| sudo bash" and "| VAR=x bash" all land.
# Not covered: curl inside a shell's own code argument, as in eval "$(curl ...)"
# or bash <(curl ...). No release used either shape, and folding them into this
# rule would widen the published classification, which is Engineering's call.
readonly WRAPPER='(([^[:space:]]*/)?(sudo|env|exec|command|nohup|time|timeout)|-[^[:space:]]+|[0-9]+[smhd]?|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)'
readonly RULE_CURL_PIPE_SHELL='(^|[;&|({)`]|[$][(])[[:space:]]*(([!({]|if|then|else|elif|while|until|do)[[:space:]]+|'"$WRAPPER"'[[:space:]]+)*curl[[:space:]].*\|&?[[:space:]]*('"$WRAPPER"'[[:space:]]+)*([^[:space:]]*/)?(ba|da|k|z)?sh([[:space:]]|;|&|[)]|$)'

# $SKILLS_JSON spliced into the interpreter's code rather than passed as its own
# argument. The leading group consumes whole quoted words, so it reaches across
# the "'...'" "$X" "'...'" splicing trick, and the trailing group stops at the
# closing quote, so the hardened form that passes the path as a separate argv
# entry does not match.
readonly RULE_CODE_PASTE="(node[[:space:]]+(--?(eval|print)|-(pe?|ep?))|python[0-9.]*[[:space:]]+-c)[[:space:]]+(('([^'\\]|\\\\.)*'|\"([^\"\\]|\\\\.)*\"|[^[:space:]'\"])*)('([^'\\]|\\\\.)*|\"([^\"\\]|\\\\.)*)?[\$]\{?SKILLS_JSON"

rule_unconstrained_base_url() {
  grep -Eq -e "$RULE_READS_BASE_URL" -- "$1" || return 1
  # A commented-out allowlist is not an allowlist. One awk rather than a
  # grep pipeline, so a short-circuiting reader cannot SIGPIPE the writer
  # and turn a live allowlist into a vulnerable verdict.
  ! awk -v pat="$RULE_ALLOWLIST" '
    index($0, pat) && $0 !~ /^[ \t]*#/ { found = 1; exit }
    END { exit !found }
  ' "$1"
}
rule_curl_pipe_shell() {
  grep -Eq -e "$RULE_CURL_PIPE_SHELL" -- "$1"
}
rule_code_paste() {
  grep -Eq -e "$RULE_CODE_PASTE" -- "$1"
}

VULN_RULES=(
  rule_unconstrained_base_url
  rule_curl_pipe_shell
  rule_code_paste
)

usage() {
  sed -n '/^# Usage:/,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
}

die() {
  echo "list-affected-releases: $*" >&2
  exit 1
}

copy_is_vulnerable() {
  local file="$1" rule
  for rule in "${VULN_RULES[@]}"; do
    if "$rule" "$file"; then
      return 0
    fi
  done
  return 1
}

# Every step inside classify_ref checks its own status. list_affected calls it
# on the left of a ||, which suspends set -e for the whole subshell.
classify_ref() {
  local ref="$1" path entry mode type verdict=not-shipped
  for path in "${COPY_PATHS[@]}"; do
    # ls-tree separates "no such path" from "the read failed", which git show
    # reports the same way. A partial clone missing its blobs would otherwise
    # answer not-shipped for a release that did ship a vulnerable copy.
    entry="$(git -C "$REPO" ls-tree --full-tree "$ref" -- "$path")" ||
      die "cannot read $path at $ref"
    [[ -n "$entry" ]] || continue
    read -r mode type _ <<<"$entry"
    [[ "$type" == blob ]] ||
      die "$path at $ref is a $type, not a file, so no rule can judge it"
    [[ "$mode" != 120000 ]] ||
      die "$path at $ref is a symlink, so its text is not the script"
    git -C "$REPO" show "$ref:$path" >"$SCRATCH/raw" ||
      die "cannot read $path at $ref"
    # A pipeline split across a line continuation is one command, so the rules
    # must see it as one line. A trailing "|" continues a line the same way a
    # trailing backslash does.
    awk '
      {
        while (sub(/\\$/, "") || /(^|[^|])\|[[:space:]]*$/) {
          if ((getline nxt) > 0) $0 = $0 nxt; else break
        }
        print
      }
    ' "$SCRATCH/raw" >"$SCRATCH/copy" ||
      die "cannot normalize $path at $ref"
    verdict=fixed
    if copy_is_vulnerable "$SCRATCH/copy"; then
      verdict=affected
      break
    fi
  done
  echo "$verdict"
}

list_affected() {
  local tag verdict
  while IFS= read -r tag; do
    # Command substitution swallows the exit status inside a condition, so the
    # verdict is taken first. An empty one would otherwise read as "not affected".
    verdict="$(classify_ref "refs/tags/$tag")" || die "cannot classify tag $tag"
    [[ "$verdict" == affected ]] || continue
    printf '%s\n' "$tag"
  done <<<"$TAGS"
}

advisory_tags() {
  awk -v start="$START_MARKER" -v end="$END_MARKER" '
    { t = $0; sub(/^[ \t\r]+/, "", t); sub(/[ \t\r]+$/, "", t) }
    t == start { if (state != 0) bad = 1; state = 1; next }
    t == end   { if (state == 1) state = 2; else bad = 1; next }
    state == 1 && t != "" {
      sub(/^[-*+][ \t]+/, "", t); gsub(/`/, "", t)
      sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      print t
    }
    END { exit (state == 2 && !bad) ? 0 : 1 }
  ' "$1"
}

check_advisory() {
  local advisory="$REPO/$ADVISORY_PATH"
  [[ -f "$advisory" ]] || die "advisory not found: $advisory"
  advisory_tags "$advisory" >"$SCRATCH/advisory" ||
    die "$ADVISORY_PATH needs exactly one $START_MARKER and $END_MARKER pair"
  list_affected >"$SCRATCH/computed"
  if diff -u --label "$ADVISORY_PATH" --label "affected tags" "$SCRATCH/advisory" "$SCRATCH/computed"; then
    echo "advisory matches: $(awk 'END { print NR }' "$SCRATCH/computed") affected releases"
  else
    die "the advisory list differs from the tags. Replace the block with one bullet per line of: bash scripts/list-affected-releases.sh"
  fi
}

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode=list
ref=""
while (($#)); do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    -C)
      (($# >= 2)) || die "-C needs a directory"
      REPO="$2"; shift 2 ;;
    --ref)
      [[ "$mode" != ref ]] || die "give --ref once"
      [[ "$mode" == list ]] || die "give at most one of --ref and --check"
      (($# >= 2)) || die "--ref needs a ref"
      mode=ref; ref="$2"; shift 2 ;;
    --check)
      [[ "$mode" == list ]] || die "give at most one of --ref and --check"
      mode=check; shift ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

TOPLEVEL="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" ||
  die "not a git work tree: $REPO"
REPO="$TOPLEVEL"

# A shallow or single-tag clone answers the tag query without failing, and the
# short list it produces reads exactly like a real one.
case "$(git -C "$REPO" rev-parse --is-shallow-repository 2>/dev/null)" in
  false) ;;
  true) die "$REPO is a shallow clone, so its tag list is incomplete. Run 'git fetch --tags --unshallow' first." ;;
  *) die "this git cannot report whether $REPO is shallow, so the tag list cannot be trusted. Needs git 2.15 or newer." ;;
esac
TAGS="$(git -C "$REPO" tag -l 'v*' --sort=v:refname)"
[[ -n "$TAGS" ]] ||
  die "no v* tags in $REPO. Run 'git fetch --tags' first."

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

case "$mode" in
  list) list_affected ;;
  check) check_advisory ;;
  ref)
    # Resolve to a commit id here so classify_ref never sees a user-typed ref.
    commit="$(git -C "$REPO" rev-parse --verify --quiet --end-of-options "$ref^{commit}")" ||
      die "cannot resolve ref: $ref"
    classify_ref "$commit"
    ;;
esac
