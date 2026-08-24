# Implementation Plan: Agent Loops for Building a New Mobile App

**Models:** Kimi K3 (planner / generator / visual evaluator) + GLM-5.2 (code evaluator)
**Method:** Karpathy `loops.md` harness design + scheduled loops from the Hanako article
**Status:** Draft for review

Guiding rules, condensed from the two sources:

- Write the loop, not the prompt. The loop is: gather, reason, act, verify, repeat.
- Separate roles: planner, generator, evaluator. A model never grades its own work.
- Negotiate a testable contract before any code is written.
- State lives on disk, never in context. Three files should be enough to resume after a crash.
- Let failed runs restart from disk state instead of patching forever.
- Keep traces of everything; debug by reading transcripts, not by re-prompting by vibe.
- Start with one loop. Add loops only after the previous one earns trust.
- Human approves the risky 5% (merges to main, first runs, store submissions); agents do the boring 95%.
- Re-audit the harness on every model upgrade and delete what the model now does for free.
- The bottleneck always moves; the loop's job is to make the next one visible.

---

## Role assignment

| Role | Model | Why |
|-|-|-|
| Planner | Kimi K3 | Long-horizon reasoning, 1M context holds the whole spec + repo |
| Generator | Kimi K3 | Tuned for long-horizon coding sessions |
| Code evaluator | GLM-5.2 | Different model family (kills self-grading sycophancy), ~1/6 the cost, runs every iteration |
| Visual evaluator | Kimi K3 | Native vision for screenshot review against the taste rubric |

---

## Phase 0 — Scaffold the state layer (manual, ~30 min)

Empty git repo plus:

```
SPEC.md                 # one paragraph: what the app is, who it is for, platforms
contract.md             # negotiated checklist of testable assertions (starts empty)
feature_list.json       # machine-readable queue: id, desc, status, test
progress.md             # what is done, what is next, current blockers
log.md                  # append-only: ## [YYYY-MM-DD] op | title
rubric.md               # taste rubric: design / originality / craft / functionality, weighted,
                        # calibrated against 3 good reference apps + 3 slop examples
prompts/planner.md
prompts/generator.md
prompts/evaluator.md
traces/                 # raw session transcripts, one file per run
loop.sh                 # the build while-loop
eval.sh                 # the evaluation pass
```

Mobile stack decision made here (React Native/Expo vs native) — it determines the test tooling in Phase 4. Default recommendation: React Native + Maestro.

Human reviews `SPEC.md` and `rubric.md` before anything runs. These two files are the boundary everything else respects.

## Phase 1 — Plan (one shot, Kimi K3)

Run the planner once:

- Turns `SPEC.md` into a sprint spec.
- Populates `feature_list.json` with ~15–30 small, independently testable features, each with a machine-checkable test description.
- Seeds `progress.md` and `log.md`.

Human reviews and edits the feature list before proceeding. This is the last fully manual gate until merge.

## Phase 2 — Contract negotiation (2–3 rounds, K3 vs GLM-5.2)

- Generator (K3) proposes in `contract.md` what "done" looks like per feature.
- Evaluator (GLM-5.2, separate session, system prompt: *the code is broken, your job is to prove it*) pushes back: vague criteria get rejected, missing edge cases added.
- They argue via `contract.md` on disk until it holds ~20–30 testable assertions. Ten is too few (evaluator rubber-stamps); aim for assertions that are mechanical, not judgment calls.
- Human arbitrates deadlocks only.

Target contract shape for mobile:

1. App builds for target platform(s), zero warnings on lint/typecheck.
2. Unit/component tests green (Jest/Vitest or XCTest/Espresso).
3. Maestro flows pass on a clean simulator (one YAML flow per core user journey).
4. Screenshot review passes the rubric threshold.

## Phase 3 — The build loop (inner while-loop)

`loop.sh`:

```bash
#!/bin/bash
while ! grep -qx "DONE" progress.md; do
  ts=$(date +%Y%m%d-%H%M%S)
  kimi -p "$(cat prompts/generator.md)" > "traces/${ts}-generator.log" 2>&1
  sleep 10
done
```

