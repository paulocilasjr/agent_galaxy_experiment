# Reproduce: Built_ML_workflow

1. Ensure `.env` has `GALAXY_URL` and `GALAXY_API_KEY`.
2. Run input setup:
   - `sh experiments/Built_ML_workflow/runs/run_20260218_202848Z_hyperparam_search/commands/01_create_history_and_upload_inputs.sh`
3. Run hyperparameter-search pipeline + workflow extraction:
   - `sh experiments/Built_ML_workflow/runs/run_20260218_202848Z_hyperparam_search/commands/02_build_pipeline_with_hyperparam_search.sh`
4. Review outputs in:
   - `experiments/Built_ML_workflow/runs/run_20260218_202848Z_hyperparam_search/outputs/`
