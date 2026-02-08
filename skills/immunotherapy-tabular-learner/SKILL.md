---
name: immunotherapy-tabular-learner
description: Reproducible Galaxy workflow for training and evaluating an immunotherapy response prediction model with Tabular Learner. Use when setting up Galaxy access, uploading data, configuring Tabular Learner, executing jobs, and downloading outputs with complete traceability of commands, prompts, file paths, parameters, and artifacts.
---

# Objective
Build a reproducible end-to-end experiment for immunotherapy response prediction using Galaxy `Tabular Learner`.

# Reproducibility Contract
For every run, capture:
1. Exact command lines executed.
2. Exact prompts used (if an agent/chat interface is involved).
3. Input and output file paths.
4. Full tool configuration payload (all parameters).
5. Galaxy identifiers (`history_id`, `dataset_id`, `job_id`, `invocation_id` when available).
6. Git commit hash of this repository.

# Secrets Handling Rules
1. Never store API keys, passwords, tokens, or cookies in `artifacts/`, `configs/`, `prompts/`, `commands/`, or committed files.
2. Keep secrets only in local `.env` (already gitignored) and reference them by variable name (for example `$GALAXY_API_KEY`).
3. If a prompt or command includes a secret, log a redacted value (for example `[REDACTED_API_KEY]`).
4. In reproducibility notes, document secret acquisition steps, not secret values:
   1. Open Galaxy in browser.
   2. Go to user menu -> preferences/settings -> API key management.
   3. Create or copy API key.
   4. Place it in local `.env` as `GALAXY_API_KEY`.

# Project Artifact Layout
Use one run folder per execution:

```text
artifacts/
  <RUN_ID>/
    commands/                 # shell command transcript
    prompts/                  # prompts and model/agent responses
    configs/                  # tool input payloads and parameter files
    metadata/                 # run manifest and IDs
    outputs/                  # downloaded result files
    api/                      # raw Galaxy API request/response JSON
```

Also keep a linear run journal:

```text
artifacts/
  <RUN_ID>/
    journal.md               # chronological story: prompts, actions, errors, fixes, outcomes
```

# Multi-Experiment Layout (Recommended)
For multiple datasets/tools in one repository, namespace runs by experiment:

```text
experiments/
  <EXPERIMENT_ID>/
    experiment.yaml
    latest_run_id.txt
    runs/
      <RUN_ID>/
        commands/
        prompts/
        configs/
        metadata/
        outputs/
        api/
        journal.md
        run_manifest.yaml
```

Use:
1. `sh scripts/init_experiment_dataset.sh <objective_slug> <dataset_slug> <tool_slug> [objective_text]`
2. `sh scripts/init_run.sh <EXPERIMENT_ID> [run_label] [dataset_alias]`

Then treat:
- `RUN_ROOT="experiments/$EXPERIMENT_ID/runs/$RUN_ID"`
- Replace `artifacts/$RUN_ID/...` paths in this skill with `$RUN_ROOT/...`
- For all new experiments, do not create new run artifacts directly under top-level `artifacts/`; treat `artifacts/` as legacy migration area.

Recommended `EXPERIMENT_ID` pattern:
- `exp_<objective_slug>__ds_<dataset_slug>__tool_<tool_slug>`
- Example:
  - `exp_histopathology_response__ds_tcga_tiles__tool_image_learner`

# Session Bootstrap (Run First)
```bash
export RUN_ID="immunotherapy_$(date +%Y%m%d_%H%M%S)"
mkdir -p "artifacts/$RUN_ID"/{commands,prompts,configs,metadata,outputs,api}
git rev-parse HEAD > "artifacts/$RUN_ID/metadata/git_commit.txt"
```

If using experiment-scoped mode, bootstrap with:

```bash
sh scripts/init_experiment_dataset.sh immunotherapy_response chowell tabular_learner "Immunotherapy response prediction using Tabular Learner"
export EXPERIMENT_ID="exp_immunotherapy_response__ds_chowell__tool_tabular_learner"
sh scripts/init_run.sh "$EXPERIMENT_ID" baseline chowell_v1
export RUN_ID="$(cat "experiments/$EXPERIMENT_ID/latest_run_id.txt")"
export RUN_ROOT="experiments/$EXPERIMENT_ID/runs/$RUN_ID"
```

Create `artifacts/$RUN_ID/metadata/run_manifest.yaml`:

```yaml
project: immunotherapy_tabular_learner
run_id: <RUN_ID>
date_utc: <YYYY-MM-DDTHH:MM:SSZ>
operator: <name>
galaxy_url: <https://...>
history_name: <history name>
history_id: <fill after creation>
tool_name: Tabular Learner
tool_id: <fill after discovery>
inputs:
  clinical_table: <path>
  response_label_column: <column_name>
outputs:
  model_summary: <path>
  predictions_table: <path>
status: in_progress
```

# Step 1: Setup Galaxy Connection
Store credentials in `.env` (never commit secrets):

