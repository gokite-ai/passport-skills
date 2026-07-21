#!/usr/bin/env bash
set -euo pipefail

# Usage: bump-version.sh [--major] [--down]
# Default: bumps patch version up (1.0.3 -> 1.0.4)
# --major: bumps major version and resets minor+patch (1.0.3 -> 2.0.0)
# --down:  decrements patch version (1.0.4 -> 1.0.3)
# --down --major: decrements major version and resets minor+patch (2.0.0 -> 1.0.0)

MAJOR=false
DOWN=false
for arg in "$@"; do
  case "$arg" in
    --major) MAJOR=true ;;
    --down) DOWN=true ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_JSON="$ROOT/skills.json"
PACKAGE_JSON="$ROOT/package.json"

# Read current version from skills.json
CURRENT=$(grep '"version"' "$SKILLS_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if ! [[ "$CURRENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: skills.json \"version\" is not a plain major.minor.patch value: '$CURRENT'" >&2
  exit 1
fi

IFS='.' read -r V_MAJOR V_MINOR V_PATCH <<< "$CURRENT"

if [ "$DOWN" = true ]; then
  if [ "$MAJOR" = true ]; then
    [ "$V_MAJOR" -le 0 ] && echo "Error: major version is already 0" && exit 1
    NEW_VERSION="$((V_MAJOR - 1)).0.0"
  else
    [ "$V_PATCH" -le 0 ] && echo "Error: patch version is already 0" && exit 1
    NEW_VERSION="${V_MAJOR}.${V_MINOR}.$((V_PATCH - 1))"
  fi
elif [ "$MAJOR" = true ]; then
  NEW_VERSION="$((V_MAJOR + 1)).0.0"
else
  NEW_VERSION="${V_MAJOR}.${V_MINOR}.$((V_PATCH + 1))"
fi

echo "Bumping version: $CURRENT -> $NEW_VERSION"

bump_file_version() {
  local file="$1"
  local before after
  # -F: fixed-string match. NEW_VERSION contains literal dots, which would
  # otherwise be interpreted as regex wildcards by plain grep -c.
  before=$(grep -Fc "\"version\": \"$NEW_VERSION\"" "$file" || true)
  # Match on the "version" key, not the old value, so this can't silently
  # no-op if this file's version had already drifted from skills.json's.
  sed -i.bak -E "s/\"version\": \"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" "$file"
  rm -f "$file.bak"
  after=$(grep -Fc "\"version\": \"$NEW_VERSION\"" "$file" || true)
  if [ "$after" -le "$before" ]; then
    echo "ERROR: failed to update version in $file — no \"version\": \"...\" field matched" >&2
    exit 1
  fi
}

bump_file_version "$SKILLS_JSON"
bump_file_version "$PACKAGE_JSON"

echo "Updated skills.json and package.json to $NEW_VERSION"
echo "Run 'npm install' to sync package-lock.json"
