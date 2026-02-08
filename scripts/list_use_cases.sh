#!/bin/sh
set -eu

INDEX="experiments/index.tsv"

if [ ! -f "$INDEX" ]; then
  echo "Missing $INDEX" >&2
  exit 1
fi

printf 'Active use cases:\n'
tail -n +2 "$INDEX" | while IFS="$(printf '\t')" read -r experiment_id created_utc status primary_tool dataset_name experiment_root; do
  if [ "$status" = "active" ]; then
    printf -- '- %s (%s, %s)\n' "$experiment_id" "$dataset_name" "$primary_tool"
    printf '  entrypoint: %s/START_HERE.md\n' "$experiment_root"
    if [ -f "$experiment_root/REPRODUCE.md" ]; then
      printf '  reproduce: %s/REPRODUCE.md\n' "$experiment_root"
    fi
  fi
done
