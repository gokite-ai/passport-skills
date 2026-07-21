# Evals — Skills Regression Harness

Ported from the `spring-test` branch as a behavioral safety net for the skills-optimization work. Treat this as a regression target: any structural change to a `SKILL.md` should be verified to not regress the `main` baseline captured in `functional-workspace/iteration-3/`.

## Layout

- `evals.json` — master eval definitions (55 scenarios, each with prompt + assertion strings).
- `functional-workspace/iteration-3/` — graded transcripts captured by dispatching subagents against two skill versions: `main/` and `spring-test/`. Each `eval-*/` directory holds an `eval_metadata.json` plus `<version>/outputs/response.md`.
- `functional-workspace/iteration-3/grade_all.py` — re-grades every response.md against its assertions and writes per-version `grading.json`.
- `functional-workspace/iteration-3/build_benchmark.py` — aggregates grading.json files into `grading_summary.json` (means, wins/ties/losses, `losses[]` queue for follow-up).
- `routing-experiments/FINDINGS.md` — earlier routing audit; documents harness limitations (slash-command stubs never trigger `Skill()` calls) and the `settings.local.json` permissions gap. Read before designing new evals.

## Baseline at port time (main @ 87ff269 vs spring-test @ 60432e0)

```
main avg:        0.971
spring-test avg: 0.984
spring-test wins: 3 | ties: 56 | losses: 0
```

Re-run anytime via:
```bash
python3 evals/functional-workspace/iteration-3/grade_all.py
python3 evals/functional-workspace/iteration-3/build_benchmark.py
```

## Adding a new comparison

When restructuring a SKILL.md on main (e.g. progressive-disclosure split), follow the workflow described in `functional-workspace/iteration-3/RUNBOOK.md`:

1. Dispatch a subagent against the restructured skill for each eval, saving the transcript to `iteration-3/eval-*/<new-version>/outputs/response.md`.
2. Extend `CONFIGS` in `grade_all.py` to include the new version directory name.
3. Re-run grade + benchmark; check `grading_summary.json.losses[]` is empty.

## Out of scope here

- No automated runner script exists in this directory — response.md files are produced by an orchestrating Claude session via subagent dispatch (see RUNBOOK). The graders work on whatever response.md files happen to be present.
- `trigger-evals/` from spring-test is intentionally not ported: per FINDINGS.md, the harness can't actually exercise `Skill()` routing.
