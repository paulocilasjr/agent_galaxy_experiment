#!/bin/sh
set -euo pipefail

RUN_ROOT="experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup"
POLL_SECONDS="${POLL_SECONDS:-30}"
MAX_POLLS="${MAX_POLLS:-240}"

mkdir -p "$RUN_ROOT/api" "$RUN_ROOT/outputs" "$RUN_ROOT/metadata"

set -a
. ./.env
set +a

: "${GALAXY_URL:?Missing GALAXY_URL in .env}"
: "${GALAXY_API_KEY:?Missing GALAXY_API_KEY in .env}"

JOB_ID="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/metadata/multimodal_learner_execution_ids.json"))["job"]["id"])
PY
)"

REPORT_ID="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/metadata/multimodal_learner_execution_ids.json"))["outputs"][0]["id"])
PY
)"
YAML_ID="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/metadata/multimodal_learner_execution_ids.json"))["outputs"][1]["id"])
PY
)"
JSON_ID="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/metadata/multimodal_learner_execution_ids.json"))["outputs"][2]["id"])
PY
)"

poll=1
final_state=""
last_poll_file=""
while [ "$poll" -le "$MAX_POLLS" ]; do
  OUT="$RUN_ROOT/api/40_multimodal_job_status_poll_${poll}.json"
  curl -sS -H "x-api-key: $GALAXY_API_KEY" \
    "$GALAXY_URL/api/jobs/$JOB_ID?full=true" \
    > "$OUT"

  state="$(python3 - <<'PY' "$OUT"
import json,sys
print(json.load(open(sys.argv[1])).get("state",""))
PY
)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$now poll=$poll job_state=$state"
  final_state="$state"
  last_poll_file="$OUT"

  case "$state" in
    ok|error|failed|deleted|stopped)
      break
      ;;
  esac

  poll=$((poll+1))
  sleep "$POLL_SECONDS"
done

curl -sS -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/datasets/$REPORT_ID" > "$RUN_ROOT/api/41_report_status_final.json"
curl -sS -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/datasets/$YAML_ID" > "$RUN_ROOT/api/42_config_status_final.json"
curl -sS -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/datasets/$JSON_ID" > "$RUN_ROOT/api/43_metrics_status_final.json"

report_state="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/api/41_report_status_final.json")).get("state",""))
PY
)"
yaml_state="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/api/42_config_status_final.json")).get("state",""))
PY
)"
json_state="$(python3 - <<'PY'
import json
print(json.load(open("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/api/43_metrics_status_final.json")).get("state",""))
PY
)"

# Download outputs regardless of state to preserve diagnostics.
curl -sS -L -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$REPORT_ID/display?to_ext=html" \
  -o "$RUN_ROOT/outputs/multimodal_report.html"
curl -sS -L -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$YAML_ID/display?to_ext=yaml" \
  -o "$RUN_ROOT/outputs/multimodal_training_config.yaml"
curl -sS -L -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$JSON_ID/display?to_ext=json" \
  -o "$RUN_ROOT/outputs/multimodal_metric_results.json"

python3 - <<'PY'
import json
from pathlib import Path

run_root = Path("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup")
polls = sorted(run_root.glob("api/40_multimodal_job_status_poll_*.json"))
job_state = ""
if polls:
    job_state = json.loads(polls[-1].read_text()).get("state", "")
summary = {
    "job_state": job_state,
    "report_state": json.loads((run_root / "api" / "41_report_status_final.json").read_text()).get("state", ""),
    "config_state": json.loads((run_root / "api" / "42_config_status_final.json").read_text()).get("state", ""),
    "metrics_state": json.loads((run_root / "api" / "43_metrics_status_final.json").read_text()).get("state", ""),
    "outputs": {
        "report_html": "outputs/multimodal_report.html",
        "training_config_yaml": "outputs/multimodal_training_config.yaml",
        "metric_results_json": "outputs/multimodal_metric_results.json",
    },
}
(run_root / "metadata" / "multimodal_outputs_download_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
PY
