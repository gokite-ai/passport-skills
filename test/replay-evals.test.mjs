import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { captureRequest, replay, suiteDigest, validateSuite, junit, markdown } from '../scripts/replay-evals.mjs';

const suite = JSON.parse(await readFile(new URL('../evals/evals.json', import.meta.url), 'utf8'));
const small = [{ id: 1, prompt: 'Show activity', expected_output: 'Render an activity card', assertions: ['kpass activity', '--output json', '━━━'] }];
const capture = (cases = small) => ({
  schemaVersion: 1, suiteSha256: suiteDigest(cases), kind: 'synthetic',
  producer: 'runner contract test, not a live agent',
  records: cases.map(({ id, assertions }) => ({ id, response: assertions.join('\n') })),
});

test('request includes every real suite prompt without leaking grading answers', () => {
  const request = captureRequest(suite);
  assert.equal(request.cases.length, suite.length);
  assert.ok(suite.length >= 138);
  assert.deepEqual(Object.keys(request.cases[0]), ['id', 'prompt']);
  assert.equal(request.suiteSha256, suiteDigest(suite));
});

test('canonical hash ignores whitespace and key ordering, but binds all grading fields', () => {
  const reordered = small.map(({ assertions, expected_output, prompt, id }) => ({ assertions, expected_output, prompt, id }));
  assert.equal(suiteDigest(reordered), suiteDigest(small));
  for (const field of ['prompt', 'expected_output', 'assertions']) {
    const changed = structuredClone(small);
    if (field === 'assertions') changed[0].assertions.push('new marker');
    else changed[0][field] += ' new';
    assert.notEqual(suiteDigest(changed), suiteDigest(small));
    assert.throws(() => replay(changed, capture()), /does not match/);
  }
});

test('all real-suite cases are graded in suite order, not capture order', () => {
  const input = capture(suite);
  input.records.reverse();
  const report = replay(suite, input);
  assert.equal(report.summary.literalPassed, suite.length);
  assert.equal(report.summary.matchedAssertions, suite.reduce((n, item) => n + item.assertions.length, 0));
  assert.deepEqual(report.cases.map((item) => item.id), suite.map((item) => item.id));
  assert.ok(report.cases.every((item) => item.semanticReview === 'required'));
  assert.match(markdown(report), /Synthetic test data/);
});

test('known missing --output json failure is stable, with exact unmatched assertion', () => {
  const input = capture(suite);
  input.records.find((item) => item.id === 1).response = 'kpass activity\n━━━';
  const first = replay(suite, input);
  assert.deepEqual(replay(suite, input), first);
  assert.equal(first.summary.literalPassed, suite.length - 1);
  assert.deepEqual(first.cases[0].assertions.filter((a) => !a.passed), [{ literal: '--output json', passed: false, offset: -1 }]);
  assert.match(junit(first), /failures="1"/);
});

test('missing, empty and execution-error captures never disappear from the denominator', () => {
  const input = capture(suite);
  input.records = input.records.filter((item) => item.id !== 1);
  input.records.find((item) => item.id === 2).response = '';
  input.records[input.records.findIndex((item) => item.id === 3)] = { id: 3, error: 'private backend error' };
  const report = replay(suite, input);
  assert.equal(report.summary.total, suite.length);
  assert.equal(report.summary.missing, 1);
  assert.equal(report.summary.errors, 1);
  assert.equal(report.summary.literalPassed, suite.length - 3);
  assert.equal(report.cases[0].status, 'missing');
  assert.equal(report.cases[2].status, 'error');
  assert.ok(!JSON.stringify(report).includes('private backend error'));
  assert.match(junit(report), /type="missing"/);
  assert.match(junit(report), /type="error"/);
});

test('literal matching is case sensitive and reports UTF-16 offsets', () => {
  const input = capture();
  input.records[0].response = '😀 KPASS activity --output json ━━━';
  const report = replay(small, input);
  assert.equal(report.cases[0].assertions[0].passed, false);
  assert.equal(report.cases[0].assertions[1].offset, input.records[0].response.indexOf('--output json'));
});

test('even an answer-key echo is only a literal pass, never semantic approval', () => {
  const input = capture();
  input.kind = 'recorded';
  const report = replay(small, input);
  assert.equal(report.summary.literalPassed, 1);
  assert.equal(report.summary.semanticReviewRequired, 1);
  assert.match(markdown(report), /All expected behaviors still require semantic review/);
  assert.ok(!markdown(report).includes('Synthetic test data'));
});

