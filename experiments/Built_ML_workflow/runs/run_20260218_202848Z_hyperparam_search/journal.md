# Run Journal: run_20260218_202848Z_hyperparam_search

## Context
- experiment_id: `Built_ML_workflow`
- run_id: `run_20260218_202848Z_hyperparam_search`
- created_utc: `2026-02-18T20:28:48Z`
- objective: Modify the Pipeline Builder chain to add hyperparameter search on `Chowell_train_Response.tsv`, then generate confusion matrices with the tuned model for Chowell and MSK1 test cohorts.

## Timeline
### 2026-02-18T20:28:48Z - Run scaffold created
- Action:
  - Created run folder `experiments/Built_ML_workflow/runs/run_20260218_202848Z_hyperparam_search` with `commands`, `prompts`, `configs`, `metadata`, `api`, `outputs`.
  - Added reproducibility scripts and prompt captures for hyperparameter-search workflow.

### 2026-02-18T20:29Z - Galaxy history + upload
- Action:
  - Created Galaxy history `ML_workflow_hyperparam` (`history_id: bbd44e69cb8906b5d9ad8dc22de96251`).
  - Uploaded five TSV files via `/api/tools/fetch`.
- Outcome:
  - All five input datasets reached `ok` state.
  - Input shapes:
    - `Chowell_train_Response.tsv`: 964 x 22
    - `Chowell_test_Response.tsv`: 515 x 22
    - `MSK1_Response.tsv`: 453 x 22
    - `Chowell_test_No_Response.tsv`: 515 x 21
    - `MSK1_No_Response.tsv`: 453 x 21

### 2026-02-18T20:30Z - Hyperparameter-search pipeline execution
- Tool chain executed:
  1. `Pipeline Builder` (`sklearn_build_pipeline`)
  2. `SearchCV` (`sklearn_searchcv`) on `Chowell_train_Response.tsv`
  3. `Model Prediction` on Chowell test features
  4. `Model Prediction` on MSK1 test features
  5. `Plot confusion matrix, precision, recall and ROC and AUC curves` for Chowell
  6. `Plot confusion matrix, precision, recall and ROC and AUC curves` for MSK1
- Search grid configured:
  - `C`: `[0.01, 0.1, 1.0, 10.0, 100.0]`
  - `max_iter`: `[1000, 2000, 4000]`
- Outcome:
  - SearchCV completed successfully and produced:
    - CV results dataset: `f9cad7b01a472135de8db279fff6c3b5`
    - Tuned model dataset: `f9cad7b01a47213569ef53bc0ee1582b`
  - Predictions and confusion matrix plots for both cohorts completed successfully.

### 2026-02-18T20:33Z - Workflow extraction and downloads
- Action:
  - Extracted executed chain into workflow using explicit job IDs.
  - New workflow id: `10eaad6bb1a3bb64`
  - Downloaded workflow JSON and output artifacts locally.
- Downloaded key outputs:
  - `confusion_matrix_chowell_test_hyperparam.png`
  - `confusion_matrix_msk1_test_hyperparam.png`
  - `predictions_chowell_test_hyperparam.tsv`
  - `predictions_msk1_test_hyperparam.tsv`

## Result Summary
- Hyperparameter-search variant completed end-to-end.
- Confusion matrix counts from tuned model predictions:
  - Chowell test (`n=515`): TP=34, TN=378, FP=10, FN=93, accuracy=0.800000
  - MSK1 test (`n=453`): TP=24, TN=306, FP=31, FN=92, accuracy=0.728477

## Key Files
- `experiments/Built_ML_workflow/runs/run_20260218_202848Z_hyperparam_search/run_manifest.yaml`
- `experiments/Built_ML_workflow/runs/run_20260218_202848Z_hyperparam_search/outputs/ML_workflow_built_pipeline_hyperparam_search.ga`
- `experiments/Built_ML_workflow/runs/run_20260218_202848Z_hyperparam_search/outputs/confusion_matrix_chowell_test_hyperparam.png`
- `experiments/Built_ML_workflow/runs/run_20260218_202848Z_hyperparam_search/outputs/confusion_matrix_msk1_test_hyperparam.png`
- `experiments/Built_ML_workflow/runs/run_20260218_202848Z_hyperparam_search/outputs/confusion_matrix_counts_hyperparam.json`
