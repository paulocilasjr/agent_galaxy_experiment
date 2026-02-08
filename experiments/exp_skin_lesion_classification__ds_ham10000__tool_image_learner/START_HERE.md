# START_HERE: HAM10000 + Image Learner

## What This Is
- Isolated experiment scaffold for HAM10000 using Image Learner.
- Intended as the clean starting point for new runs.

## Primary Navigation
1. `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/REPRODUCE.md`
2. `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/summaries/run_index.tsv`
3. `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/journal.md`

## Step 0: Confirm Dataset Mapping
Open and finalize:
- `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/datasets/manifest.tsv`

Required aliases in the manifest:
- `ham10000_selected_metadata_aug_v1` (local metadata CSV)
- `ham10000_selected_images_96_zip_v1` (Zenodo ZIP URL for Galaxy upload)

## Step 1: Create a New Run
```bash
sh scripts/init_run.sh exp_skin_lesion_classification__ds_ham10000__tool_image_learner baseline ham10000_selected_metadata_aug_v1
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

## Step 2a: Upload Source ZIP To Galaxy
Use dataset alias `ham10000_selected_images_96_zip_v1` from the dataset manifest:
- `https://zenodo.org/records/18284218/files/selected_HAM10000_img_96_size.zip`

## Step 3: Reproducibility Rule
- Record every prompt/action/error/fix in `$RUN_ROOT/journal.md`.
- Store exact request payloads in `$RUN_ROOT/configs/`.
- Never mix files across experiments.
