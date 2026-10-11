import process from "node:process";
import { readFile } from "node:fs/promises";

let prompt = "";
for await (const chunk of process.stdin) {
  prompt += chunk;
}

const mode = process.argv[2] ?? "echo";

if (mode === "echo") {
  process.stdout.write(prompt);
} else if (mode === "fail") {
  process.stderr.write("fixture failure\n");
  process.exitCode = 7;
} else if (mode === "hang") {
  setTimeout(() => process.stdout.write("too late"), 10_000);
} else if (mode === "echo-id") {
  process.stdout.write(`eval-${process.env.EVAL_ID}`);
} else if (mode === "assertions-file") {
  const evals = JSON.parse(await readFile(process.argv[3], "utf8"));
  const evalCase = evals.find(({ id }) => String(id) === process.env.EVAL_ID);
  process.stdout.write(evalCase.assertions.join("\n"));
} else if (mode === "miss-last") {
  process.stdout.write("alpha");
} else {
  process.stderr.write(`unknown fixture mode: ${mode}\n`);
  process.exitCode = 2;
}
