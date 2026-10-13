#!/usr/bin/env bash
# Test passport-setup installer base resolution (ticket AC 1, AC 2).
# Runs from any directory. Covers: (a) scripts/setup.sh --help resolution, (b) SKILL.md fallback
# with scripts/setup.sh absent, (c) fallback with .installer-base absent gives prod, (d) fallback
# with KPASS_BASE_URL=evil exits non-zero and calls curl zero times, (e) grep finds no bare
# 'cat .installer-base' in passport-setup/SKILL.md or GETTING_STARTED.md, (f) shellcheck passes
# on the extracted fallback block.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Copy the repo to a temp dir so we can delete files without affecting the working tree
cp -r "$REPO_ROOT" "$WORK/repo"
cd "$WORK"

# (a) scripts/setup.sh --help: base must be non-empty and match the regex
cd /tmp
base_line="$(bash "$WORK/repo/scripts/setup.sh" --help 2>&1 | grep 'Try: curl -fsSL' | head -1)"
base="$(echo "$base_line" | sed -E 's/.*curl -fsSL ([^ ]+)\/install\.sh.*/\1/')"
[[ -n "$base" ]] || fail "(a) scripts/setup.sh --help gave empty base"
[[ "$base" =~ ^https://cli(\.staging)?\.gokite\.ai$ ]] || fail "(a) base '$base' does not match regex"
echo "PASS (a): scripts/setup.sh --help base is '$base'"

# (b) SKILL.md fallback with scripts/setup.sh absent: resolves base correctly
rm "$WORK/repo/scripts/setup.sh"
# Extract the fallback bash block from SKILL.md
# Look for the get_installer_base function and extract it
awk '/^```bash$/,/^```$/ {if (!/^```/) print}' "$WORK/repo/passport-setup/SKILL.md" | awk '/get_installer_base/,/^curl -fsSL/' > "$WORK/fallback-raw.sh"
if [[ ! -s "$WORK/fallback-raw.sh" ]]; then
  fail "(b) could not extract fallback from SKILL.md"
fi

# Wrap it in a test harness
cat > "$WORK/fallback.sh" << 'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
WRAPPER_EOF

skill_path="$WORK/repo/passport-setup"
sed "s|<skill-directory>|$skill_path|g" "$WORK/fallback-raw.sh" >> "$WORK/fallback.sh"

# Create stub curl that logs its URL and doesn't actually download
cat > "$WORK/curl" << 'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  echo "$arg" >> "$CURL_LOG"
done
exit 0
EOF
chmod +x "$WORK/curl"
export CURL_LOG="$WORK/curl.log"
export PATH="$WORK:$PATH"

cd /tmp
: > "$CURL_LOG"
if ! bash "$WORK/fallback.sh" 2>&1 | tee "$WORK/fallback.out"; then
  fail "(b) SKILL.md fallback exited non-zero"
fi
# Check the curl log for the URL
fallback_base="$(grep -o 'https://[^/]*' "$CURL_LOG" | head -1)"
[[ -n "$fallback_base" ]] || fail "(b) SKILL.md fallback did not call curl with a URL"
[[ "$fallback_base" =~ ^https://cli(\.staging)?\.gokite\.ai$ ]] || fail "(b) fallback base '$fallback_base' does not match regex"
echo "PASS (b): SKILL.md fallback base is '$fallback_base'"

# (c) Fallback with .installer-base removed gives https://cli.gokite.ai
rm -f "$WORK/repo/.installer-base"
unset KPASS_BASE_URL
cd /tmp
: > "$CURL_LOG"
bash "$WORK/fallback.sh" > /dev/null 2>&1 || true
fallback_prod="$(grep -o 'https://[^/]*' "$CURL_LOG" | head -1)"
[[ "$fallback_prod" == "https://cli.gokite.ai" ]] || fail "(c) fallback without .installer-base gave '$fallback_prod', expected https://cli.gokite.ai"
echo "PASS (c): fallback without .installer-base gives https://cli.gokite.ai"

# (d) Fallback with KPASS_BASE_URL=https://evil.example exits non-zero and calls curl zero times
cd /tmp
: > "$CURL_LOG"
if KPASS_BASE_URL=https://evil.example bash "$WORK/fallback.sh" 2>/dev/null; then
  fail "(d) fallback with evil URL did not exit non-zero"
fi
curl_calls="$(wc -l < "$CURL_LOG" 2>/dev/null || echo 0)"
[[ "$curl_calls" -eq 0 ]] || fail "(d) fallback with evil URL called curl $curl_calls times, expected 0"
echo "PASS (d): fallback with KPASS_BASE_URL=https://evil.example exits non-zero and calls curl 0 times"

# (e) grep finds no bare 'cat .installer-base' in passport-setup/SKILL.md or GETTING_STARTED.md
cd "$REPO_ROOT"
match_count="$({ grep -c 'cat .installer-base' passport-setup/SKILL.md GETTING_STARTED.md 2>/dev/null || true; } | awk -F: '{s+=$2} END {print s+0}')"
[[ "$match_count" -eq 0 ]] || fail "(e) found $match_count instances of 'cat .installer-base' in passport-setup/SKILL.md or GETTING_STARTED.md"
echo "PASS (e): no bare 'cat .installer-base' in passport-setup/SKILL.md or GETTING_STARTED.md"

# (f) shellcheck passes on the extracted fallback block
if shellcheck "$WORK/fallback.sh" 2>&1; then
  echo "PASS (f): shellcheck passes on fallback block"
else
  fail "(f) shellcheck failed on fallback block"
fi

echo "PASSPORT SETUP BASE OK"
