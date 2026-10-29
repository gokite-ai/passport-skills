// Produce reproducible synthetic evidence of the tool's pass/failure paths only.
import { readFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { replay, suiteDigest, main } from '../../scripts/replay-evals.mjs';
import { writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const suite = JSON.parse(await readFile(new URL('../../evals/evals.json', import.meta.url), 'utf8'));
const dir = resolve('tmp/replay-evidence');
await mkdir(dir, { recursive: true });
for (const variant of ['all-markers', 'missing-json-flag']) {
  const capture = {
    schemaVersion: 1, suiteSha256: suiteDigest(suite), kind: 'synthetic',
    producer: 'deterministic replay contract fixture; not a live agent evaluation',
    records: suite.map(({ id, assertions }) => ({ id, response: assertions.join('\n') })),
  };
  if (variant === 'missing-json-flag') capture.records.find((item) => item.id === 1).response = 'kpass activity\n━━━';
  const capturePath = resolve(dir, `${variant}.json`);
  await writeFile(capturePath, JSON.stringify(capture, null, 2) + '\n');
  const code = await main(['--capture', capturePath, '--out', resolve(dir, variant)]);
  assert.equal(code, variant === 'all-markers' ? 0 : 1);
  assert.equal(replay(suite, capture).summary.literalPassed, suite.length - (code === 1 ? 1 : 0));
}
