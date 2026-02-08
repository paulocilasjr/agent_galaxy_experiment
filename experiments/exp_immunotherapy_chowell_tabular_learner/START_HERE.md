# START_HERE: Chowell + Tabular Learner

## What This Contains
- Completed reproduction trail for the Chowell dataset using Tabular Learner.
- Four runs showing configuration adjustments and final corrected setup.

## Primary Navigation
1. `experiments/exp_immunotherapy_chowell_tabular_learner/REPRODUCE.md`
2. `experiments/exp_immunotherapy_chowell_tabular_learner/runs/run_20260207_121552_legacy/run_manifest.yaml`
3. `experiments/exp_immunotherapy_chowell_tabular_learner/runs/run_20260207_121552_legacy/journal.md`

## Read In This Order
1. `experiments/exp_immunotherapy_chowell_tabular_learner/README.md`
2. `experiments/exp_immunotherapy_chowell_tabular_learner/datasets/manifest.tsv`
3. `experiments/exp_immunotherapy_chowell_tabular_learner/runs/run_20260207_121552_legacy/journal.md`
4. `artifacts/immunotherapy_20260207_121552/journal.md`
5. `artifacts/immunotherapy_20260207_121552/prompts/`
6. `artifacts/immunotherapy_20260207_121552/configs/`
7. `artifacts/immunotherapy_20260207_121552/metadata/`

## Key Run Result Files
- Run 1 summary: `artifacts/immunotherapy_20260207_121552/metadata/05_execution_result.json`
- Run 2 evidence: `artifacts/immunotherapy_20260207_121552/api/05b_job_details_full_poll_1.json`
- Run 3 summary: `artifacts/immunotherapy_20260207_121552/metadata/05c_execution_result.json`
- Run 4 summary (custom probability threshold): `artifacts/immunotherapy_20260207_121552/metadata/05d_execution_result.json`

## Re-run Starting Point
- Canonical payload to execute now:
  - `artifacts/immunotherapy_20260207_121552/configs/tabular_learner_request.json`
- Command pattern:
  - `curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" -d @<payload> "$GALAXY_URL/api/tools"`
