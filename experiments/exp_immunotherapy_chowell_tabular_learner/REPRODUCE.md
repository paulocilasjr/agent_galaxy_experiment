# Reproduce: Chowell + Tabular Learner

## Use Case Scope

- dataset: Chowell train/test TSV
- tool: Galaxy Tabular Learner
- outcome: 4-run tuning sequence with corrections

## Read Order

1. `experiments/exp_immunotherapy_chowell_tabular_learner/START_HERE.md`
2. `experiments/exp_immunotherapy_chowell_tabular_learner/datasets/manifest.tsv`
3. `experiments/exp_immunotherapy_chowell_tabular_learner/summaries/run_index.tsv`
4. `experiments/exp_immunotherapy_chowell_tabular_learner/runs/run_20260207_121552_legacy/journal.md`
5. `artifacts/immunotherapy_20260207_121552/configs/`

## Where The Run Artifacts Are

- This completed run was executed before strict run-scoped storage.
- Canonical historical location:
  - `artifacts/immunotherapy_20260207_121552/`
- Experiment-scoped compatibility wrapper:
  - `experiments/exp_immunotherapy_chowell_tabular_learner/runs/run_20260207_121552_legacy/`

## Re-run Starting Point

- payloads:
  - `artifacts/immunotherapy_20260207_121552/configs/tabular_learner_request.json`
  - `artifacts/immunotherapy_20260207_121552/configs/tabular_learner_request_rerun_with_test_dataset.json`
  - `artifacts/immunotherapy_20260207_121552/configs/tabular_learner_request_custom_prob_025.json`
- command pattern:
  - `curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" -d @<payload.json> "$GALAXY_URL/api/tools"`
