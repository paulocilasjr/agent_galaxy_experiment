#!/bin/sh
set -euo pipefail
RUN_ID="$(cat artifacts/latest_run_id.txt)"
set -a
. ./.env
set +a

# Submit job
curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d @"artifacts/$RUN_ID/configs/tabular_learner_request.json" \
  "$GALAXY_URL/api/tools" \
  | tee "artifacts/$RUN_ID/api/05_tabular_learner_run.json"

# Extract IDs
python3 - <<'PY'
import json
from pathlib import Path
run_id = Path('artifacts/latest_run_id.txt').read_text().strip()
run = json.loads(Path(f'artifacts/{run_id}/api/05_tabular_learner_run.json').read_text())
Path(f'artifacts/{run_id}/metadata/05_execution_ids.json').write_text(json.dumps({
    'job_id': run['jobs'][0]['id'],
    'tool_id': run['jobs'][0]['tool_id'],
    'history_id': run['jobs'][0]['history_id'],
    'output_datasets': {o['output_name']: o['id'] for o in run['outputs']}
}, indent=2) + '\n')
PY

JOB_ID="$(python3 - <<'PY'
import json
from pathlib import Path
run_id=Path('artifacts/latest_run_id.txt').read_text().strip()
print(json.loads(Path(f'artifacts/{run_id}/metadata/05_execution_ids.json').read_text())['job_id'])
PY
)"
MODEL_ID="$(python3 - <<'PY'
import json
from pathlib import Path
run_id=Path('artifacts/latest_run_id.txt').read_text().strip()
print(json.loads(Path(f'artifacts/{run_id}/metadata/05_execution_ids.json').read_text())['output_datasets']['model'])
PY
)"
CSV_ID="$(python3 - <<'PY'
import json
from pathlib import Path
run_id=Path('artifacts/latest_run_id.txt').read_text().strip()
print(json.loads(Path(f'artifacts/{run_id}/metadata/05_execution_ids.json').read_text())['output_datasets']['best_model_csv'])
PY
)"
HTML_ID="$(python3 - <<'PY'
import json
from pathlib import Path
run_id=Path('artifacts/latest_run_id.txt').read_text().strip()
print(json.loads(Path(f'artifacts/{run_id}/metadata/05_execution_ids.json').read_text())['output_datasets']['comparison_result'])
PY
)"

SUMMARY_FILE="artifacts/$RUN_ID/metadata/05_execution_poll_summary.log"
: > "$SUMMARY_FILE"

for i in $(seq 1 90); do
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  curl -sS -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/jobs/$JOB_ID" > "artifacts/$RUN_ID/api/05_job_status_poll_${i}.json"
  curl -sS -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/datasets/$MODEL_ID" > "artifacts/$RUN_ID/api/05_dataset_model_poll_${i}.json"
  curl -sS -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/datasets/$CSV_ID" > "artifacts/$RUN_ID/api/05_dataset_best_model_csv_poll_${i}.json"
  curl -sS -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/datasets/$HTML_ID" > "artifacts/$RUN_ID/api/05_dataset_comparison_result_poll_${i}.json"

  export POLL_I="$i"
  STATES=$(python3 - <<'PY'
import json, os
from pathlib import Path
run_id=Path('artifacts/latest_run_id.txt').read_text().strip()
idx=os.environ['POLL_I']
base=Path(f'artifacts/{run_id}/api')
job=json.loads((base/f'05_job_status_poll_{idx}.json').read_text()).get('state')
model=json.loads((base/f'05_dataset_model_poll_{idx}.json').read_text()).get('state')
csv=json.loads((base/f'05_dataset_best_model_csv_poll_{idx}.json').read_text()).get('state')
html=json.loads((base/f'05_dataset_comparison_result_poll_{idx}.json').read_text()).get('state')
print(f"{job}\t{model}\t{csv}\t{html}")
PY
)
  JOB_STATE=$(printf '%s' "$STATES" | cut -f1)
  MODEL_STATE=$(printf '%s' "$STATES" | cut -f2)
  CSV_STATE=$(printf '%s' "$STATES" | cut -f3)
  HTML_STATE=$(printf '%s' "$STATES" | cut -f4)
  printf '%s poll=%s job=%s model=%s csv=%s html=%s\n' "$TS" "$i" "$JOB_STATE" "$MODEL_STATE" "$CSV_STATE" "$HTML_STATE" | tee -a "$SUMMARY_FILE"

  if [ "$JOB_STATE" = "ok" ] || [ "$JOB_STATE" = "error" ] || [ "$JOB_STATE" = "deleted" ]; then
    break
  fi
  sleep 20
done