```bash
GALAXY_URL="https://usegalaxy.org"
GALAXY_API_KEY="<your_api_key>"
```

Validate connection and log response:

```bash
set -a; . ./.env; set +a
curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/users/current" \
  | tee "artifacts/$RUN_ID/api/01_users_current.json"
```

Record command text in:
`artifacts/$RUN_ID/commands/01_setup_connection.sh`

# Step 2: Upload Files to a New History
Create history:

```bash
HISTORY_NAME="immunotherapy_tabular_learner_$RUN_ID"
HISTORY_ID=$(
  curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
    -d "{\"name\":\"$HISTORY_NAME\"}" \
    "$GALAXY_URL/api/histories" \
  | tee "artifacts/$RUN_ID/api/02_create_history.json" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])'
)
echo "$HISTORY_ID" > "artifacts/$RUN_ID/metadata/history_id.txt"
```

Upload each local dataset (repeat per file):

```bash
LOCAL_FILE="data/immunotherapy_training.tsv"
FILE_NAME="$(basename "$LOCAL_FILE")"

curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  -F "history_id=$HISTORY_ID" \
  -F "tool_id=upload1" \
  -F "files_0|NAME=$FILE_NAME" \
  -F "files_0|type=upload_dataset" \
  -F "files_0|file_data=@$LOCAL_FILE" \
  "$GALAXY_URL/api/tools" \
  | tee "artifacts/$RUN_ID/api/03_upload_${FILE_NAME}.json"
```

Log prompt(s), if any, in:
`artifacts/$RUN_ID/prompts/02_upload_prompt.md`

# Step 3: Select `Tabular Learner` and Capture Full Configuration
Create a configuration record file:
`artifacts/$RUN_ID/configs/tabular_learner_config.md`

Include:
1. Tool name and resolved `tool_id`.
2. Input dataset ID(s) chosen from the history.
3. Target column (immunotherapy response label).
4. Data split strategy (train/validation/test or CV).
5. Algorithm choices and hyperparameters.
6. Random seed.
7. Any preprocessing options.

Also store the exact API payload used to run the tool:
`artifacts/$RUN_ID/configs/tabular_learner_request.json`

Template:

```json
{
  "history_id": "<HISTORY_ID>",
  "tool_id": "<TABULAR_LEARNER_TOOL_ID>",
  "inputs": {
    "input_table": { "src": "hda", "id": "<INPUT_DATASET_ID>" },
    "target_column": "<RESPONSE_COLUMN>",
    "random_seed": 42
  }
}
```

# Step 4: Execute the Tool (Job)
Run from saved JSON payload:

```bash
curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d @"artifacts/$RUN_ID/configs/tabular_learner_request.json" \
  "$GALAXY_URL/api/tools" \
  | tee "artifacts/$RUN_ID/api/04_tabular_learner_run.json"
```

Extract and persist IDs from response:
`job_id`, output `dataset_id` values, and any invocation metadata into
`artifacts/$RUN_ID/metadata/execution_ids.json`.

Track job state until completion and save each poll result:

```bash
OUTPUT_DATASET_ID="<fill_from_04_response>"
curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$OUTPUT_DATASET_ID" \
  | tee "artifacts/$RUN_ID/api/04_output_dataset_status.json"
```

# Step 5: Download Results for Analysis
Download each required output dataset:

```bash
PRED_DATASET_ID="<predictions_dataset_id>"
curl -sS -L -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$PRED_DATASET_ID/display?to_ext=tabular" \
  -o "artifacts/$RUN_ID/outputs/predictions.tsv"
```

Optional: export history metadata snapshot:

```bash
curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/histories/$HISTORY_ID/contents" \
  | tee "artifacts/$RUN_ID/api/05_history_contents.json"
```

Mark completion:
1. Update `artifacts/$RUN_ID/metadata/run_manifest.yaml` status to `completed`.
2. Add final notes in `artifacts/$RUN_ID/metadata/analysis_notes.md`.

# Prompt Logging Template
For each conversational step, create `artifacts/$RUN_ID/prompts/<step>.md`:

```markdown
# Prompt Log
timestamp_utc: <YYYY-MM-DDTHH:MM:SSZ>
step: <1|2|3|4|5>
goal: <what was requested>

## prompt
<exact prompt text>

## response_summary
<short summary of what was done>

## artifacts_created
- <path>
- <path>
```

# Minimum Evidence Checklist
Before considering a run reproducible, ensure all exist:
1. `artifacts/$RUN_ID/metadata/git_commit.txt`
2. `artifacts/$RUN_ID/metadata/run_manifest.yaml`
3. `artifacts/$RUN_ID/configs/tabular_learner_request.json`
4. `artifacts/$RUN_ID/api/04_tabular_learner_run.json`
5. At least one downloaded output in `artifacts/$RUN_ID/outputs/`
6. `artifacts/$RUN_ID/journal.md` with a linear timeline including prompts, errors, and fixes
