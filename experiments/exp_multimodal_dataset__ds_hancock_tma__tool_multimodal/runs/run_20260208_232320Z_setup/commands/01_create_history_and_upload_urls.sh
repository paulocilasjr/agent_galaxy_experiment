#!/bin/sh
set -euo pipefail

RUN_ROOT="experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup"
HISTORY_NAME="Agent-Multimodal"

mkdir -p "$RUN_ROOT/api" "$RUN_ROOT/configs" "$RUN_ROOT/metadata" "$RUN_ROOT/outputs"

set -a
. ./.env
set +a

: "${GALAXY_URL:?Missing GALAXY_URL in .env}"
: "${GALAXY_API_KEY:?Missing GALAXY_API_KEY in .env}"

curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/users/current" \
  > "$RUN_ROOT/api/01_users_current.json"

curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d "{\"name\":\"$HISTORY_NAME\"}" \
  "$GALAXY_URL/api/histories" \
  > "$RUN_ROOT/api/02_create_history_agent_multimodal.json"

HISTORY_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$RUN_ROOT/api/02_create_history_agent_multimodal.json")"
printf '%s\n' "$HISTORY_ID" > "$RUN_ROOT/metadata/history_id.txt"

cat > "$RUN_ROOT/configs/03_fetch_targets.json" <<JSON
{
  "history_name": "$HISTORY_NAME",
  "history_id": "$HISTORY_ID",
  "targets": [
    {
      "destination": {"type": "hdas", "id": "$HISTORY_ID"},
      "elements": [
        {"src": "url", "url": "https://zenodo.org/records/17933596/files/HANCOCK_train_split.csv", "name": "HANCOCK_train_split.csv"},
        {"src": "url", "url": "https://zenodo.org/records/17933596/files/HANCOCK_test_split.csv", "name": "HANCOCK_test_split.csv"},
        {"src": "url", "url": "https://zenodo.org/records/17727354/files/tma_cores_cd3_cd8_images.zip", "name": "tma_cores_cd3_cd8_images.zip"}
      ]
    }
  ]
}
JSON

curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d @"$RUN_ROOT/configs/03_fetch_targets.json" \
  "$GALAXY_URL/api/tools/fetch" \
  > "$RUN_ROOT/api/03_upload_fetch_urls.json"

curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/histories/$HISTORY_ID/contents?details=all" \
  > "$RUN_ROOT/api/04_history_contents_after_upload.json"

python3 - <<'PY'
import json
from pathlib import Path

run_root = Path("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup")
created = json.loads((run_root / "api" / "02_create_history_agent_multimodal.json").read_text())
fetch = json.loads((run_root / "api" / "03_upload_fetch_urls.json").read_text())

summary = {
    "history_name": created.get("name", "Agent-Multimodal"),
    "history_id": created.get("id", ""),
    "job_id": (fetch.get("jobs", [{}])[0].get("id") if fetch.get("jobs") else ""),
    "uploads": [
        {
            "name": o.get("name"),
            "id": o.get("id"),
            "hid": o.get("hid"),
            "state": o.get("state"),
            "file_ext": o.get("file_ext"),
        }
        for o in fetch.get("outputs", [])
    ],
}

(run_root / "metadata" / "uploaded_dataset_ids.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
PY
