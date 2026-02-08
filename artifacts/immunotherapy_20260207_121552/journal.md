# Run Journal: immunotherapy_20260207_121552

## Purpose
Linear story of what was asked, what was executed, what failed, and how issues were fixed.

## Run Context
- run_id: `immunotherapy_20260207_121552`
- galaxy_url: `https://usegalaxy.org`
- history_name: `agent-tabular_learner`
- history_id: `bbd44e69cb8906b5818b2d41fc14f7a1`

## Timeline

### 0) Reproducibility framework created
- User prompt: create a skill-like file to capture commands, prompts, file paths, architecture, and all 5 steps.
- Action:
  - Created `skills/immunotherapy-tabular-learner/SKILL.md`.
  - Defined step-by-step workflow (connection, upload, configure, execute, download).
  - Added artifact folder contract and prompt logging template.
- Outcome: reproducibility scaffold established.

### 1) Galaxy API setup
- User prompt: set Galaxy API key.
- Timestamp: `2026-02-07T17:16:21Z` (from `prompts/01_setup_api_prompt.md`)
- Action:
  - Created local `.env` and `.env.example`.
  - Initialized run folder `artifacts/immunotherapy_20260207_121552/`.
  - Called `/api/users/current` to validate credentials.
- Error encountered:
  - In sandbox: DNS/network resolution failure (`curl: (6) Could not resolve host: usegalaxy.org`).
- Fix:
  - Re-ran with network-enabled execution.
- Outcome:
  - Connection verified.
  - API response saved in `api/01_users_current.json`.
  - API key redacted from prompt logs.

### 2) Create history and upload datasets from URLs
- User prompt: create history `agent-tabular_learner` and upload:
  - `https://zenodo.org/records/17781688/files/Chowell_train.tsv`
  - `https://zenodo.org/records/17781688/files/Chowell_test.tsv`
- Timestamp: `2026-02-07T17:26:00Z` (from `prompts/02_upload_prompt.md`)
- Action:
  - Created history via `/api/histories`.
  - Uploaded via `/api/tools/fetch`.
- Errors encountered:
  - `03_upload_fetch_attempt1_error.json`: schema validation error (`destination`/`elements` missing).
  - `03_upload_fetch_attempt2_error.json`: schema validation error (`history_id` missing).
- Fix:
  - Switched to valid fetch payload with:
    - top-level `history_id`
    - `targets[].destination`
    - `targets[].elements[]`
- Outcome:
  - Upload succeeded.
  - `Chowell_train.tsv`: `f9cad7b01a47213515562d8d15c5db3d` (`ok`, 965 rows, 22 cols)
  - `Chowell_test.tsv`: `f9cad7b01a4721353f443ce2cb15cd33` (`ok`, 516 rows, 22 cols)

### 3) Select tool and configure parameters
- User prompt: select `Tabular Learner`, set:
  - Input Dataset = `Chowell_train.tsv`
  - Separate test dataset = `yes`
  - Tabular Test Dataset = `Chowell_test.tsv`
  - Target column = `c22: Response`
- Timestamp: `2026-02-07T17:31:00Z` (from `prompts/03_tool_setup_prompt.md`)
- Action:
  - Discovered installed tool versions.
  - Selected `toolshed.g2.bx.psu.edu/repos/goeckslab/tabular_learner/tabular_learner/0.1.4`.
  - Built tool form schema (`api/04_tabular_learner_build.json`).
  - Wrote request payload and config notes.
- Outcome:
  - Configuration artifacts created under `configs/`.

### 4) First execution
- User prompt: execute tool with all configuration.
- Timestamp: `2026-02-07T17:41:30Z` (from `prompts/04_execute_prompt.md`)
- Action:
  - Submitted run (`api/05_tabular_learner_run.json`).
  - Polled job/datasets until terminal state.
- Outcome:
  - Job `bbd44e69cb8906b54f799399bb524738` completed `ok`.
  - Outputs produced (`hid` 3-5).

### 5) User-detected configuration bug (important correction)
- User prompt: test dataset was not used; fix and rerun.
- Timestamp: `2026-02-08T00:27:00Z` (from `prompts/04b_fix_test_dataset_and_rerun.md`)
- Investigation:
  - Checked full job details for first run (`api/05_job_details_full.json`).
  - Found root cause:
    - `params.test_data_choice = {"__current_case__": 1, "has_test_file": "no"}`
    - no test dataset input binding.
