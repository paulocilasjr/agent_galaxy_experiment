#!/bin/sh
set -euo pipefail

RUN_ROOT="experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup"
TOOL_ID="toolshed.g2.bx.psu.edu/repos/goeckslab/image_learner/image_learner/0.1.5"

if [ -f "$RUN_ROOT/api/31_image_learner_run_submit_flattened_conditionals.json" ] && [ "${FORCE_RERUN:-0}" != "1" ]; then
  echo "Flattened-conditionals submission artifact already exists at $RUN_ROOT/api/31_image_learner_run_submit_flattened_conditionals.json"
  echo "Set FORCE_RERUN=1 to intentionally submit another attempt."
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
        "task_selection|__current_case__": 1,
        "task_selection|task": "classification",
        "task_selection|validation_metric_multiclass": "",
        "column_override|__current_case__": 0,
        "column_override|override_columns": "true",
        "column_override|target_column": "3",
        "column_override|image_column": "8",
        "sample_id_column": "1",
        "model_name": "caformer_s18_384",
        "scratch_fine_tune|__current_case__": 0,
        "scratch_fine_tune|use_pretrained": "true",
        "scratch_fine_tune|fine_tune": "true",
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
        "advanced_settings|__current_case__": 0,
        "advanced_settings|customize_defaults": "true",
        "advanced_settings|epochs": 30,
        "advanced_settings|early_stop": 30
    }
}

(run_root / "configs" / "04c_image_learner_request_flattened_conditionals.json").write_text(json.dumps(payload, indent=2) + "\n")
PY

curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d @"$RUN_ROOT/configs/04c_image_learner_request_flattened_conditionals.json" \
  "$GALAXY_URL/api/tools" \
  > "$RUN_ROOT/api/31_image_learner_run_submit_flattened_conditionals.json"

python3 - <<'PY'
import json
from pathlib import Path

run_root = Path("experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup")
submit = json.loads((run_root / "api" / "31_image_learner_run_submit_flattened_conditionals.json").read_text())

if isinstance(submit, dict) and submit.get("err_msg"):
    raise SystemExit(f"Image Learner flattened submission failed: {submit.get('err_msg')}")

summary = {
    "job_id": submit.get("jobs", [{}])[0].get("id") if submit.get("jobs") else "",
    "model_id": submit.get("outputs", [{}])[0].get("id") if submit.get("outputs") else "",
    "report_id": submit.get("outputs", [{}, {}])[1].get("id") if len(submit.get("outputs", [])) > 1 else "",
    "collection_id": submit.get("output_collections", [{}])[0].get("id") if submit.get("output_collections") else "",
}
print(json.dumps(summary, indent=2))
PY
