#!/bin/sh
set -euo pipefail

RUN_ROOT="experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup"
SLEEP_SECONDS="${SLEEP_SECONDS:-60}"
MAX_POLLS="${MAX_POLLS:-120}"

set -a
. ./.env
set +a

: "${GALAXY_URL:?Missing GALAXY_URL in .env}"
: "${GALAXY_API_KEY:?Missing GALAXY_API_KEY in .env}"

JOB_ID="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/metadata/image_learner_execution_ids.json"))["job"]["id"])
PY
)"

mkdir -p "$RUN_ROOT/api"

i=1
while [ "$i" -le "$MAX_POLLS" ]; do
  OUT="$RUN_ROOT/api/40_image_learner_job_status_fixed_poll_${i}.json"
  curl -sS -H "x-api-key: $GALAXY_API_KEY" \
    "$GALAXY_URL/api/jobs/$JOB_ID?full=true" \
    > "$OUT"

  STATE="$(python3 - <<'PY' "$OUT"
import json,sys
print(json.load(open(sys.argv[1])).get("state",""))
PY
)"

  NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$NOW poll=$i job_state=$STATE"

  case "$STATE" in
    ok|error|failed|deleted|stopped)
      exit 0
      ;;
  esac

  i=$((i+1))
  sleep "$SLEEP_SECONDS"
done

echo "Reached MAX_POLLS=$MAX_POLLS without terminal state."
exit 0