- First fix attempt:
  - Submitted nested JSON conditional payload (`05b` run).
  - Still resolved to `has_test_file=no`.
- Working fix:
  - Switched to Galaxy pipe-notation conditional keys:
    - `test_data_choice|has_test_file = yes`
    - `test_data_choice|test_file = <Chowell_test.tsv HDA>`
  - Submitted corrected run (`api/05c_tabular_learner_run.json`).
- Verified evidence:
  - `api/05c_job_details_full_final.json` shows:
    - `has_test_file=yes`
    - `inputs.test_data_choice|test_file = f9cad7b01a4721353f443ce2cb15cd33`
    - command line contains `--test_file ...`
- Corrected outcome:
  - Job `bbd44e69cb8906b565ae45e2520ae066` completed `ok`.
  - Corrected outputs:
    - model (h5): `f9cad7b01a472135b43201caca78bb3f`
    - best model params (csv): `f9cad7b01a4721355e80a48e5a82f8f4`
    - analysis report (html): `f9cad7b01a472135fcdbe02831df1b6d`
  - Canonical request updated to fixed format in:
    - `configs/tabular_learner_request.json`

### 6) Journal requirement added
- User prompt: add a journal file with linear history of prompts, errors, and fixes.
- Action:
  - Created this file.
  - Updated skill instructions to require `journal.md` in each run.
- Outcome:
  - Future runs must include linear narrative documentation.

## Key Files To Read First
- `artifacts/immunotherapy_20260207_121552/metadata/run_manifest.yaml`
- `artifacts/immunotherapy_20260207_121552/prompts/`
- `artifacts/immunotherapy_20260207_121552/metadata/05c_execution_result.json`
- `artifacts/immunotherapy_20260207_121552/api/05c_job_details_full_final.json`

## Notes
- Secrets are intentionally excluded from artifacts. API keys remain only in local `.env`.

### 7) New setup request: customize defaults + probability threshold
- User prompt: keep setup identical to last corrected run, but set `Customize Default Settings = yes` and `Classification Probability Threshold = 0.25`.
- Timestamp: `2026-02-08T00:36:57Z` (from `prompts/03b_customize_default_threshold_prompt.md`)
- Action:
  - Created `configs/tabular_learner_request_custom_prob_025.json`.
  - Promoted it as canonical payload in `configs/tabular_learner_request.json`.
  - Recorded setup metadata in `metadata/03b_tool_setup_custom_prob_025.json`.
- Outcome:
  - Tool is configured for next execution with only the requested functional change: probability threshold `0.25` under customized defaults.

### 8) Execute new job with custom probability threshold
- User prompt: run the new job configured with customize defaults and probability threshold `0.25`.
- Timestamp: 2026-02-08T04:46:05Z (from `prompts/04c_run_custom_prob_job_prompt.md`)
- Action:
  - Submitted `configs/tabular_learner_request.json` (customized defaults enabled).
  - Verified early job metadata includes:
    - `has_test_file=yes`
    - `test_data_choice|test_file = f9cad7b01a4721353f443ce2cb15cd33`
    - `--probability_threshold '0.25'` in command line.
  - Polled job and outputs to terminal state.
- Outcome:
  - Job `bbd44e69cb8906b508227afbe60b766d` completed `ok`.
  - Outputs:
    - model (h5): `f9cad7b01a47213541e9af7a2d86fed9`
    - best model params (csv): `f9cad7b01a4721355f32b3a3a11aecd4`
    - analysis report (html): `f9cad7b01a47213526f7e6ae60c97438`

### 9) Compare test-split metrics across 4 runs (PNG table)
- User prompt: read report HTML outputs and create PNG table comparing test split metrics (Accuracy, ROC-AUC, Precision, Recall, F1-score) across 4 runs.
- Timestamp: 2026-02-08T04:59:24Z (from `prompts/05_compare_test_metrics_prompt.md`)
- Action:
  - Downloaded report datasets for all 4 runs and recorded states in `metadata/06_report_dataset_states.tsv`.
  - Detected report files are zip containers with embedded HTML; extracted HTML before parsing.
  - Parsed split-metrics table (`Metric/Train/Validation/Test`) and extracted Test-column values.
  - Rendered comparison table image using Pillow (`matplotlib` not available in environment).
- Outcome:
  - Created `outputs/reports/test_split_metrics_comparison.png`.
  - Created extracted data files:
    - `outputs/reports/test_split_metrics_by_run.csv`
    - `outputs/reports/test_split_metrics_by_run.json`
