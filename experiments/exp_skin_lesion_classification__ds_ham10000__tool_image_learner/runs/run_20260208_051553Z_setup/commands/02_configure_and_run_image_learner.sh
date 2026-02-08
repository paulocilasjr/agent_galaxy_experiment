#!/bin/sh
set -euo pipefail

# Historical note:
# This initial submission script is preserved for provenance.
# It does not set conditional `__current_case__` fields and therefore can
# produce the default label-column behavior in this tool version.

RUN_ROOT="experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup"
TOOL_ID="toolshed.g2.bx.psu.edu/repos/goeckslab/image_learner/image_learner/0.1.5"

if [ -f "$RUN_ROOT/api/10_image_learner_run_submit.json" ] && [ "${FORCE_RERUN:-0}" != "1" ]; then
  echo "Submission artifact already exists at $RUN_ROOT/api/10_image_learner_run_submit.json"
  echo "Set FORCE_RERUN=1 to intentionally submit another Image Learner job."
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
            "task": "classification",
            "validation_metric_multiclass": ""
        },
        "column_override": {
            "override_columns": "true",
            "target_column": "3",
            "image_column": "8"
        },
        "sample_id_column": "1",
        "model_name": "caformer_s18_384",
        "scratch_fine_tune": {
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
            "customize_defaults": "true",
            "epochs": 30,
            "early_stop": 30
        }
    }
}

(run_root / "configs" / "04_image_learner_request.json").write_text(json.dumps(payload, indent=2) + "\n")
PY

curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d @"$RUN_ROOT/configs/04_image_learner_request.json" \
  "$GALAXY_URL/api/tools" \
  > "$RUN_ROOT/api/10_image_learner_run_submit.json"

python3 - <<'PY'
import json
from pathlib import Path

run_root = Path("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup")
submit = json.loads((run_root / "api" / "10_image_learner_run_submit.json").read_text())

if isinstance(submit, dict) and submit.get("err_msg"):
    raise SystemExit(f"Image Learner submit failed: {submit.get('err_msg')}")

meta = {
    "tool_id": "toolshed.g2.bx.psu.edu/repos/goeckslab/image_learner/image_learner/0.1.5",
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
outs=json.load(open("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/metadata/image_learner_execution_ids.json"))["outputs"]
print(outs[0]["id"])
PY
)"
REPORT_ID="$(python3 - <<'PY'
import json
outs=json.load(open("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/metadata/image_learner_execution_ids.json"))["outputs"]
print(outs[1]["id"])
PY
)"
HISTORY_ID="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/metadata/uploaded_dataset_ids.json"))["history_id"])
PY
)"

curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/jobs/$JOB_ID?full=true" \
  > "$RUN_ROOT/api/11_image_learner_job_status_poll_1.json"
curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$MODEL_ID" \
  > "$RUN_ROOT/api/12_output_model_status_poll_1.json"
curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$REPORT_ID" \
  > "$RUN_ROOT/api/13_output_report_status_poll_1.json"
curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/histories/$HISTORY_ID/contents?details=all" \
  > "$RUN_ROOT/api/14_history_contents_after_image_learner_submit.json"

python3 - <<'PY'
import json
from pathlib import Path

root = Path("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/api")
job = json.loads((root / "11_image_learner_job_status_poll_1.json").read_text())
model = json.loads((root / "12_output_model_status_poll_1.json").read_text())
report = json.loads((root / "13_output_report_status_poll_1.json").read_text())
print("job_state", job.get("state"))
print("model_state", model.get("state"))
print("report_state", report.get("state"))
PY
