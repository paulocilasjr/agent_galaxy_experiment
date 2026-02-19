# Run Journal: run_20260218_180758Z_setup

## Context
- experiment_id: `Built_ML_workflow`
- run_id: `run_20260218_180758Z_setup`
- created_utc: `2026-02-18T18:07:58Z`
- objective: Build a Galaxy ML workflow (starting with Pipeline Builder) that trains on Chowell train data, predicts on Chowell/MSK1 test cohorts, and generates confusion matrices for both cohorts.

## Timeline
### 2026-02-18T18:07:58Z - Experiment scaffold created
- Action:
  - Created experiment folder `experiments/Built_ML_workflow`.
  - Created run folder `experiments/Built_ML_workflow/runs/run_20260218_180758Z_setup` with standard artifact subfolders: `commands`, `prompts`, `configs`, `metadata`, `api`, `outputs`.
  - Initialized `experiment.yaml`, `run_manifest.yaml`, `datasets/manifest.tsv`, `summaries/run_index.tsv`, and prompt capture file.

### 2026-02-18T18:08:48Z - Galaxy history creation + input upload
- Action:
  - Created Galaxy history `ML_workflow` (`history_id: bbd44e69cb8906b519322378c6ea8f6e`).
  - Uploaded 5 TSV files via `/api/tools/fetch`:
    - `Chowell_test_No_Response.tsv` (`f9cad7b01a47213588efba34d9aa5fcd`, hid 1)
    - `Chowell_test_Response.tsv` (`f9cad7b01a4721353a31536b18594d1c`, hid 2)
    - `Chowell_train_Response.tsv` (`f9cad7b01a472135fcee3144425e2753`, hid 3)
    - `MSK1_No_Response.tsv` (`f9cad7b01a4721354130d78b087ddcd1`, hid 4)
    - `MSK1_Response.tsv` (`f9cad7b01a472135932c95d1fc41ff39`, hid 5)
- Outcome:
  - All uploaded datasets reached `ok` state.

### 2026-02-18T18:09Z - Input shape analysis
- Action:
  - Profiled uploaded tables and inferred row/column counts from tabular headers and line counts.
- Findings:
  - `Chowell_train_Response.tsv`: 964 x 22
  - `Chowell_test_Response.tsv`: 515 x 22
  - `MSK1_Response.tsv`: 453 x 22
  - `Chowell_test_No_Response.tsv`: 515 x 21
  - `MSK1_No_Response.tsv`: 453 x 21
- Interpretation:
  - `*_No_Response.tsv` are feature-only test tables.
  - `*_Response.tsv` include the `Response` label used for evaluation.

### 2026-02-18T18:10Z - Tool selection and workflow design
- Action:
  - Queried installed Galaxy tools and resolved candidate IDs.
- Selected tool chain:
  1. `Pipeline Builder` (`sklearn_build_pipeline`)
  2. `Fit a Pipeline, Ensemble` (`sklearn_model_fit`)
  3. `Model Prediction` (twice: Chowell and MSK1)
  4. `Plot confusion matrix, precision, recall and ROC and AUC curves` (twice)
- Designed data flow:
  - Train with `Chowell_train_Response.tsv`.
  - Predict on `Chowell_test_No_Response.tsv` and `MSK1_No_Response.tsv`.
  - Evaluate with `Chowell_test_Response.tsv` and `MSK1_Response.tsv`.

### 2026-02-18T18:11Z - First pipeline-chain attempt
- Action:
  - Submitted Pipeline Builder with LogisticRegression final estimator.
  - Pipeline builder output produced (`hid 6`: `New Pipleline/Estimator`).
- Error encountered on next step (`Model Fit`):
  - API error: `Parameter 'col1': an invalid option (None) was selected`.
  - Cause: nested conditional input encoding did not resolve dynamic selector values for `column_selector_options_1`.

### 2026-02-18T18:15Z - Fix applied and successful chain execution
- Fix:
  - Switched to flattened conditional keys (`input_options|...`) for tool submission payloads.
  - Used header-based selectors for label column:
    - exclude `Response` from features
    - select `Response` as target
- Successful jobs:
  - Pipeline Builder job: `bbd44e69cb8906b5b326ae67fab9cd2f`
  - Model Fit job: `bbd44e69cb8906b5ec06b97be0b7e3cb`
  - Prediction (Chowell) job: `bbd44e69cb8906b5ff0bd2346ab71ecb`
  - Prediction (MSK1) job: `bbd44e69cb8906b59559f4b98bcded4d`
  - Plot (Chowell) job: `bbd44e69cb8906b54c600b6fb990877c`
  - Plot (MSK1) job: `bbd44e69cb8906b506c6502ed144f7c1`
- Generated outputs in history (all `ok`):
  - model estimator (hid 7)
  - predictions (hid 8, 9)
  - confusion matrices (hid 10, 13)
  - precision/recall reports (hid 11, 14)
  - ROC/AUC reports (hid 12, 15)

### 2026-02-18T18:19Z - Workflow extraction
- First extraction attempt (`from_history_id` only):
  - Produced workflow object but downloaded `.ga` had `0` steps.
- Fix:
  - Re-extracted using explicit `job_ids` from the successful chain.
- Final workflow:
  - `workflow_id: 4588c13287e93b82`
  - Name: `ML_workflow_built_pipeline`
  - Steps: 6
    1. Pipeline Builder
    2. Fit a Pipeline, Ensemble
    3. Model Prediction (Chowell)
    4. Model Prediction (MSK1)
    5. Plot confusion matrix... (Chowell)
    6. Plot confusion matrix... (MSK1)
  - Saved locally to `outputs/ML_workflow_built_pipeline.ga`.

### 2026-02-18T18:20Z - Local artifact download and metric summary
- Downloaded from Galaxy to `outputs/`:
  - `confusion_matrix_chowell_test.png`
  - `confusion_matrix_msk1_test.png`
  - precision/recall and ROC/AUC HTML reports for both cohorts
  - prediction TSVs for both cohorts
- Computed confusion matrix counts by comparing predictions to `Response` labels:
  - Chowell test (`n=515`): TP=127, TN=27, FP=361, FN=0, accuracy=0.2990
  - MSK1 test (`n=453`): TP=115, TN=10, FP=327, FN=1, accuracy=0.2759
- Saved summaries:
  - `outputs/confusion_matrix_counts.json`
  - `outputs/confusion_matrix_counts.tsv`
  - `outputs/input_shape_summary.tsv`

## Final Outcome
- Requested history `ML_workflow` was created and populated.
- Input shapes were analyzed and recorded.
- A Pipeline Builder-based ML chain was executed successfully.
- Confusion matrices were generated for both requested test cohorts.
- A reusable Galaxy workflow was created and saved (`workflow_id: 4588c13287e93b82`).

## Key Files
- `experiments/Built_ML_workflow/runs/run_20260218_180758Z_setup/run_manifest.yaml`
- `experiments/Built_ML_workflow/runs/run_20260218_180758Z_setup/metadata/ml_workflow_run_summary.json`
- `experiments/Built_ML_workflow/runs/run_20260218_180758Z_setup/outputs/ML_workflow_built_pipeline.ga`
- `experiments/Built_ML_workflow/runs/run_20260218_180758Z_setup/outputs/confusion_matrix_chowell_test.png`
- `experiments/Built_ML_workflow/runs/run_20260218_180758Z_setup/outputs/confusion_matrix_msk1_test.png`
