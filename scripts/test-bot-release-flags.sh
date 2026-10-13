#!/usr/bin/env bash
# Test bot-release-flags.sh with stub gh (ATE-160)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

LOG="$WORK/gh.log"
STUB="$WORK/stub-bin"
mkdir -p "$STUB"

# Create stub gh
cat > "$STUB/gh" <<'GHSTUB'
#!/usr/bin/env bash
echo "$@" >> "__LOG__"

jq_query=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[i]}" = "--jq" ]] && (( i+1 < ${#args[@]} )); then
    jq_query="${args[i+1]}"
    break
  fi
done

case "$1" in
  "api")
    path="$2"
    if [[ "$path" =~ ^repos/[^/]+/[^/]+/(.+)$ ]]; then
      path="${BASH_REMATCH[1]}"
    fi
    
    result=""
    
    if [[ "$path" =~ ^git/ref/tags/bot-release/(prerelease|promote)/v([0-9.]+-?[a-z]*)/([0-9]+)$ ]]; then
      action="${BASH_REMATCH[1]}"
      version="${BASH_REMATCH[2]}"
      stamp="${BASH_REMATCH[3]}"
      result="{\"object\":{\"sha\":\"sha-${action}-${version}-${stamp}\"}}"
    elif [[ "$path" =~ ^git/tags/(sha-.+)$ ]]; then
      sha="${BASH_REMATCH[1]}"
      if [[ "$sha" =~ ^sha-([^-]+)-([^-]+)-([0-9]+)$ ]]; then
        action="${BASH_REMATCH[1]}"
        version="${BASH_REMATCH[2]}"
        stamp="${BASH_REMATCH[3]}"
        
        if [[ "$stamp" = "1234567890123" ]]; then
          echo "Not Found" >&2
          exit 1
        fi
        
        msg="Release

Slack-OK: https://gokite-team.slack.com/archives/C123/p1234567890"
        
        if [[ "$action" = "promote" ]]; then
          if [[ "$version" =~ noauth ]]; then
            msg="Promote without auth"
          fi
        else
          msg="Prerelease"
        fi
        
        result=$(printf '{"object":{"type":"commit"},"message":%s}' "$(echo "$msg" | /usr/bin/jq -Rs .)")
      fi
    elif [[ "$path" =~ ^releases/latest$ ]]; then
      version="${FIXTURE_LATEST:-v3.5.6}"
      result="{\"tag_name\":\"$version\"}"
    fi
    
    if [[ -n "$result" ]]; then
      if [[ -n "$jq_query" ]]; then
        echo "$result" | /usr/bin/jq -r "$jq_query"
      else
        echo "$result"
      fi
      exit 0
    fi
    ;;
    
  "release")
    case "$2" in
      "view")
        version="$3"
        if [[ "$version" = "v9.9.9" ]]; then
          echo "release not found" >&2
          exit 1
        fi
        result='{"isDraft":false}'
        if [[ "$version" = "v1.0.0-draft" ]]; then
          result='{"isDraft":true}'
        fi
        if [[ -n "$jq_query" ]]; then
          echo "$result" | /usr/bin/jq -r "$jq_query"
        else
          echo "$result"
        fi
        exit 0
        ;;
      "edit")
        exit 0
        ;;
    esac
    ;;
esac

echo "Stub gh: unhandled: $*" >&2
exit 1
GHSTUB

sed -i "s|__LOG__|$LOG|g" "$STUB/gh"
chmod +x "$STUB/gh"

cat > "$STUB/jq" <<'JQ'
#!/usr/bin/env bash
exec /usr/bin/jq "$@"
JQ
chmod +x "$STUB/jq"

PATH="$STUB:$PATH"
export REPO="test/repo"

run_test() {
  local name="$1"
  local tag="$2"
  local expect_exit="$3"
  local expect_edit="${4:-}"
  
  : > "$LOG"
  export TAG="$tag"
  
  if bash "$SCRIPT_DIR/bot-release-flags.sh" >/dev/null 2>&1; then
    actual_exit=0
  else
    actual_exit=$?
  fi
  
  if [[ "$actual_exit" != "$expect_exit" ]]; then
    echo "FAIL: $name - expected exit $expect_exit, got $actual_exit"
    exit 1
  fi
  
  if [[ -n "$expect_edit" ]]; then
    if ! grep -qF "$expect_edit" "$LOG"; then
      echo "FAIL: $name - expected edit line not found: $expect_edit"
      echo "Log contents:"
      cat "$LOG"
      exit 1
    fi
  fi
}

run_test "valid prerelease" \
  "bot-release/prerelease/v3.5.6/20261013120000" \
  0 \
  "release edit v3.5.6 --repo test/repo --prerelease --latest=false"

run_test "valid promote with Slack-OK" \
  "bot-release/promote/v3.5.6/20261013120000" \
  0 \
  "release edit v3.5.6 --repo test/repo --prerelease=false --latest"

run_test "promote without Slack-OK" \
  "bot-release/promote/v3.5.6-noauth/20261013120000" \
  1 \
  ""

run_test "lightweight tag" \
  "bot-release/promote/v3.5.6/1234567890123" \
  1 \
  ""

run_test "invalid version format" \
  "bot-release/prerelease/v1.2/20261013120000" \
  1 \
  ""

run_test "release not found" \
  "bot-release/prerelease/v9.9.9/20261013120000" \
  1 \
  ""

run_test "release is draft" \
  "bot-release/prerelease/v1.0.0-draft/20261013120000" \
  1 \
  ""

export FIXTURE_LATEST="v3.5.7"
run_test "promote latest mismatch" \
  "bot-release/promote/v3.5.6/20261013120000" \
  1 \
  ""
unset FIXTURE_LATEST

echo "BOT RELEASE FLAGS OK"
