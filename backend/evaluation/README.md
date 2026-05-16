# Evaluation Toolkit

This folder contains repeatable scripts to produce measurable accuracy reports.

## 1) Intent Benchmark

Evaluates intent classification (`reminder/note/expense/query/other`) using:

- `ai/training/data/training_data.json` (canonical dataset)
- sampled holdout split
- either live LLM inference or local heuristic fallback

Run from project root:

```bash
python backend/evaluation/evaluate_intent.py --sample-size 400 --holdout-ratio 0.2
```

Recommended final claim run (live LLM, no mock mode):

```bash
python backend/evaluation/evaluate_intent.py \
	--use-llm \
	--sample-size 400 \
	--holdout-ratio 0.2 \
	--target-accuracy 0.90 \
	--enforce-claim-gate
```

Options:

- `--use-llm` enables live API inference through `detect_intent_gpt`.
- `--mock-mode` forces deterministic mock mode (for CI/demo, not real quality claims).
- `--target-accuracy` sets the minimum accuracy threshold for claim proof.
- `--enforce-claim-gate` exits non-zero if the live run does not meet target.

Output:

- `backend/evaluation/results/intent_eval_*.json`
- `backend/evaluation/results/intent_eval_*.md`

JSON includes `claim_verdict` with `status=proven|not_proven` and reason.
Only live LLM runs (`--use-llm` and not mock mode) can prove the claim.

## 2) Expense Proxy Benchmark

Uses weak labels derived from text patterns in expense examples and compares extraction outputs.
This is a **proxy metric** only when no curated expense-ground-truth dataset exists.

```bash
python backend/evaluation/evaluate_expense_proxy.py --sample-size 300
```

Output:

- `backend/evaluation/results/expense_proxy_eval_*.json`

## 3) Final Report

Use:

- `backend/evaluation/report_template.md`

Fill with the generated JSON metrics and include screenshots/logs in your FYP appendix.

For a defensible final submission, attach both JSON + MD artifacts from the same live run timestamp.

## 4) Live Integration and Stress Test Coverage

These tests are opt-in so normal CI remains stable and low-cost.

Live external integration tests (real provider path):

```bash
RUN_LIVE_INTEGRATION_TESTS=true pytest backend/tests/test_live_external_integration_opt_in.py -q
```

Stress/concurrency behavior tests:

```bash
RUN_STRESS_TESTS=true pytest backend/tests/test_stress_behavior_opt_in.py -q
```

Notes:

- `test_live_external_integration_opt_in.py` requires a valid `OPENAI_API_KEY`.
- Keep these tests out of default CI and run before milestone/final releases.

