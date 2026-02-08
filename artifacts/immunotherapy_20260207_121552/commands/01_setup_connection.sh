#!/bin/sh
set -euo pipefail
RUN_ID="$(cat artifacts/latest_run_id.txt)"
set -a
. ./.env
set +a
curl -sS -H "x-api-key: $GALAXY_API_KEY" \
  "$GALAXY_URL/api/users/current" \
  | tee "artifacts/$RUN_ID/api/01_users_current.json"
