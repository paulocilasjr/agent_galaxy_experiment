#!/bin/sh
set -eu
# Recreates history ML_workflow and uploads the five Zenodo TSV inputs.
python3 - <<'PY'
from pathlib import Path
import requests, json, time

run = Path('experiments/Built_ML_workflow/runs/run_20260218_180758Z_setup')
api = run / 'api'; api.mkdir(parents=True, exist_ok=True)
conf = run / 'configs'; conf.mkdir(parents=True, exist_ok=True)
meta = run / 'metadata'; meta.mkdir(parents=True, exist_ok=True)

env = {}
for raw in Path('.env').read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    k, v = line.split('=', 1)
    env[k.strip()] = v.strip().strip('"').strip("'")
base = env.get('GALAXY_URL', 'https://usegalaxy.org').rstrip('/')
headers = {'x-api-key': env['GALAXY_API_KEY']}

def save(name, obj):
    (api / name).write_text(json.dumps(obj, indent=2, sort_keys=True))

history = requests.post(f'{base}/api/histories', headers=headers, json={'name': 'ML_workflow'}, timeout=60).json()
save('02_create_history_ml_workflow.json', history)
hid = history['id']

urls = [
    'https://zenodo.org/records/13885908/files/Chowell_test_No_Response.tsv',
    'https://zenodo.org/records/13885908/files/Chowell_test_Response.tsv',
    'https://zenodo.org/records/13885908/files/Chowell_train_Response.tsv',
    'https://zenodo.org/records/13885908/files/MSK1_No_Response.tsv',
    'https://zenodo.org/records/13885908/files/MSK1_Response.tsv',
]
payload = {
    'history_id': hid,
    'targets': [{'destination': {'type': 'hdas'}, 'elements': [{'src': 'url', 'url': u, 'ext': 'tabular', 'dbkey': '?'} for u in urls]}],
}
(conf / '02_fetch_payload_upload_tsvs.json').write_text(json.dumps(payload, indent=2, sort_keys=True))
fetch = requests.post(f'{base}/api/tools/fetch', headers=headers, json=payload, timeout=120).json()
save('03_upload_fetch_tsvs.json', fetch)

ids = [o['id'] for o in fetch.get('outputs', [])]
final = {}
for i in range(1, 121):
    snap = {'poll': i, 'datasets': []}
    done = True
    for did in ids:
        d = requests.get(f'{base}/api/histories/{hid}/contents/{did}', headers=headers, timeout=60).json()
        final[did] = d
        snap['datasets'].append({'id': did, 'name': d.get('name'), 'state': d.get('state'), 'hid': d.get('hid')})
        if d.get('state') not in ('ok', 'error', 'failed_metadata'):
            done = False
    save(f'04_upload_poll_{i:03d}.json', snap)
    if done:
        break
    time.sleep(5)

(meta / 'uploaded_dataset_ids.json').write_text(json.dumps({'history_id': hid, 'name_to_id': {d.get('name'): did for did, d in final.items()}}, indent=2, sort_keys=True))
print('history_id', hid)
print('dataset_ids', ids)
PY
