# agent_galaxy_experiment
Running galaxy experiment using agent

## Quick Entrypoint
Open `START_HERE.md` and choose a use case.
For experiment-level navigation, use `experiments/README.md`.

## Recommended Organization
Use experiment-scoped folders to avoid mixing datasets/tools/runs:

```text
experiments/<experiment_id>/runs/<run_id>/...
```

Quick start:

```bash
sh scripts/init_experiment_dataset.sh immunotherapy_response chowell tabular_learner "Immunotherapy response prediction using Tabular Learner"
sh scripts/init_run.sh exp_immunotherapy_response__ds_chowell__tool_tabular_learner baseline chowell_v1
```

Next experiment example (Image Learner):

```bash
sh scripts/init_experiment_dataset.sh histopathology_response tcga_tiles image_learner "Image Learner experiment for response prediction from tiles"
sh scripts/init_run.sh exp_histopathology_response__ds_tcga_tiles__tool_image_learner baseline tcga_tiles_v1
```

Details:
- `docs/EXPERIMENT_ORGANIZATION.md`

## Tracked Use Cases
- `exp_immunotherapy_chowell_tabular_learner` (Tabular Learner)
- `exp_skin_lesion_classification__ds_ham10000__tool_image_learner` (Image Learner)
- `exp_multimodal_dataset__ds_hancock_tma__tool_multimodal` (Multimodal setup)
