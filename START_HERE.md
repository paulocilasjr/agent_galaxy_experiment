# Start Here

This repository is organized by experiment-dataset-tool.

Primary catalog:
- `experiments/README.md`
- quick CLI listing: `sh scripts/list_use_cases.sh`

Pick one use case and open its `START_HERE.md`:

1. Chowell + Tabular Learner (completed 4-run adjustment sequence)  
   `experiments/exp_immunotherapy_chowell_tabular_learner/START_HERE.md`  
   reproducibility map: `experiments/exp_immunotherapy_chowell_tabular_learner/REPRODUCE.md`
2. HAM10000 + Image Learner (new experiment scaffold)  
   `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/START_HERE.md`  
   reproducibility map: `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/REPRODUCE.md`

Before running anything:
- Copy `.env.example` to `.env` and set `GALAXY_URL` / `GALAXY_API_KEY`.
- Read `docs/EXPERIMENT_ORGANIZATION.md` once for conventions.
