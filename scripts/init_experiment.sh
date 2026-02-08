#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <experiment_id> [objective] [primary_tool] [dataset_name]" >&2
  exit 1
fi

EXPERIMENT_ID="$1"
OBJECTIVE="${2:-}"
PRIMARY_TOOL="${3:-}"
DATASET_NAME="${4:-}"
CREATED_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EXPERIMENT_ROOT="experiments/$EXPERIMENT_ID"

mkdir -p "$EXPERIMENT_ROOT/runs" "$EXPERIMENT_ROOT/summaries" "$EXPERIMENT_ROOT/datasets" "$EXPERIMENT_ROOT/configs" "$EXPERIMENT_ROOT/references"

if [ ! -f "$EXPERIMENT_ROOT/experiment.yaml" ]; then
  cat > "$EXPERIMENT_ROOT/experiment.yaml" <<EOF
experiment_id: $EXPERIMENT_ID
created_utc: $CREATED_UTC
objective: "$OBJECTIVE"
primary_tool: "$PRIMARY_TOOL"
dataset_name: "$DATASET_NAME"
status: active
EOF
fi

if [ ! -f "$EXPERIMENT_ROOT/datasets/manifest.tsv" ]; then
  printf 'dataset_alias\tsource_type\tsource\tnotes\n' > "$EXPERIMENT_ROOT/datasets/manifest.tsv"
fi

if [ ! -f "$EXPERIMENT_ROOT/summaries/run_index.tsv" ]; then
  printf 'run_id\tcreated_utc\tstatus\ttool_id\tdataset_alias\tnotes\n' > "$EXPERIMENT_ROOT/summaries/run_index.tsv"
fi

if [ ! -f "$EXPERIMENT_ROOT/README.md" ]; then
  cat > "$EXPERIMENT_ROOT/README.md" <<EOF
# $EXPERIMENT_ID

## Experiment Metadata
- objective: $OBJECTIVE
- primary_tool: $PRIMARY_TOOL
- dataset_name: $DATASET_NAME
- created_utc: $CREATED_UTC

## Where Things Go
- dataset mapping: \`datasets/manifest.tsv\`
- run artifacts: \`runs/<run_id>/...\`
- cross-run summaries: \`summaries/\`
EOF
fi

mkdir -p experiments
if [ ! -f experiments/index.tsv ]; then
  printf 'experiment_id\tcreated_utc\tstatus\tprimary_tool\tdataset_name\texperiment_root\n' > experiments/index.tsv
fi

if ! rg -q "^${EXPERIMENT_ID}\t" experiments/index.tsv; then
  printf '%s\t%s\tactive\t%s\t%s\t%s\n' "$EXPERIMENT_ID" "$CREATED_UTC" "$PRIMARY_TOOL" "$DATASET_NAME" "$EXPERIMENT_ROOT" >> experiments/index.tsv
fi

echo "Initialized experiment: $EXPERIMENT_ROOT"
