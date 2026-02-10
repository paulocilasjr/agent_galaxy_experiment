#!/bin/sh
set -euo pipefail

RUN_ROOT="experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup"
REQUEST_JSON="$RUN_ROOT/configs/06_multimodal_learner_request_fix_optimization_override.json"
OUT_JSON="$RUN_ROOT/api/54_multimodal_submit_fix_optimization_override.json"

if [ -f "$OUT_JSON" ] && [ "${FORCE_RERUN:-0}" != "1" ]; then
  echo "Submission artifact already exists at $OUT_JSON"
  echo "Set FORCE_RERUN=1 to intentionally submit again."
  exit 1
fi

set -a
. ./.env
set +a

: "${GALAXY_URL:?Missing GALAXY_URL in .env}"
: "${GALAXY_API_KEY:?Missing GALAXY_API_KEY in .env}"

curl -sS -H "x-api-key: $GALAXY_API_KEY" -H "Content-Type: application/json" \
  -d @"$REQUEST_JSON" \
  "$GALAXY_URL/api/tools" \
  > "$OUT_JSON"

python3 - <<'PY'
import json
from pathlib import Path

out = Path("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/api/54_multimodal_submit_fix_optimization_override.json")
j = json.loads(out.read_text())
if isinstance(j, dict) and j.get("err_msg"):
    raise SystemExit(f"Submit failed: {j.get('err_msg')}")
print("jobs", len(j.get("jobs", [])), "outputs", len(j.get("outputs", [])), "collections", len(j.get("output_collections", [])))
for job in j.get("jobs", []):
    print("job", job.get("id"), "state", job.get("state"))
PY
