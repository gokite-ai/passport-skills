#!/usr/bin/env bash
# Optimize skill trigger descriptions using an eval + improve loop.
#
# This script is an exploratory tool, not a build step. It iteratively rewrites
# each skill's `description:` frontmatter and scores the rewrite against trigger
# evals — keeping whichever variant scores best.
#
# Prerequisites (none of which this repo ships):
#   1. The Anthropic `skill-creator` plugin installed locally. The loop runner
#      is `scripts/run_loop` inside that plugin's directory.
#      Default path: ~/.claude/plugins/marketplaces/anthropic-agent-skills/skills/skill-creator
#      Override via $SKILL_CREATOR.
#   2. Trigger-eval fixtures at evals/trigger-evals/<skill>.json. These were
#      intentionally NOT ported from spring-test — evals/routing-experiments/
#      FINDINGS.md documents why the harness can't actually exercise Skill()
#      routing. Generate fresh fixtures before running this script.
#   3. Python 3 with the modules skill-creator depends on.
#
# Usage:
#   REPO=/path/to/passport-skills \
#   SKILL_CREATOR=~/.claude/plugins/marketplaces/anthropic-agent-skills/skills/skill-creator \
#   OUT=/tmp/passport-skills-evals \
#   MODEL=claude-haiku-4-5-20251001 \
#   ./scripts/optimize-descriptions.sh [skill1 skill2 ...]
#
# With no skill arguments, runs all 14 skills in parallel.

set -euo pipefail

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
OUT="${OUT:-/tmp/passport-skills-evals}"
SKILL_CREATOR="${SKILL_CREATOR:-$HOME/.claude/plugins/marketplaces/anthropic-agent-skills/skills/skill-creator}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"

ALL_SKILLS=(
  activity
  attach-session
  authenticate-user
  cloud-deploy
  form-session-delegation
  kite-discovery
  kite-passport
  manage-agents
  report-feedback
  request-session
  shopping
  upgrade-passport
  wallet-send
  x402-execute
)

if [ ! -d "$SKILL_CREATOR" ]; then
  echo "ERROR: SKILL_CREATOR not found at: $SKILL_CREATOR" >&2
  echo "Install the skill-creator plugin or override SKILL_CREATOR." >&2
  exit 2
fi

if [ ! -d "$REPO/evals/trigger-evals" ]; then
  echo "ERROR: trigger-eval fixtures missing at: $REPO/evals/trigger-evals/" >&2
  echo "See evals/routing-experiments/FINDINGS.md for context on why these aren't shipped." >&2
  exit 2
fi

SKILLS=("${@:-${ALL_SKILLS[@]}}")

echo "Running description optimizer for: ${SKILLS[*]}"
echo "Repo:           $REPO"
echo "Skill-creator:  $SKILL_CREATOR"
echo "Output dir:     $OUT"
echo "Model:          $MODEL"
echo ""

cd "$SKILL_CREATOR"

pids=()
launched=()
for skill in "${SKILLS[@]}"; do
  if [ ! -f "$REPO/evals/trigger-evals/$skill.json" ]; then
    echo "  ! $skill: missing trigger-eval fixture, skipping"
    continue
  fi
  mkdir -p "$OUT/$skill"
  echo "Starting $skill..."
  python3 -m scripts.run_loop \
    --eval-set "$REPO/evals/trigger-evals/$skill.json" \
    --skill-path "$REPO/$skill" \
    --model "$MODEL" \
    --runs-per-query 2 \
    --holdout 0.4 \
    --results-dir "$OUT/$skill" \
    --report none \
    > "$OUT/$skill/run_loop.log" 2>&1 &
  pids+=("$!")
  # Track skill name alongside its pid (not SKILLS[$i]) — a skipped fixture
  # would otherwise desync the two arrays' indices, misattributing this
  # skill's success/failure line to whichever skill happens to land at the
  # same index.
  launched+=("$skill")
done

echo "Waiting for ${#pids[@]} job(s)..."
failed=0
for i in "${!pids[@]}"; do
  if wait "${pids[$i]}"; then
    echo "  ✓ ${launched[$i]}"
  else
    echo "  ✗ ${launched[$i]} (exit ${?}) — check $OUT/${launched[$i]}/run_loop.log"
    failed=$((failed + 1))
  fi
done

echo ""
echo "=== Results ==="
python3 - <<EOF
import json, glob, sys
ok = 0
for f in sorted(glob.glob('$OUT/*/run_loop.json')):
    skill = f.split('/')[-2]
    try:
        d = json.load(open(f))
        print(f"{skill}: best={d['best_test_score']} exit={d['exit_reason']}")
        print(f"  {d['best_description'][:120]}")
        ok += 1
    except Exception as e:
        print(f"{skill}: ERROR - {e}")
    print()
EOF

if [ "$failed" -gt 0 ]; then
  exit 1
fi
