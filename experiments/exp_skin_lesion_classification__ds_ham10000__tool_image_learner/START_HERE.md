# START_HERE: HAM10000 + Image Learner

## What This Is
- Isolated experiment scaffold for HAM10000 using Image Learner.
- Intended as the clean starting point for new runs.

## Step 0: Confirm Dataset Mapping
Open and finalize:
- `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/datasets/manifest.tsv`

Replace placeholders with exact source locations/paths used in your environment.

## Step 1: Create a New Run
```bash
sh scripts/init_run.sh exp_skin_lesion_classification__ds_ham10000__tool_image_learner baseline ham10000_v1
```

Then set:
```bash
export EXPERIMENT_ID="exp_skin_lesion_classification__ds_ham10000__tool_image_learner"
export RUN_ID="$(cat "experiments/$EXPERIMENT_ID/latest_run_id.txt")"
export RUN_ROOT="experiments/$EXPERIMENT_ID/runs/$RUN_ID"
```

## Step 2: Log Everything Under RUN_ROOT
Required folders/files are already scaffolded:
- `$RUN_ROOT/run_manifest.yaml`
- `$RUN_ROOT/journal.md`
- `$RUN_ROOT/configs/`
- `$RUN_ROOT/prompts/`
- `$RUN_ROOT/commands/`
- `$RUN_ROOT/api/`
- `$RUN_ROOT/outputs/`

## Step 3: Reproducibility Rule
- Record every prompt/action/error/fix in `$RUN_ROOT/journal.md`.
- Store exact request payloads in `$RUN_ROOT/configs/`.
- Never mix files across experiments.
