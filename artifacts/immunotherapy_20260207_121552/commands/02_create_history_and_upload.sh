#!/bin/sh
set -euo pipefail
RUN_ID="$(cat artifacts/latest_run_id.txt)"
set -a
. ./.env
set +a

HISTORY_NAME="agent-tabular_learner"

curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d "{\"name\":\"$HISTORY_NAME\"}" \
  "$GALAXY_URL/api/histories" \
  | tee "artifacts/$RUN_ID/api/02_create_history.json"

HISTORY_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "artifacts/$RUN_ID/api/02_create_history.json")"

cat > "artifacts/$RUN_ID/configs/02_fetch_targets.json" <<JSON
{
  "history_id": "$HISTORY_ID",
  "targets": [
    {
      "destination": {"type": "hdas", "id": "$HISTORY_ID"},
      "elements": [
        {"src": "url", "url": "https://zenodo.org/records/17781688/files/Chowell_train.tsv", "name": "Chowell_train.tsv"},
        {"src": "url", "url": "https://zenodo.org/records/17781688/files/Chowell_test.tsv", "name": "Chowell_test.tsv"}
      ]
    }
  ]
}
JSON

curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d @"artifacts/$RUN_ID/configs/02_fetch_targets.json" \
  "$GALAXY_URL/api/tools/fetch" \
  | tee "artifacts/$RUN_ID/api/03_upload_fetch.json"

curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/histories/$HISTORY_ID/contents?details=all" \
  | tee "artifacts/$RUN_ID/api/03_history_contents_after_upload.json"
