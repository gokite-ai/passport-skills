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

# ---- Check 6: setup.sh fallback version pins match skills.json ----
# Skill-local setup.sh copies embed DEFAULT_CLI_VERSION / DEFAULT_MIN_CLI_VERSION
# as fallbacks for standalone installs where skills.json does not ship. A
# drifted fallback silently installs a CLI the skills cannot drive.
MAX_CLI=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$SKILLS_JSON','utf8')).max_cli_version)")
MIN_CLI=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$SKILLS_JSON','utf8')).min_cli_version.split('-')[0])")

while IFS= read -r script; do
  s_max=$(grep -oE '^DEFAULT_CLI_VERSION="[^"]*"' "$script" | cut -d'"' -f2 || true)
  s_min=$(grep -oE '^DEFAULT_MIN_CLI_VERSION="[^"]*"' "$script" | cut -d'"' -f2 || true)
  rel="${script#"$REPO_ROOT"/}"
  if [[ -z "$s_max" || -z "$s_min" ]]; then
    echo "  FAIL: $rel — missing DEFAULT_CLI_VERSION / DEFAULT_MIN_CLI_VERSION pins"
    ERRORS=$((ERRORS + 1))
  elif [[ "$s_max" != "$MAX_CLI" || "$s_min" != "$MIN_CLI" ]]; then
    echo "  FAIL: $rel — fallback pins ($s_min..$s_max) drifted from skills.json ($MIN_CLI..$MAX_CLI)"
    ERRORS=$((ERRORS + 1))
  else
    echo "  [OK] $rel fallback pins match skills.json"
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
