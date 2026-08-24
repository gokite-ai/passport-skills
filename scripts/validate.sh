#!/usr/bin/env bash
# Validates the skill repository structure.
#
# Checks:
#   1. skills.json exists and is valid JSON
#   2. Every skill listed in skills.json has a non-empty SKILL.md
#   3. No orphan skill directories (directories with SKILL.md not in skills.json)
#
# Usage: bash scripts/validate.sh
# Exit codes:
#   0  All checks passed
#   1  One or more checks failed
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_JSON="$REPO_ROOT/skills.json"
ERRORS=0

echo "==> Validating skill repository structure"
echo ""

# ---- Check 1: skills.json exists and is valid JSON ----
if [[ ! -f "$SKILLS_JSON" ]]; then
  echo "FAIL: skills.json not found at $SKILLS_JSON"
  exit 1
fi

if ! node -e "JSON.parse(require('fs').readFileSync('$SKILLS_JSON', 'utf8'))" 2>/dev/null; then
  echo "FAIL: skills.json is not valid JSON"
  exit 1
fi

echo "  [OK] skills.json is valid JSON"

# ---- Check 2: Every skill in skills.json has a non-empty SKILL.md ----
SKILL_PATHS=$(node -e "
  const s = JSON.parse(require('fs').readFileSync('$SKILLS_JSON', 'utf8'));
  s.skills.forEach(sk => console.log(sk.slug + '|' + sk.path));
")

while IFS='|' read -r slug path; do
  FULL_PATH="$REPO_ROOT/$path"
  if [[ ! -f "$FULL_PATH" ]]; then
    echo "  FAIL: Skill '$slug' — file not found: $path"
    ERRORS=$((ERRORS + 1))
  elif [[ ! -s "$FULL_PATH" ]]; then
    echo "  FAIL: Skill '$slug' — file is empty: $path"
    ERRORS=$((ERRORS + 1))
  else
    echo "  [OK] $slug -> $path"
  fi
done <<< "$SKILL_PATHS"

# ---- Check 3: No orphan directories ----
REGISTERED_SLUGS=$(node -e "
  const s = JSON.parse(require('fs').readFileSync('$SKILLS_JSON', 'utf8'));
  s.skills.forEach(sk => console.log(sk.slug));
")

for dir in "$REPO_ROOT"/*/; do
  dir_name=$(basename "$dir")
  # Skip non-skill directories
  if [[ "$dir_name" == "scripts" || "$dir_name" == "node_modules" || "$dir_name" == ".github" || "$dir_name" == ".git" || "$dir_name" == ".idea" ]]; then
    continue
  fi
  if [[ -f "$dir/SKILL.md" ]]; then
    if ! echo "$REGISTERED_SLUGS" | grep -qx "$dir_name"; then
      echo "  WARN: Directory '$dir_name' has a SKILL.md but is not registered in skills.json"
      ERRORS=$((ERRORS + 1))
    fi
  fi
done

# ---- Check 4: Required fields in skills.json ----
MISSING_FIELDS=$(node -e "
  const s = JSON.parse(require('fs').readFileSync('$SKILLS_JSON', 'utf8'));
  const required = ['slug', 'name', 'description', 'path'];
  s.skills.forEach((sk, i) => {
    required.forEach(f => {
      if (!sk[f]) console.log('Skill index ' + i + ' missing field: ' + f);
    });
  });
")

if [[ -n "$MISSING_FIELDS" ]]; then
  echo ""
  while read -r line; do
    echo "  FAIL: $line"
    ERRORS=$((ERRORS + 1))
  done <<< "$MISSING_FIELDS"
fi

# ---- Check 5: SKILL.md frontmatter parses and references/ links resolve ----
if ! node "$REPO_ROOT/scripts/check-skill-content.js"; then
  ERRORS=$((ERRORS + 1))
fi

# ---- Check 6: skill groups are consistent ----
# skills.json's top-level "groups" map declares the known skill groups
# (user, buyer-agent, seller-agent, ...). Every skill's "group" field
# (skills predating this field default to "user") must reference a group
# that actually exists, and every non-"user" group must have a backing
# directory -- the group's README.md lives there even before any skill
# does, so an agent researching "what does the buyer-agent group drive"
# always finds real documentation, not a 404.
GROUP_ERRORS=$(node -e "
  const s = JSON.parse(require('fs').readFileSync('$SKILLS_JSON', 'utf8'));
  const groups = s.groups || {};
  const groupNames = new Set(Object.keys(groups));
  const lines = [];
  if (!groupNames.has('user')) {
    lines.push('groups map is missing the required \"user\" group');
  }
  s.skills.forEach(sk => {
    const group = sk.group || 'user';
    if (!groupNames.has(group)) {
      lines.push('Skill \'' + sk.slug + '\' references unknown group: ' + group);
    }
  });
  console.log(lines.join('\n'));
")

if [[ -n "$GROUP_ERRORS" ]]; then
  echo ""
  while IFS= read -r line; do
    echo "  FAIL: $line"
    ERRORS=$((ERRORS + 1))
  done <<< "$GROUP_ERRORS"
fi

GROUP_DIRS=$(node -e "
  const s = JSON.parse(require('fs').readFileSync('$SKILLS_JSON', 'utf8'));
  Object.keys(s.groups || {})
    .filter(name => name !== 'user')
    .forEach(name => console.log(name));
")

while IFS= read -r group; do
  [[ -z "$group" ]] && continue
  GROUP_DIR="$REPO_ROOT/$group"
  if [[ ! -d "$GROUP_DIR" ]]; then
    echo "  FAIL: group '$group' has no backing directory: $group/"
    ERRORS=$((ERRORS + 1))
  elif [[ ! -f "$GROUP_DIR/README.md" ]]; then
    echo "  FAIL: group '$group' directory is missing README.md: $group/README.md"
    ERRORS=$((ERRORS + 1))
  else
    echo "  [OK] group '$group' -> $group/README.md"
  fi
done <<< "$GROUP_DIRS"

echo "  [OK] skill groups are consistent"

# ---- Check 7: setup.sh fallback version pins match skills.json ----
# Skill-local setup.sh copies embed DEFAULT_MIN_CLI_VERSION as the fallback for
# standalone installs where skills.json does not ship. A drifted fallback
# silently accepts a CLI older than the skills can drive.
#
# The FLOOR only. There used to be a ceiling here too, mirrored from
# max_cli_version, and it earned its removal: it gated nothing a user would
# notice — one line of --help text — while costing a seven-way duplication that
# had to be raised for every CLI release, and a hard upper-bound gate in
# passport-release that failed the bundle when it was not.
MIN_CLI=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$SKILLS_JSON','utf8')).min_cli_version.split('-')[0])")

while IFS= read -r script; do
  s_min=$(grep -oE '^DEFAULT_MIN_CLI_VERSION="[^"]*"' "$script" | cut -d'"' -f2 || true)
  rel="${script#"$REPO_ROOT"/}"
  if [[ -z "$s_min" ]]; then
    echo "  FAIL: $rel — missing DEFAULT_MIN_CLI_VERSION pin"
    ERRORS=$((ERRORS + 1))
  elif [[ "$s_min" != "$MIN_CLI" ]]; then
    echo "  FAIL: $rel — fallback floor ($s_min) drifted from skills.json ($MIN_CLI)"
    ERRORS=$((ERRORS + 1))
  else
    echo "  [OK] $rel fallback floor matches skills.json"
  fi
done < <(find "$REPO_ROOT" -maxdepth 3 -name "setup.sh" -path "*/scripts/*" -not -path "*/node_modules/*" | grep -v "setup-ksearch")

# ---- Summary ----
echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "FAILED: $ERRORS error(s) found"
  exit 1
else
  echo "PASSED: All checks passed"
  exit 0
fi
