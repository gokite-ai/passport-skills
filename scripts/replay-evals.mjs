#!/usr/bin/env node
// Replay captured answers without invoking agents, wallets, or paid services.
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const digest = (value) => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const nonempty = (value) => typeof value === 'string' && value.trim().length > 0;

/** Reject ambiguous inputs before scoring: duplicate IDs can hide missing cases. */
export function validateSuite(suite) {
  if (!Array.isArray(suite) || suite.length === 0) throw new Error('Suite must be a nonempty array');
  const ids = new Set();
  for (const item of suite) {
    if (!item || !Number.isSafeInteger(item.id) || item.id < 1 || ids.has(item.id)) {
      throw new Error('Suite IDs must be unique positive safe integers');
    }
    if (!nonempty(item.prompt) || !nonempty(item.expected_output)
        || !Array.isArray(item.assertions) || item.assertions.length === 0
        || !item.assertions.every(nonempty)) throw new Error(`Invalid eval ${item.id}`);
    ids.add(item.id);
  }
  return suite;
}

/** Canonical fields bind captures to prompts AND grading rules, ignoring JSON whitespace. */
export function suiteDigest(suite) {
  return digest(validateSuite(suite).map(({ id, prompt, expected_output, assertions }) =>
    ({ id, prompt, expected_output, assertions })));
}

/** The capture request deliberately omits the answer key and literal assertions. */
export function captureRequest(suite) {
  return {
    schemaVersion: 1,
    suiteSha256: suiteDigest(suite),
    cases: suite.map(({ id, prompt }) => ({ id, prompt })),
  };
}

/** Missing captures remain in the denominator; literal matches are not semantic approval. */
export function replay(suite, capture) {
  const hash = suiteDigest(suite);
  if (!capture || capture.schemaVersion !== 1 || capture.suiteSha256 !== hash) {
    throw new Error('Capture schemaVersion or suiteSha256 does not match the current suite');
  }
  if (!['recorded', 'synthetic'].includes(capture.kind) || !nonempty(capture.producer)
      || !Array.isArray(capture.records)) throw new Error('Capture needs kind, producer and records');
  const validIds = new Set(suite.map((item) => item.id));
  const records = new Map();
  for (const record of capture.records) {
    if (!record || !validIds.has(record.id) || records.has(record.id)) {
      throw new Error('Capture contains an unknown or duplicate eval ID');
    }
    const hasResponse = Object.hasOwn(record, 'response');
    const hasError = Object.hasOwn(record, 'error');
    if (hasResponse === hasError || (hasResponse && typeof record.response !== 'string')
        || (hasError && !nonempty(record.error))) {
      throw new Error(`Eval ${record.id} needs exactly one response string or nonempty error`);
    }
    records.set(record.id, record);
  }
  const cases = suite.map((item) => {
    const record = records.get(item.id);
    const status = !record ? 'missing' : Object.hasOwn(record, 'error') ? 'error' : 'captured';
    const assertions = item.assertions.map((literal) => {
      const offset = status === 'captured' ? record.response.indexOf(literal) : -1;
      return { literal, passed: offset >= 0, offset };
    });
    return {
      id: item.id, status,
      responseSha256: status === 'captured' ? digest(record.response) : null,
      // Avoid copying account data or backend error text into public CI artifacts.
      errorSha256: status === 'error' ? digest(record.error) : null,
      assertions,
      literalPassed: status === 'captured' && assertions.every((a) => a.passed),
      semanticReview: 'required',
    };
  });
  const allAssertions = cases.flatMap((item) => item.assertions);
  const summary = {
    total: cases.length,
    captured: cases.filter((item) => item.status === 'captured').length,
    missing: cases.filter((item) => item.status === 'missing').length,
    errors: cases.filter((item) => item.status === 'error').length,
    literalPassed: cases.filter((item) => item.literalPassed).length,
    assertions: allAssertions.length,
    matchedAssertions: allAssertions.filter((item) => item.passed).length,
    semanticReviewRequired: cases.length,
  };
  return {
    schemaVersion: 1, kind: capture.kind, producer: capture.producer,
    suiteSha256: hash, captureSha256: digest(capture), summary, cases,
  };
}

// XML 1.0 excludes most controls even when escaped; preserve valid Unicode code points.
const xml = (value) => String(value)
  .replace(/[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD\u{10000}-\u{10FFFF}]/gu, '\uFFFD')
  .replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[c]));

