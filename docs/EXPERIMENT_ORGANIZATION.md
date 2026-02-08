# Experiment Organization

## Goal
Keep multiple datasets, tools, and parameter configurations in one repository without ambiguity about ownership of files.

## Canonical Layout

```text
experiments/
  index.tsv
  <experiment_id>/
    experiment.yaml
    latest_run_id.txt
    datasets/
      manifest.tsv
    configs/
    references/
    README.md
    runs/
      <run_id>/
        run_manifest.yaml
        journal.md
        commands/
        prompts/
        configs/
        metadata/
        api/
        outputs/
    summaries/
      run_index.tsv
```

## Naming Rules
- `experiment_id`: stable slug that explicitly includes objective + dataset + tool.
- `run_id`: unique execution instance for one parameterized run.
- Recommended `experiment_id` format:
  - `exp_<objective_slug>__ds_<dataset_slug>__tool_<tool_slug>`
- Examples:
  - `exp_immunotherapy_response__ds_chowell__tool_tabular_learner`
  - `exp_histopathology_response__ds_tcga_tiles__tool_image_learner`
  - `run_id`: `run_20260208_045000Z_default`

## Ownership Rule
- Everything inside `experiments/<experiment_id>/runs/<run_id>/` belongs to exactly one run.
- Never write run artifacts outside the run directory.
- Cross-run artifacts go to:
  - `experiments/<experiment_id>/summaries/`

## Required Metadata

### `experiment.yaml`
- experiment identity and immutable context:
  - objective
  - primary tool
  - dataset name
  - owner
  - creation timestamp

### `datasets/manifest.tsv`
- dataset inventory per experiment:
  - dataset alias
  - source type (`url`, `local`, `galaxy_hda`, etc.)
  - source location/id
  - notes

### `run_manifest.yaml`
- run identity and mutable execution details:
  - status (`in_progress`, `completed`, `failed`)
  - exact tool version
  - exact parameter payload path
  - dataset IDs / job IDs / output IDs

### `journal.md`
- linear timeline:
  - prompts
  - actions
  - errors
  - fixes
  - outcomes

## Suggested Workflow
1. Initialize experiment (recommended helper):  
   `scripts/init_experiment_dataset.sh <objective_slug> <dataset_slug> <tool_slug> [objective_text]`
2. Start each run:  
   `scripts/init_run.sh <experiment_id> [run_label] [dataset_alias]`
3. Write all artifacts under the new run directory.
4. Update run manifest status when done.
5. Maintain `START_HERE.md` inside each experiment folder as the human entrypoint.

Example for your next use case:

```bash
sh scripts/init_experiment_dataset.sh histopathology_response tcga_tiles image_learner "Image Learner experiment for response prediction from tiles"
sh scripts/init_run.sh exp_histopathology_response__ds_tcga_tiles__tool_image_learner baseline tcga_tiles_v1
```

## Why This Avoids Confusion
- Separation by experiment first, then by run.
- Single source of truth for current run: `latest_run_id.txt`.
- Fast inventory:
  - global: `experiments/index.tsv`
  - per experiment: `summaries/run_index.tsv`
