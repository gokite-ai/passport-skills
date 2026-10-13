#!/usr/bin/env bash
# Bot release flags editor for gokite-ai/passport-skills (ATE-160)
# Edits release flags by pushing an annotated tag: bot-release/prerelease/vX.Y.Z/<14-digit-UTC> marks a release
# as prerelease and not latest; bot-release/promote/vX.Y.Z/<14-digit-UTC> makes it the full latest release only
# when the tag message has Yusuke's Slack-OK permalink. Both tags must be annotated. Any other tag, a lightweight
# tag, a promote tag without Slack-OK, or a missing or draft release exits 1 without editing.
set -euo pipefail

TAG="${TAG:?TAG env var required}"
REPO="${REPO:?REPO env var required}"

# Tag parsing: bot-release/(prerelease|promote)/vX.Y.Z/<14-digit-stamp>
if ! [[ "$TAG" =~ ^bot-release/(prerelease|promote)/v([0-9]+\.[0-9]+\.[0-9]+)/([0-9]{14})$ ]]; then
  echo "::error::Tag $TAG does not match bot-release/(prerelease|promote)/vX.Y.Z/<14-digit-UTC>" >&2
  exit 1
fi

action="${BASH_REMATCH[1]}"
version="v${BASH_REMATCH[2]}"

# Require annotated tag: fetch the ref to get the object SHA, then fetch that object
ref_sha="$(gh api "repos/$REPO/git/ref/tags/$TAG" --jq '.object.sha' 2>&1)" || {
  echo "::error::Failed to fetch tag ref $TAG from $REPO" >&2
  exit 1
}

tag_type="$(gh api "repos/$REPO/git/tags/$ref_sha" --jq '.object.type' 2>&1)" || {
  echo "::error::Failed to fetch tag object $ref_sha from $REPO (lightweight tag?)" >&2
  exit 1
}

if [[ "$tag_type" != "commit" ]]; then
  echo "::error::Tag $TAG is not an annotated tag (object type: $tag_type)" >&2
  exit 1
fi

# For promote, require Slack-OK line in the message
if [[ "$action" = "promote" ]]; then
  tag_message="$(gh api "repos/$REPO/git/tags/$ref_sha" --jq '.message' 2>&1)" || {
    echo "::error::Failed to fetch tag message for $TAG" >&2
    exit 1
  }
  
  if ! echo "$tag_message" | grep -qE '^Slack-OK: https://[a-z0-9-]+\.slack\.com/archives/[A-Z0-9]+/p[0-9]+'; then
    echo "::error::Promote tag $TAG message missing Slack-OK line" >&2
    exit 1
  fi
fi

# Check that release exists and is not a draft
release_info="$(gh release view "$version" --repo "$REPO" --json isDraft 2>&1)" || {
  echo "::error::Release $version not found in $REPO" >&2
  exit 1
}

is_draft="$(echo "$release_info" | jq -r '.isDraft')"
if [[ "$is_draft" = "true" ]]; then
  echo "::error::Release $version is a draft, cannot edit" >&2
  exit 1
fi

# Edit release based on action
case "$action" in
  prerelease)
    gh release edit "$version" --repo "$REPO" --prerelease --latest=false
    echo "Marked $version as prerelease and not latest"
    ;;
  promote)
    gh release edit "$version" --repo "$REPO" --prerelease=false --latest
    echo "Promoted $version to full latest release"
    
    # Verify it's actually latest now
    latest_tag="$(gh api "repos/$REPO/releases/latest" --jq '.tag_name' 2>&1)" || {
      echo "::error::Failed to fetch latest release after promotion" >&2
      exit 1
    }
    
    if [[ "$latest_tag" != "$version" ]]; then
      echo "::error::Expected latest release to be $version, but got $latest_tag" >&2
      exit 1
    fi
    ;;
  *)
    echo "::error::Unknown action: $action" >&2
    exit 1
    ;;
esac
