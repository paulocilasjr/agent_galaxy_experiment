#!/bin/sh
set -euo pipefail

RUN_ROOT="experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup"
CSV_PATH="experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/datasets/selected_HAM10000_img_metadata_aug.csv"
ZIP_URL="https://zenodo.org/records/18284218/files/selected_HAM10000_img_96_size.zip"
HISTORY_NAME="agent-image_learner"

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
  > "$RUN_ROOT/api/02_create_history_agent_image_learner.json"

HISTORY_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$RUN_ROOT/api/02_create_history_agent_image_learner.json")"
printf '%s\n' "$HISTORY_ID" > "$RUN_ROOT/metadata/history_id.txt"

curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  -F "history_id=$HISTORY_ID" \
  -F "tool_id=upload1" \
  -F "files_0|NAME=selected_HAM10000_img_metadata_aug.csv" \
  -F "files_0|type=upload_dataset" \
  -F "files_0|file_data=@$CSV_PATH" \
  "$GALAXY_URL/api/tools" \
  > "$RUN_ROOT/api/03_upload_metadata_csv.json"

cat > "$RUN_ROOT/configs/03_fetch_zip_upload_payload.json" <<JSON
{
  "history_id": "$HISTORY_ID",
  "targets": [
    {
      "destination": {"type": "hdas", "id": "$HISTORY_ID"},
      "elements": [
        {
          "src": "url",
          "url": "$ZIP_URL",
          "name": "selected_HAM10000_img_96_size.zip"
        }
      ]
    }
  ]
}
JSON

curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d @"$RUN_ROOT/configs/03_fetch_zip_upload_payload.json" \
  "$GALAXY_URL/api/tools/fetch" \
  > "$RUN_ROOT/api/04_upload_image_zip_from_url.json"

curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/histories/$HISTORY_ID/contents?details=all" \
  > "$RUN_ROOT/api/05_history_contents_after_upload.json"

python3 - <<'PY'
import json
from pathlib import Path

run_root = Path("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup")

def first_output(path: Path):
    data = json.loads(path.read_text())
    outputs = data.get("outputs", [])
    if not outputs:
        return {"id": "", "hid": "", "state": ""}
    out = outputs[0]
    return {
        "id": out.get("id", ""),
        "hid": out.get("hid", ""),
        "state": out.get("state", ""),
    }

csv_out = first_output(run_root / "api/03_upload_metadata_csv.json")
zip_out = first_output(run_root / "api/04_upload_image_zip_from_url.json")
history = json.loads((run_root / "api/02_create_history_agent_image_learner.json").read_text())

summary = {
    "history_name": "agent-image_learner",
    "history_id": history.get("id", ""),
    "uploads": {
        "metadata_csv": csv_out,
        "image_zip_from_url": zip_out,
    },
}

(run_root / "metadata/uploaded_dataset_ids.json").write_text(json.dumps(summary, indent=2) + "\n")
PY

echo "History created and uploads submitted:"
cat "$RUN_ROOT/metadata/uploaded_dataset_ids.json"
