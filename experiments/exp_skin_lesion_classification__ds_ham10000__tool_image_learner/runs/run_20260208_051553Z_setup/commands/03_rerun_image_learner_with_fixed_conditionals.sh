#!/bin/sh
set -euo pipefail

RUN_ROOT="experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup"
TOOL_ID="toolshed.g2.bx.psu.edu/repos/goeckslab/image_learner/image_learner/0.1.5"

if [ -f "$RUN_ROOT/api/18_image_learner_run_submit_fixed_conditionals.json" ] && [ "${FORCE_RERUN:-0}" != "1" ]; then
  echo "Fixed-conditionals submission artifact already exists at $RUN_ROOT/api/18_image_learner_run_submit_fixed_conditionals.json"
  echo "Set FORCE_RERUN=1 to intentionally submit another Image Learner fixed job."
  exit 1
fi

mkdir -p "$RUN_ROOT/configs" "$RUN_ROOT/api" "$RUN_ROOT/metadata"

set -a
. ./.env
set +a

: "${GALAXY_URL:?Missing GALAXY_URL in .env}"
: "${GALAXY_API_KEY:?Missing GALAXY_API_KEY in .env}"

python3 - <<'PY'
import json
from pathlib import Path

run_root = Path("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup")
meta = json.loads((run_root / "metadata" / "uploaded_dataset_ids.json").read_text())

history_id = meta["history_id"]
csv_id = meta["uploads"]["metadata_csv"]["id"]
zip_id = meta["uploads"]["image_zip_from_url"]["id"]

payload = {
    "history_id": history_id,
    "tool_id": "toolshed.g2.bx.psu.edu/repos/goeckslab/image_learner/image_learner/0.1.5",
    "inputs": {
        "input_csv": {"src": "hda", "id": csv_id},
        "image_zip": {"src": "hda", "id": zip_id},
        "task_selection": {
            "__current_case__": 1,
            "task": "classification",
            "validation_metric_multiclass": ""
        },
        "column_override": {
            "__current_case__": 0,
            "override_columns": "true",
            "target_column": "3",
            "image_column": "8"
        },
        "sample_id_column": "1",
        "model_name": "caformer_s18_384",
        "scratch_fine_tune": {
            "__current_case__": 0,
            "use_pretrained": "true",
            "fine_tune": "true"
        },
        "image_resize": "384x384",
        "augmentation": [
            "random_horizontal_flip",
            "random_vertical_flip",
            "random_rotate",
            "random_blur",
            "random_brightness",
            "random_contrast"
        ],
        "random_seed": 42,
        "advanced_settings": {
            "__current_case__": 0,
            "customize_defaults": "true",
            "epochs": 30,
            "early_stop": 30
        }
    }
}

(run_root / "configs" / "04b_image_learner_request_fixed_conditionals.json").write_text(json.dumps(payload, indent=2) + "\n")
PY

curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d @"$RUN_ROOT/configs/04b_image_learner_request_fixed_conditionals.json" \
  "$GALAXY_URL/api/tools" \
  > "$RUN_ROOT/api/18_image_learner_run_submit_fixed_conditionals.json"

python3 - <<'PY'
import json
from pathlib import Path

run_root = Path("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup")
submit = json.loads((run_root / "api" / "18_image_learner_run_submit_fixed_conditionals.json").read_text())

if isinstance(submit, dict) and submit.get("err_msg"):
    raise SystemExit(f"Image Learner fixed submission failed: {submit.get('err_msg')}")

meta = {
    "tool_id": "toolshed.g2.bx.psu.edu/repos/goeckslab/image_learner/image_learner/0.1.5",
    "attempt": "attempt_2_fixed_conditionals",
    "job": submit.get("jobs", [{}])[0] if submit.get("jobs") else {},
    "outputs": [
        {
            "name": o.get("name"),
            "id": o.get("id"),
            "hid": o.get("hid"),
            "state": o.get("state"),
            "file_ext": o.get("file_ext"),
        }
        for o in submit.get("outputs", [])
    ],
    "output_collections": [
        {
            "name": c.get("name"),
            "id": c.get("id"),
            "hid": c.get("hid"),
            "collection_type": c.get("collection_type"),
        }
        for c in submit.get("output_collections", [])
    ],
}
(run_root / "metadata" / "image_learner_execution_ids.json").write_text(json.dumps(meta, indent=2) + "\n")
print(json.dumps(meta, indent=2))
PY

JOB_ID="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/metadata/image_learner_execution_ids.json"))["job"]["id"])
PY
)"
MODEL_ID="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/metadata/image_learner_execution_ids.json"))["outputs"][0]["id"])
PY
)"
REPORT_ID="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/metadata/image_learner_execution_ids.json"))["outputs"][1]["id"])
PY
)"
COLL_ID="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/metadata/image_learner_execution_ids.json"))["output_collections"][0]["id"])
PY
)"
HISTORY_ID="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/metadata/uploaded_dataset_ids.json"))["history_id"])
PY
)"

curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/jobs/$JOB_ID?full=true" \
  > "$RUN_ROOT/api/19_image_learner_job_status_fixed_poll_1.json"
curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$MODEL_ID" \
  > "$RUN_ROOT/api/20_output_model_status_fixed_poll_1.json"
curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$REPORT_ID" \
  > "$RUN_ROOT/api/21_output_report_status_fixed_poll_1.json"
curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/histories/$HISTORY_ID/contents/dataset_collections/$COLL_ID" \
  > "$RUN_ROOT/api/22_output_collection_status_fixed_poll_1.json"

python3 - <<'PY'
import json
from pathlib import Path

root = Path("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/api")
job = json.loads((root / "19_image_learner_job_status_fixed_poll_1.json").read_text())
model = json.loads((root / "20_output_model_status_fixed_poll_1.json").read_text())
report = json.loads((root / "21_output_report_status_fixed_poll_1.json").read_text())
print("job_state", job.get("state"))
print("model_state", model.get("state"))
print("report_state", report.get("state"))
PY
