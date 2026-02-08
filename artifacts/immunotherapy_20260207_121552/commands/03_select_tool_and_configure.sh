#!/bin/sh
set -euo pipefail
RUN_ID="$(cat artifacts/latest_run_id.txt)"
set -a
. ./.env
set +a

HISTORY_ID="$(python3 - <<'PY'
import json
from pathlib import Path
run_id = Path('artifacts/latest_run_id.txt').read_text().strip()
print(json.loads(Path(f'artifacts/{run_id}/api/02_create_history.json').read_text())['id'])
PY
)"
TOOL_ID='toolshed.g2.bx.psu.edu/repos/goeckslab/tabular_learner/tabular_learner/0.1.4'
ENCODED_TOOL_ID="$(python3 - <<'PY'
import urllib.parse
print(urllib.parse.quote('toolshed.g2.bx.psu.edu/repos/goeckslab/tabular_learner/tabular_learner/0.1.4', safe=''))
PY
)"

curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/tools/$ENCODED_TOOL_ID/build?history_id=$HISTORY_ID" \
  | tee "artifacts/$RUN_ID/api/04_tabular_learner_build.json"

# Edit artifacts/$RUN_ID/configs/tabular_learner_request.json if needed before Step 4 execution.
