# Reproduce: HAM10000 + Image Learner

## Use Case Scope

- dataset: HAM10000 metadata CSV + image ZIP
- tool: Galaxy Image Learner
- objective: multi-class prediction of `dx` using leakage-safe split by `lesion_id`

## Read Order

1. `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/START_HERE.md`
2. `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/datasets/manifest.tsv`
3. `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/summaries/run_index.tsv`
4. `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/journal.md`
5. `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/configs/`

## Current Canonical Run

- run id: `run_20260208_051553Z_setup`
- run root:
  - `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/`

## Key Reproducibility Files

- active manifest:
  - `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/run_manifest.yaml`
- run timeline:
  - `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/journal.md`
- final active request payload:
  - `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/configs/04c_image_learner_request_flattened_conditionals.json`

## Notes On Attempts

- this run includes multiple attempts with error/fix history
- attempt summary:
  - `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/metadata/image_learner_attempts_summary.json`
