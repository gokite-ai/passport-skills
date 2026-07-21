#!/usr/bin/env node
// Validates that every skill's SKILL.md frontmatter is parseable YAML with the
// required fields, and that every `@references/*.md` link in the body points
// at a file that actually exists.
'use strict';
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const repoRoot = path.resolve(__dirname, '..');
const { skills } = JSON.parse(fs.readFileSync(path.join(repoRoot, 'skills.json'), 'utf8'));

let errors = 0;

for (const skill of skills) {
  const skillPath = path.join(repoRoot, skill.path);
  const skillDir = path.dirname(skillPath);

  let content;
  try {
    content = fs.readFileSync(skillPath, 'utf8');
  } catch (err) {
    console.log(`  FAIL: ${skill.slug} — could not read SKILL.md at ${path.relative(repoRoot, skillPath)}: ${err.message}`);
    errors++;
    continue;
  }

  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  if (!match) {
    console.log(`  FAIL: ${skill.slug} — SKILL.md has no frontmatter block`);
    errors++;
    continue;
  }
  const [, frontmatterText, body] = match;

  let frontmatter;
  try {
    frontmatter = yaml.load(frontmatterText);
  } catch (err) {
    console.log(`  FAIL: ${skill.slug} — frontmatter is not valid YAML: ${err.message}`);
    errors++;
    continue;
  }

  for (const field of ['name', 'description']) {
    if (!frontmatter || !frontmatter[field]) {
      console.log(`  FAIL: ${skill.slug} — frontmatter missing required field: ${field}`);
      errors++;
    }
  }

  const refPattern = /@references\/([\w./-]+\.md)/g;
  const seen = new Set();
  const referencesDir = path.join(skillDir, 'references');
  let refMatch;
  while ((refMatch = refPattern.exec(body)) !== null) {
    const refFile = refMatch[1];
    if (seen.has(refFile)) continue;
    seen.add(refFile);
    const refPath = path.resolve(referencesDir, refFile);
    if (refPath !== referencesDir && !refPath.startsWith(referencesDir + path.sep)) {
      console.log(`  FAIL: ${skill.slug} — references/${refFile} resolves outside the references/ directory, rejected`);
      errors++;
      continue;
    }
    if (!fs.existsSync(refPath)) {
      console.log(`  FAIL: ${skill.slug} — references/${refFile} referenced in SKILL.md but not found at ${path.relative(repoRoot, refPath)}`);
      errors++;
    }
  }
}

if (errors > 0) {
  console.log('');
  console.log(`FAILED: ${errors} content error(s) found`);
  process.exit(1);
}
console.log('  [OK] All SKILL.md frontmatter parses and references/ links resolve');
