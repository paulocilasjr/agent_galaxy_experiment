#!/bin/sh
set -euo pipefail

RUN_ROOT="experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup"
POLL_SECONDS="${POLL_SECONDS:-30}"
MAX_POLLS="${MAX_POLLS:-480}"

mkdir -p "$RUN_ROOT/api" "$RUN_ROOT/outputs" "$RUN_ROOT/metadata"

set -a
. ./.env
set +a

: "${GALAXY_URL:?Missing GALAXY_URL in .env}"
: "${GALAXY_API_KEY:?Missing GALAXY_API_KEY in .env}"

read -r ATTEMPT_KEY ATTEMPT_TAG JOB_ID REPORT_ID YAML_ID JSON_ID <<EOF
$(python3 - <<'PY'
import json
import re
from pathlib import Path

meta_path = Path("experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/metadata/multimodal_learner_execution_ids.json")
meta = json.loads(meta_path.read_text())

attempt_key = meta.get("latest_attempt", "")
record = meta.get(attempt_key, {}) if attempt_key else {}

# Backward compatibility with older metadata shape.
if not record and "job" in meta:
    attempt_key = "legacy_attempt"
    record = {
        "job_id": meta["job"]["id"],
        "outputs": meta.get("outputs", []),
    }

if not record:
    raise SystemExit("No runnable attempt found in multimodal_learner_execution_ids.json")

attempt_tag = re.sub(r"[^A-Za-z0-9_.-]+", "_", attempt_key) or "latest"
outputs = record.get("outputs", [])
if len(outputs) < 3:
    raise SystemExit(f"Expected 3 outputs for attempt {attempt_key}, got {len(outputs)}")

print(
    attempt_key,
    attempt_tag,
    record.get("job_id", ""),
    outputs[0].get("id", ""),
    outputs[1].get("id", ""),
    outputs[2].get("id", ""),
)
PY
)
EOF

if [ -z "$JOB_ID" ] || [ -z "$REPORT_ID" ] || [ -z "$YAML_ID" ] || [ -z "$JSON_ID" ]; then
  echo "Missing IDs for latest attempt in metadata/multimodal_learner_execution_ids.json"
  exit 1
fi

echo "Monitoring attempt: $ATTEMPT_KEY (job=$JOB_ID)"

poll=1
final_state=""
last_poll_file=""
while [ "$poll" -le "$MAX_POLLS" ]; do
  OUT="$RUN_ROOT/api/60_multimodal_job_status_${ATTEMPT_TAG}_poll_${poll}.json"
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

curl -sS -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/datasets/$REPORT_ID" > "$RUN_ROOT/api/61_report_status_${ATTEMPT_TAG}_final.json"
curl -sS -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/datasets/$YAML_ID" > "$RUN_ROOT/api/62_config_status_${ATTEMPT_TAG}_final.json"
curl -sS -H "x-api-key: $GALAXY_API_KEY" "$GALAXY_URL/api/datasets/$JSON_ID" > "$RUN_ROOT/api/63_metrics_status_${ATTEMPT_TAG}_final.json"

report_state="$(python3 - <<'PY' "$RUN_ROOT" "$ATTEMPT_TAG"
import json,sys
run_root, tag = sys.argv[1], sys.argv[2]
print(json.load(open(f"{run_root}/api/61_report_status_{tag}_final.json")).get("state",""))
PY
)"
yaml_state="$(python3 - <<'PY' "$RUN_ROOT" "$ATTEMPT_TAG"
import json,sys
run_root, tag = sys.argv[1], sys.argv[2]
print(json.load(open(f"{run_root}/api/62_config_status_{tag}_final.json")).get("state",""))
PY
)"
json_state="$(python3 - <<'PY' "$RUN_ROOT" "$ATTEMPT_TAG"
import json,sys
run_root, tag = sys.argv[1], sys.argv[2]
print(json.load(open(f"{run_root}/api/63_metrics_status_{tag}_final.json")).get("state",""))
PY
)"

# Download outputs regardless of state to preserve diagnostics.
curl -sS -L -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$REPORT_ID/display?to_ext=html" \
  -o "$RUN_ROOT/outputs/multimodal_report_${ATTEMPT_TAG}.html"
curl -sS -L -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$YAML_ID/display?to_ext=yaml" \
  -o "$RUN_ROOT/outputs/multimodal_training_config_${ATTEMPT_TAG}.yaml"
curl -sS -L -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/datasets/$JSON_ID/display?to_ext=json" \
  -o "$RUN_ROOT/outputs/multimodal_metric_results_${ATTEMPT_TAG}.json"

# Keep canonical filenames pointing to latest attempt.
cp "$RUN_ROOT/outputs/multimodal_report_${ATTEMPT_TAG}.html" "$RUN_ROOT/outputs/multimodal_report.html"
cp "$RUN_ROOT/outputs/multimodal_training_config_${ATTEMPT_TAG}.yaml" "$RUN_ROOT/outputs/multimodal_training_config.yaml"
cp "$RUN_ROOT/outputs/multimodal_metric_results_${ATTEMPT_TAG}.json" "$RUN_ROOT/outputs/multimodal_metric_results.json"

python3 - <<'PY' "$RUN_ROOT" "$ATTEMPT_KEY" "$ATTEMPT_TAG" "$JOB_ID" "$final_state" "$report_state" "$yaml_state" "$json_state" "$last_poll_file"
import json
import sys
from pathlib import Path

run_root = Path(sys.argv[1])
attempt_key = sys.argv[2]
attempt_tag = sys.argv[3]
job_id = sys.argv[4]
job_state = sys.argv[5]
report_state = sys.argv[6]
config_state = sys.argv[7]
metrics_state = sys.argv[8]
last_poll_file = sys.argv[9]

summary = {
    "attempt_key": attempt_key,
    "attempt_tag": attempt_tag,
    "job_id": job_id,
    "job_state": job_state,
    "report_state": report_state,
    "config_state": config_state,
    "metrics_state": metrics_state,
    "last_job_poll_file": str(Path(last_poll_file).relative_to(run_root)),
    "outputs": {
        "report_html": f"outputs/multimodal_report_{attempt_tag}.html",
        "training_config_yaml": f"outputs/multimodal_training_config_{attempt_tag}.yaml",
        "metric_results_json": f"outputs/multimodal_metric_results_{attempt_tag}.json",
        "canonical_report_html": "outputs/multimodal_report.html",
        "canonical_training_config_yaml": "outputs/multimodal_training_config.yaml",
        "canonical_metric_results_json": "outputs/multimodal_metric_results.json",
    },
}

(run_root / "metadata" / "multimodal_outputs_download_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
(run_root / "metadata" / f"multimodal_outputs_download_summary_{attempt_tag}.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
PY