/** One JUnit testcase per assertion makes CI point to the exact missing marker. */
export function junit(report) {
  const rows = report.cases.flatMap((item) => item.assertions.map((assertion, index) => ({ item, assertion, index })));
  const failures = rows.filter(({ item, assertion }) => item.status === 'captured' && !assertion.passed).length;
  const errors = rows.filter(({ item }) => item.status !== 'captured').length;
  const tests = rows.map(({ item, assertion, index }) => {
    const name = xml(`eval ${item.id} assertion ${index + 1}: ${assertion.literal}`);
    const detail = item.status !== 'captured'
      ? `<error type="${item.status}" message="Capture ${item.status}; assertion not evaluated"/>`
      : assertion.passed ? '' : '<failure type="literal-mismatch" message="Required literal was not found"/>';
    return `    <testcase classname="passport.literal-replay" name="${name}">${detail}</testcase>`;
  });
  return `<?xml version="1.0" encoding="UTF-8"?>\n<testsuites tests="${rows.length}" failures="${failures}" errors="${errors}">\n`
    + `  <testsuite name="Passport literal replay (${xml(report.kind)})" tests="${rows.length}" failures="${failures}" errors="${errors}">\n`
    + '    <properties><property name="semanticReview" value="required"/>'
    + `<property name="suiteSha256" value="${report.suiteSha256}"/></properties>\n`
    + tests.join('\n') + '\n  </testsuite>\n</testsuites>\n';
}

const md = (value) => String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/\|/g, '&#124;').replace(/`/g, '&#96;').replace(/[\r\n]/g, ' ');

export function markdown(report) {
  const s = report.summary;
  const lines = [
    '# Passport transcript replay', '',
    `Capture kind: **${report.kind}**. Producer: ${md(report.producer)}.`, '',
    '**Literal checks only. All expected behaviors still require semantic review.**',
    ...(report.kind === 'synthetic' ? ['**Synthetic test data: this is not evidence of an agent passing the skill evals.**'] : []), '',
    `Cases: ${s.total}; captured: ${s.captured}; missing: ${s.missing}; errors: ${s.errors}.`,
    `Literal-pass cases: ${s.literalPassed}/${s.total}; matched assertions: ${s.matchedAssertions}/${s.assertions}.`, '',
    `Suite SHA-256: ${report.suiteSha256}`, '',
    '| Eval | Capture | Literal result | Unmatched assertions |',
    '| --- | --- | --- | --- |',
  ];
  for (const item of report.cases) {
    lines.push(`| ${item.id} | ${item.status} | ${item.literalPassed ? 'pass' : 'fail'} | `
      + `${item.assertions.filter((a) => !a.passed).map((a) => md(a.literal)).join('; ')} |`);
  }
  return lines.join('\n') + '\n';
}

/** Exit 1 is an incomplete/failed literal replay; malformed input or I/O uses exit 2. */
export async function main(args) {
  if (args.length === 1 && args[0] === '--help') {
    console.log('Usage: node scripts/replay-evals.mjs [--suite FILE] --request FILE\n'
      + '       node scripts/replay-evals.mjs [--suite FILE] --capture FILE --out DIR\n'
      + 'Replays literal assertions only; never executes agents or approves semantic behavior.');
    return 0;
  }
  const options = {};
  for (let i = 0; i < args.length; i += 2) {
    const key = args[i];
    if (!['--suite', '--request', '--capture', '--out'].includes(key)
        || Object.hasOwn(options, key) || !args[i + 1] || args[i + 1].startsWith('--')) {
      throw new Error('Unknown, repeated or incomplete option; use --help');
    }
    options[key] = resolve(args[i + 1]);
  }
  const requestMode = !!options['--request'];
  if (requestMode ? options['--capture'] || options['--out'] : !options['--capture'] || !options['--out']) {
    throw new Error('Choose --request FILE or --capture FILE --out DIR');
  }
  const suitePath = options['--suite'] || resolve(root, 'evals/evals.json');
  const suite = validateSuite(JSON.parse(await readFile(suitePath, 'utf8')));
  if (requestMode) {
    // Exclusive creation prevents accidental overwrites of suites or existing captures.
    await writeFile(options['--request'], JSON.stringify(captureRequest(suite), null, 2) + '\n', { flag: 'wx' });
    console.log(`Wrote ${suite.length} prompts (no answer key)`);
    return 0;
  }
  const capture = JSON.parse(await readFile(options['--capture'], 'utf8'));
  const report = replay(suite, capture);
  // Require a fresh directory so a failed run cannot leave a stale green report behind.
  await mkdir(options['--out']);
  for (const [name, value] of [
    ['report.json', JSON.stringify(report, null, 2) + '\n'],
    ['report.md', markdown(report)], ['junit.xml', junit(report)],
  ]) await writeFile(resolve(options['--out'], name), value, { flag: 'wx' });
  console.log(JSON.stringify({ kind: report.kind, ...report.summary }));
  return report.summary.literalPassed === report.summary.total ? 0 : 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then((code) => { process.exitCode = code; }).catch((error) => {
    console.error(`Replay error: ${error.message}`);
    process.exitCode = 2;
  });
}
