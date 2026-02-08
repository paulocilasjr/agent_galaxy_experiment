#!/bin/sh
set -euo pipefail
RUN_ID="$(cat artifacts/latest_run_id.txt)"
set -a
. ./.env
set +a

# Submit corrected payload using pipe-notation conditional keys
curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d @"artifacts/$RUN_ID/configs/tabular_learner_request_rerun_with_test_dataset_pipe.json" \
  "$GALAXY_URL/api/tools" \
  | tee "artifacts/$RUN_ID/api/05c_tabular_learner_run.json"

# Verify has_test_file and test_file binding
JOB_ID="$(python3 - <<'PY'
import json
from pathlib import Path
r=Path('artifacts/latest_run_id.txt').read_text().strip()
print(json.loads(Path(f'artifacts/{r}/api/05c_tabular_learner_run.json').read_text())['jobs'][0]['id'])
PY
)"

curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/jobs/$JOB_ID?full=true" \
  | tee "artifacts/$RUN_ID/api/05c_job_details_full_poll_1.json"

# Then poll job and outputs until terminal state (same loop pattern as step 4).
