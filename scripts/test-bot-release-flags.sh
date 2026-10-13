#!/usr/bin/env bash
# Test bot-release-flags.sh with stub gh (ATE-160)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap "rm -rf '$WORK'" EXIT

LOG="$WORK/gh.log"
STUB="$WORK/stub-bin"
mkdir -p "$STUB"

# Stub gh that logs arguments and returns fixture values
cat > "$STUB/gh" <<'STUB_END'
#!/usr/bin/env bash
echo "$@" >> "@@LOG@@"

case "$1 $2" in
  "api repos/"*)
    # Parse repo path to determine response
    path="${3#repos/}"
    
    if [[ "$path" =~ git/ref/tags/bot-release/(prerelease|promote)/v([0-9.]+)/([0-9]+) ]]; then
      action="${BASH_REMATCH[1]}"
      stamp="${BASH_REMATCH[3]}"
      
      # Return lightweight tag for stamp=1234567890123 (13 digits)
      if [[ "$stamp" = "1234567890123" ]]; then
        echo '{"object":{"type":"commit"}}'
        exit 0
      fi
      
      # All other valid-format tags return annotated
      echo '{"object":{"type":"tag"}}'
      exit 0
    fi
    
    if [[ "$path" =~ git/tags/bot-release/promote/ ]]; then
      tag="${3#repos/*/git/tags/}"
      
      # Return message with Slack-OK for valid promote, without for noauth case
      if [[ "$tag" =~ noauth ]]; then
        echo '{"message":"Promote without auth"}'
      else
        echo '{"message":"Release v3.5.6\n\nSlack-OK: https://gokite-team.slack.com/archives/C123/p1234567890"}'
      fi
      exit 0
    fi
    
    if [[ "$path" =~ releases/latest ]]; then
      # Return the version from fixture
      version="${FIXTURE_LATEST:-v3.5.6}"
      echo "{\"tag_name\":\"$version\"}"
      exit 0
    fi
    ;;
    
  "release view"*)
    version="$3"
    
    # missing case: v9.9.9 doesn't exist
    if [[ "$version" = "v9.9.9" ]]; then
      echo "release not found" >&2
      exit 1
    fi
    
    # draft case: v1.0.0-draft is a draft
    if [[ "$version" = "v1.0.0-draft" ]]; then
      echo '{"isDraft":true}'
      exit 0
    fi
    
    # All others exist and are not drafts
    echo '{"isDraft":false}'
    exit 0
    ;;
    
  "release edit"*)
    # Just log the edit, don't actually do anything
    exit 0
    ;;
esac

echo "Stub gh: unhandled: $*" >&2
exit 1
STUB_END

# Replace @@LOG@@ placeholder with actual log path
sed -i "s|@@LOG@@|$LOG|g" "$STUB/gh"
chmod +x "$STUB/gh"

# Stub jq (might be called by the script)
cat > "$STUB/jq" <<'JQ_END'
#!/usr/bin/env bash
exec /usr/bin/jq "$@"
JQ_END
chmod +x "$STUB/jq"

PATH="$STUB:$PATH"
export REPO="test/repo"

run_test() {
  local name="$1"
  local tag="$2"
  local expect_exit="$3"
  local expect_edit="${4:-}"
  
  > "$LOG"
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

# Test 1: Valid prerelease tag
run_test "valid prerelease" \
  "bot-release/prerelease/v3.5.6/20261013120000" \
  0 \
  "release edit v3.5.6 --repo test/repo --prerelease --latest=false"

# Test 2: Valid promote tag with Slack-OK
run_test "valid promote with Slack-OK" \
  "bot-release/promote/v3.5.5/20261013120000" \
  0 \
  "release edit v3.5.5 --repo test/repo --prerelease=false --latest"

# Test 3: Promote tag without Slack-OK (contains "noauth" to trigger stub behavior)
run_test "promote without Slack-OK" \
  "bot-release/promote/v3.5.6-noauth/20261013120000" \
  1 \
  ""

# Test 4: Lightweight promote tag (13-digit stamp triggers lightweight in stub)
run_test "lightweight tag" \
  "bot-release/promote/v3.5.6/1234567890123" \
  1 \
  ""

# Test 5: Tag with invalid version format (v1.2 not v1.2.3)
run_test "invalid version format" \
  "bot-release/prerelease/v1.2/20261013120000" \
  1 \
  ""

# Test 6: Release missing (v9.9.9 triggers not-found in stub)
run_test "release not found" \
  "bot-release/prerelease/v9.9.9/20261013120000" \
  1 \
  ""

# Test 7: Release is draft (v1.0.0-draft triggers draft in stub)
run_test "release is draft" \
  "bot-release/prerelease/v1.0.0-draft/20261013120000" \
  1 \
  ""

# Test 8: Promote where latest comes back as different tag
export FIXTURE_LATEST="v3.5.7"
run_test "promote latest mismatch" \
  "bot-release/promote/v3.5.6/20261013120000" \
  1 \
  ""
unset FIXTURE_LATEST

echo "BOT RELEASE FLAGS OK"
