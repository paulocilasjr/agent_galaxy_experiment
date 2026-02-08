#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <experiment_id> [run_label] [dataset_alias]" >&2
  exit 1
fi

EXPERIMENT_ID="$1"
RUN_LABEL_RAW="${2:-default}"
DATASET_ALIAS="${3:-}"
RUN_LABEL="$(printf '%s' "$RUN_LABEL_RAW" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed 's/^_//; s/_$//')"

EXPERIMENT_ROOT="experiments/$EXPERIMENT_ID"
if [ ! -d "$EXPERIMENT_ROOT" ]; then
  echo "Experiment does not exist: $EXPERIMENT_ROOT" >&2
  echo "Run scripts/init_experiment.sh first." >&2
  exit 1
fi

STAMP="$(date -u +%Y%m%d_%H%M%SZ)"
RUN_ID="run_${STAMP}_${RUN_LABEL}"
RUN_ROOT="$EXPERIMENT_ROOT/runs/$RUN_ID"
CREATED_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

mkdir -p "$RUN_ROOT/commands" "$RUN_ROOT/prompts" "$RUN_ROOT/configs" "$RUN_ROOT/metadata" "$RUN_ROOT/api" "$RUN_ROOT/outputs"
printf '%s\n' "$GIT_COMMIT" > "$RUN_ROOT/metadata/git_commit.txt"

cat > "$RUN_ROOT/run_manifest.yaml" <<EOF
experiment_id: $EXPERIMENT_ID
run_id: $RUN_ID
created_utc: $CREATED_UTC
status: in_progress
dataset_alias: "$DATASET_ALIAS"
tool_name: ""
tool_id: ""
tool_version: ""
history_name: ""
history_id: ""
base_run_id: ""
inputs: {}
outputs: {}
notes: ""
EOF

cat > "$RUN_ROOT/journal.md" <<EOF
# Run Journal: $RUN_ID

## Context
- experiment_id: \`$EXPERIMENT_ID\`
- run_id: \`$RUN_ID\`
- run_label: \`$RUN_LABEL_RAW\`
- dataset_alias: \`$DATASET_ALIAS\`
- created_utc: \`$CREATED_UTC\`

## Timeline
EOF

printf '%s\n' "$RUN_ID" > "$EXPERIMENT_ROOT/latest_run_id.txt"

if [ ! -f "$EXPERIMENT_ROOT/summaries/run_index.tsv" ]; then
  printf 'run_id\tcreated_utc\tstatus\ttool_id\tdataset_alias\tnotes\n' > "$EXPERIMENT_ROOT/summaries/run_index.tsv"
fi
printf '%s\t%s\tin_progress\t\t%s\t%s\n' "$RUN_ID" "$CREATED_UTC" "$DATASET_ALIAS" "$RUN_LABEL_RAW" >> "$EXPERIMENT_ROOT/summaries/run_index.tsv"

echo "Initialized run: $RUN_ROOT"
echo "Run ID: $RUN_ID"