The generator prompt enforces, every iteration:

1. Read `feature_list.json`, `progress.md`, `contract.md` first — nothing else is trusted memory.
2. Pick the single next unfinished feature.
3. Boot/reset the simulator to a clean state.
4. Implement it. Run build + unit tests + the relevant Maestro flow. Fix what broke.
5. Update `feature_list.json` and `progress.md`; append to `log.md`; commit with a clear message.
6. If every feature in `feature_list.json` passes the contract, write `DONE` as the last line of `progress.md` and stop.

Restart policy (§V): if a run goes sideways (repeated failing tests, patch-on-patch churn visible in the trace), the next iteration deletes the feature's changes and rebuilds from the state files rather than patching. Do not interrupt restarts — that is the loop working correctly. Interrupt only when the *contract itself* is wrong.

## Phase 4 — The evaluation loop (GLM-5.2 + K3 vision)

Runs after each build iteration, or on a cron interval (e.g. every 30 min during overnight runs):

- **Code evaluation (GLM-5.2):** reads `contract.md`, runs the build, unit tests, and every Maestro flow on a clean simulator. Appends pass/fail per assertion to `log.md`, writes failures to `progress.md` as blockers for the generator.
- **Visual evaluation (Kimi K3):** captures a screenshot per screen, reviews against `rubric.md`, outputs a 0–1 score plus a paragraph explaining the gap. Appends to `log.md`.
- Loop until all contract assertions pass and the rubric score crosses the threshold set in Phase 0.

Evaluation tooling note: Maestro flows are YAML and agent-writable — the evaluator may add flows for new features, but additions to `contract.md` assertions still require the negotiation in Phase 2, not unilateral edits.

## Phase 5 — Outer loops (only after Phases 3–4 are trusted)

Add one at a time, each boring, bounded, and verifiable at a glance:

1. **CI watcher** (every few minutes): fix failing CI on open branches.
2. **Flaky-test patcher** (nightly): quarantine and repair flaky Maestro flows/unit tests.
3. **Digest** (nightly): summarize `log.md` into a morning report.
4. Later: feedback clusterer once the app has users.

Each loop gets a narrow written job in its own prompt file. "Improve the codebase" is a wish, not a loop.

## Phase 6 — Move off the laptop

Once the build/eval loops run unattended locally, move them to a server (cron or CI schedules, webhook triggers) so they survive the laptop closing. Human gates that remain regardless of where loops run:

- Merge to `main`.
- First run of any new loop.
- Anything touching signing keys, store submissions, or production data.

---

## Standing operational rules

**Traces (§VII).** Every run writes its raw transcript to `traces/`. When output diverges from expectation, grep the trace for the exact moment judgment went wrong, fix the prompt at that point, rerun. `log.md` is the agent's memory; traces are yours. Never tune by vibe.

**Harness audits (§VIII).** Every piece of scaffolding is tagged with the model limitation it compensates for. On each model upgrade (K3.x, GLM-5.3, …), re-test each assumption by removing the workaround and watching traces; delete what the model now does for free. Known candidate already: aggressive context chunking/summarization, given both models' 1M-token windows. A harness that only grows is a harness nobody is reading.

**Bottleneck checks (§IX).** After every improvement, ask: what is the slowest or most failure-prone stage now? Instrument it, fix it, ship a smaller harness, repeat. Coding → planning → verification → taste is the expected progression. If everything feels smooth, the bottleneck is somewhere you are not measuring.

## Open questions to resolve before starting

- [ ] App stack: React Native/Expo + Maestro (recommended) vs native?
- [ ] Which agent CLI invokes GLM-5.2 headlessly, and via which provider? (Kimi Code custom provider in `config.toml`, or a second CLI?)
- [ ] Where do overnight runs live: this Mac first, or straight to a server?
- [ ] Rubric threshold score and the 3 good / 3 slop reference apps.
- [ ] What counts as "risky 5%" for this project beyond merges and signing?
