#!/bin/sh
set -eu
# Create a fresh Galaxy history for hyperparameter-search run and upload Chowell/MSK1 inputs.
python3 - <<'PY'
from pathlib import Path
import csv
import io
import json
import time
import requests

run = Path('experiments/Built_ML_workflow/runs/run_20260218_202848Z_hyperparam_search')
api = run / 'api'; api.mkdir(parents=True, exist_ok=True)
conf = run / 'configs'; conf.mkdir(parents=True, exist_ok=True)
meta = run / 'metadata'; meta.mkdir(parents=True, exist_ok=True)

# Load Galaxy credentials
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

# Capture current user for traceability.
user = requests.get(f'{base}/api/users/current', headers=headers, timeout=60)
user.raise_for_status()
save('01_users_current.json', user.json())

history_name = 'ML_workflow_hyperparam'
hresp = requests.post(f'{base}/api/histories', headers=headers, json={'name': history_name}, timeout=60)
hresp.raise_for_status()
history = hresp.json()
save('02_create_history_ml_workflow_hyperparam.json', history)
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
    'targets': [{
        'destination': {'type': 'hdas'},
        'elements': [{'src': 'url', 'url': u, 'ext': 'tabular', 'dbkey': '?'} for u in urls],
    }],
}
(conf / '02_fetch_payload_upload_tsvs.json').write_text(json.dumps(payload, indent=2, sort_keys=True))
uresp = requests.post(f'{base}/api/tools/fetch', headers=headers, json=payload, timeout=180)
uresp.raise_for_status()
upload = uresp.json()
save('03_upload_fetch_tsvs.json', upload)

ids = [o['id'] for o in upload.get('outputs', [])]
latest = {}
for i in range(1, 121):
    snap = {'poll': i, 'datasets': []}
    done = True
    for did in ids:
        d = requests.get(f'{base}/api/histories/{hid}/contents/{did}', headers=headers, timeout=60)
        d.raise_for_status()
        dj = d.json()
        latest[did] = dj
        snap['datasets'].append({
            'id': did,
            'hid': dj.get('hid'),
            'name': dj.get('name'),
            'state': dj.get('state'),
        })
        if dj.get('state') not in ('ok', 'error', 'failed_metadata'):
            done = False
    save(f'04_upload_poll_{i:03d}.json', snap)
    if done:
        break
    time.sleep(5)

hcontents = requests.get(f'{base}/api/histories/{hid}/contents', headers=headers, params={'details': 'all'}, timeout=120)
hcontents.raise_for_status()
save('05_history_contents_after_upload.json', hcontents.json())

name_to_id = {d.get('name'): did for did, d in latest.items()}

# Infer table shapes from uploaded files.
shape_rows = []
for did in ids:
    d = latest[did]
    name = d.get('name')
    text = requests.get(f'{base}/api/histories/{hid}/contents/{did}/display', headers=headers, timeout=120)
    text.raise_for_status()
    content = text.text
    lines = content.splitlines()
    header = lines[0] if lines else ''
    rows_inferred = max(len(lines) - 1, 0)
    cols_inferred = len(header.split('\t')) if header else 0
    shape_rows.append({
        'dataset_id': did,
        'hid': d.get('hid'),
        'name': name,
        'state': d.get('state'),
        'rows_inferred': rows_inferred,
        'cols_inferred': cols_inferred,
        'header': header,
    })

(meta / 'uploaded_dataset_ids.json').write_text(json.dumps({
    'history_id': hid,
    'history_name': history_name,
    'dataset_ids': ids,
    'name_to_id': name_to_id,
    'shape_rows': shape_rows,
}, indent=2, sort_keys=True))
(meta / 'uploaded_dataset_shapes.json').write_text(json.dumps(shape_rows, indent=2, sort_keys=True))

print('history_id', hid)
print('dataset_ids', ids)
PY
