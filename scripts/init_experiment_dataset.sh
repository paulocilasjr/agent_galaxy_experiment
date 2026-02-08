#!/bin/sh
set -eu

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <objective_slug> <dataset_slug> <tool_slug> [objective_text]" >&2
  echo "Example: $0 immunotherapy_response chowell image_learner \"Image learner on Chowell image dataset\"" >&2
  exit 1
fi

OBJECTIVE_SLUG="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed 's/^_//; s/_$//')"
DATASET_SLUG="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed 's/^_//; s/_$//')"
TOOL_SLUG="$(printf '%s' "$3" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed 's/^_//; s/_$//')"
OBJECTIVE_TEXT="${4:-}"

EXPERIMENT_ID="exp_${OBJECTIVE_SLUG}__ds_${DATASET_SLUG}__tool_${TOOL_SLUG}"

if [ -z "$OBJECTIVE_TEXT" ]; then
  OBJECTIVE_TEXT="${OBJECTIVE_SLUG} experiment on ${DATASET_SLUG} using ${TOOL_SLUG}"
fi

PRIMARY_TOOL_HUMAN="$(printf '%s' "$TOOL_SLUG" | tr '_' ' ')"
DATASET_NAME_HUMAN="$(printf '%s' "$DATASET_SLUG" | tr '_' ' ')"

sh scripts/init_experiment.sh "$EXPERIMENT_ID" "$OBJECTIVE_TEXT" "$PRIMARY_TOOL_HUMAN" "$DATASET_NAME_HUMAN"
echo "Experiment ID: $EXPERIMENT_ID"