test('reject invalid suites, duplicates and empty assertions', () => {
  for (const value of [null, {}, [], [null], [...small, ...small],
    [{ ...small[0], id: '1' }], [{ ...small[0], id: 0 }],
    [{ ...small[0], prompt: ' ' }], [{ ...small[0], expected_output: null }],
    [{ ...small[0], assertions: [] }], [{ ...small[0], assertions: [''] }],
    [{ ...small[0], assertions: [3] }]]) assert.throws(() => validateSuite(value));
});

test('reject malformed capture contracts instead of silently accepting partial data', () => {
  for (const patch of [{ schemaVersion: 2 }, { suiteSha256: 'wrong' }, { kind: 'unknown' },
    { producer: '' }, { records: {} }, { records: [null] },
    { records: [{ id: 999, response: '' }] },
    { records: [...capture().records, ...capture().records] },
    { records: [{ id: 1 }] }, { records: [{ id: 1, response: 2 }] },
    { records: [{ id: 1, error: '' }] }, { records: [{ id: 1, response: '', error: 'failure' }] }]) {
    assert.throws(() => replay(small, { ...capture(), ...patch }));
  }
  assert.throws(() => replay(small, null));
});

test('reports escape markup, omit raw responses and retain valid Unicode', () => {
  const special = [{ ...small[0], assertions: ['<tag a="x">&\'|`\u0001😀'] }];
  const input = capture(special);
  input.records[0].response += '\nprivate-wallet-secret';
  input.producer = '<script>alert(1)</script> | producer';
  const report = replay(special, input);
  const output = junit(report);
  assert.match(output, /&lt;tag a=&quot;x&quot;&gt;&amp;&apos;/);
  assert.ok(!output.includes('\u0001'));
  assert.ok(output.includes('😀'));
  assert.ok(!markdown(report).includes('<script>'));
  assert.ok(!JSON.stringify(report).includes('private-wallet-secret'));
  assert.match(markdown(report), /&#124;/);
});

const cli = resolve('scripts/replay-evals.mjs');
const run = (args, cwd) => spawnSync(process.execPath, [cli, ...args], { cwd, encoding: 'utf8' });

test('CLI generates full-suite reports, reproduces failures, and distinguishes input errors', async (t) => {
  const dir = await mkdtemp(join(tmpdir(), 'passport-replay-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const inputPath = join(dir, 'capture.json');
  const requestPath = join(dir, 'request.json');
  // The default suite must resolve relative to the script, not the caller's cwd.
  assert.equal(run(['--request', requestPath], dir).status, 0);
  assert.equal(JSON.parse(await readFile(requestPath)).cases.length, suite.length);
  assert.equal(run(['--request', requestPath], dir).status, 2);
  await writeFile(inputPath, JSON.stringify(capture(suite)));
  const passDir = join(dir, 'pass');
  assert.equal(run(['--capture', inputPath, '--out', passDir], dir).status, 0);
  const report = JSON.parse(await readFile(join(passDir, 'report.json')));
  assert.equal(report.summary.literalPassed, suite.length);
  assert.match(await readFile(join(passDir, 'junit.xml'), 'utf8'), /failures="0" errors="0"/);
  const failing = capture(suite);
  failing.records[0].response = 'kpass activity ━━━';
  await writeFile(inputPath, JSON.stringify(failing));
  assert.equal(run(['--capture', inputPath, '--out', join(dir, 'fail')], dir).status, 1);
  // A reused output path must not silently expose the previous green run.
  assert.equal(run(['--capture', inputPath, '--out', passDir], dir).status, 2);
  await writeFile(inputPath, '{bad json');
  assert.equal(run(['--capture', inputPath, '--out', join(dir, 'bad')], dir).status, 2);
  for (const args of [[], ['--unknown', 'x'], ['--capture'], ['--capture', '--out'],
    ['--request', 'a', '--request', 'b'], ['--request', 'a', '--out', 'b'],
    ['--capture', 'missing', '--out', 'b']]) assert.equal(run(args, dir).status, 2);
  assert.equal(run(['--help'], dir).status, 0);
});

test('CLI supports a custom suite and reports missing captures as failure', async (t) => {
  const dir = await mkdtemp(join(tmpdir(), 'passport-replay-custom-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  await writeFile(join(dir, 'suite.json'), JSON.stringify(small));
  await writeFile(join(dir, 'capture.json'), JSON.stringify({ ...capture(), records: [] }));
  const result = run(['--suite', 'suite.json', '--capture', 'capture.json', '--out', 'report'], dir);
  assert.equal(result.status, 1);
  assert.equal(JSON.parse(await readFile(join(dir, 'report/report.json'))).summary.missing, 1);
});
