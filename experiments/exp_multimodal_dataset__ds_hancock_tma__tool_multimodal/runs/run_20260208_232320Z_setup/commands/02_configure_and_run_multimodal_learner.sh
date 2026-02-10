#!/bin/sh
set -euo pipefail

RUN_ROOT="experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup"
TOOL_ID="toolshed.g2.bx.psu.edu/repos/goeckslab/multimodal_learner/multimodal_learner/0.1.5"

if [ -f "$RUN_ROOT/api/25_multimodal_learner_submit.json" ] && [ "${FORCE_RERUN:-0}" != "1" ]; then
  echo "Submission artifact already exists at $RUN_ROOT/api/25_multimodal_learner_submit.json"
  echo "Set FORCE_RERUN=1 to intentionally submit another Multimodal Learner job."
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

run_root = Path("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup")
meta = json.loads((run_root / "metadata" / "uploaded_dataset_ids.json").read_text())

history_id = meta["history_id"]
train_id = next(u["id"] for u in meta["uploads"] if u["name"] == "HANCOCK_train_split.csv")
test_id = next(u["id"] for u in meta["uploads"] if u["name"] == "HANCOCK_test_split.csv")
zip_id = next(u["id"] for u in meta["uploads"] if u["name"] == "tma_cores_cd3_cd8_images.zip")

payload = {
    "history_id": history_id,
    "tool_id": "toolshed.g2.bx.psu.edu/repos/goeckslab/multimodal_learner/multimodal_learner/0.1.5",
    "inputs": {
        "input_csv": {"src": "hda", "id": train_id},
        "target_column": "3",

        "sample_id_selector|__current_case__": 0,
        "sample_id_selector|use_sample_id": "yes",
        "sample_id_selector|sample_id_column": "1",

        "test_dataset_conditional|__current_case__": 0,
        "test_dataset_conditional|has_test_dataset": True,
        "test_dataset_conditional|input_test": {"src": "hda", "id": test_id},

        "backbone_text": "microsoft/deberta-v3-base",

        "use_images_conditional|__current_case__": 0,
        "use_images_conditional|use_images": True,
        "use_images_conditional|images_zip_repeat": [
            {"images_zip": {"src": "hda", "id": zip_id}}
        ],
        "use_images_conditional|images_zip_repeat_0|images_zip": {"src": "hda", "id": zip_id},
        "use_images_conditional|backbone_image": "swin_base_patch4_window7_224.ms_in22k_ft_in1k",
        "use_images_conditional|missing_image_strategy": True,

        "preset": "medium_quality",
        "eval_metric": "roc_auc",
        "random_seed": 42,
        "time_limit": 7200,
        "deterministic": True,

        "customize_defaults_conditional|__current_case__": 1,
        "customize_defaults_conditional|customize_defaults": False
    },
}

(run_root / "configs" / "04_multimodal_learner_request.json").write_text(json.dumps(payload, indent=2) + "\n")
PY

curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d @"$RUN_ROOT/configs/04_multimodal_learner_request.json" \
  "$GALAXY_URL/api/tools" \
  > "$RUN_ROOT/api/25_multimodal_learner_submit.json"

python3 - <<'PY'
import json
from pathlib import Path

run_root = Path("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup")
submit = json.loads((run_root / "api" / "25_multimodal_learner_submit.json").read_text())

if isinstance(submit, dict) and submit.get("err_msg"):
    raise SystemExit(f"Multimodal Learner submit failed: {submit.get('err_msg')}")

meta = {
    "tool_id": "toolshed.g2.bx.psu.edu/repos/goeckslab/multimodal_learner/multimodal_learner/0.1.5",
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

(run_root / "metadata" / "multimodal_learner_execution_ids.json").write_text(json.dumps(meta, indent=2) + "\n")
print(json.dumps(meta, indent=2))
PY
