#!/bin/sh
set -eu
python3 - <<'PY'
import json
import time
from pathlib import Path
from datetime import datetime, timezone
import requests

root = Path('IWC_ChIP-seq Analysis')
api_dir = root / 'api'
meta_dir = root / 'metadata'
api_dir.mkdir(parents=True, exist_ok=True)
meta_dir.mkdir(parents=True, exist_ok=True)

# Load env
env = {}
for raw in Path('.env').read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    k, v = line.split('=', 1)
    env[k.strip()] = v.strip().strip('"').strip("'")

base = env.get('GALAXY_URL', 'https://usegalaxy.org').rstrip('/')
key = env.get('GALAXY_API_KEY')
if not key:
    raise SystemExit('GALAXY_API_KEY missing in .env')
headers = {'x-api-key': key}

def save_json(name: str, obj):
    (api_dir / name).write_text(json.dumps(obj, indent=2, sort_keys=True))

# 0) Validate user
r = requests.get(f'{base}/api/users/current', headers=headers, timeout=60)
r.raise_for_status()
user = r.json()
save_json('01_users_current.json', user)

# 1) Create history
stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%SZ')
history_name = f'IWC_ChIP-seq-local-ga-{stamp}'
r = requests.post(f'{base}/api/histories', headers=headers, json={'name': history_name}, timeout=60)
r.raise_for_status()
history = r.json()
save_json('02_create_history_local_ga.json', history)
history_id = history['id']

# 2) Upload URLs via fetch
read1_url = 'https://zenodo.org/record/1324070/files/wt_H3K4me3_read1.fastq.gz'
read2_url = 'https://zenodo.org/record/1324070/files/wt_H3K4me3_read2.fastq.gz'
fetch_payload = {
    'history_id': history_id,
    'targets': [{
        'destination': {'type': 'hdas'},
        'elements': [
            {'src': 'url', 'url': read1_url, 'ext': 'fastqsanger.gz', 'dbkey': '?'},
            {'src': 'url', 'url': read2_url, 'ext': 'fastqsanger.gz', 'dbkey': '?'},
        ],
    }],
}
(root / 'configs' / '02_fetch_payload_local_ga.json').write_text(json.dumps(fetch_payload, indent=2, sort_keys=True))
r = requests.post(f'{base}/api/tools/fetch', headers=headers, json=fetch_payload, timeout=120)
r.raise_for_status()
fetch_resp = r.json()
save_json('03_upload_fastq_urls_fetch.json', fetch_resp)
dataset_ids = [o['id'] for o in fetch_resp.get('outputs', [])]

# Poll dataset states
dataset_details = {}
for poll in range(1, 61):
    all_done = True
    poll_snap = {'poll': poll, 'datasets': []}
    for did in dataset_ids:
        d = requests.get(f'{base}/api/histories/{history_id}/contents/{did}', headers=headers, timeout=60).json()
        dataset_details[did] = d
        poll_snap['datasets'].append({'id': did, 'name': d.get('name'), 'state': d.get('state')})
        if d.get('state') not in ('ok', 'error', 'failed_metadata'):
            all_done = False
    save_json(f'04_upload_poll_{poll:02d}.json', poll_snap)
    if all_done:
        break
    time.sleep(5)

# Map read1/read2 by name
name_to_id = {d.get('name'): did for did, d in dataset_details.items()}
read1_id = next((did for did, d in dataset_details.items() if (d.get('name') or '').endswith('read1.fastq.gz')), dataset_ids[0])
read2_id = next((did for did, d in dataset_details.items() if (d.get('name') or '').endswith('read2.fastq.gz')), dataset_ids[1])

# 3) Create list:paired collection
collection_payload = {
    'history_id': history_id,
    'collection_type': 'list:paired',
    'name': 'wt_H3K4me3_reads_list_paired_local_ga',
    'element_identifiers': [
        {
            'name': 'wt_H3K4me3',
            'src': 'new_collection',
            'collection_type': 'paired',
            'element_identifiers': [
                {'name': 'forward', 'src': 'hda', 'id': read1_id},
                {'name': 'reverse', 'src': 'hda', 'id': read2_id},
            ],
        }
    ],
}
(root / 'configs' / '03_collection_payload_local_ga.json').write_text(json.dumps(collection_payload, indent=2, sort_keys=True))
r = requests.post(f'{base}/api/dataset_collections', headers=headers, json=collection_payload, timeout=120)
r.raise_for_status()
collection = r.json()
save_json('05_create_paired_collection_local_ga.json', collection)
collection_id = collection['id']

# 4) Import local workflow file
local_wf = json.loads((root / 'configs' / 'chipseq-pe.ga').read_text())
import_payload = {'workflow': local_wf}
(root / 'configs' / '04_import_local_workflow_payload.json').write_text(json.dumps(import_payload, indent=2, sort_keys=True))
r = requests.post(f'{base}/api/workflows', headers=headers, json=import_payload, timeout=120)
r.raise_for_status()
imported = r.json()
save_json('06_import_local_workflow.json', imported)
local_workflow_id = imported['id']

# 5) Invoke local workflow
invoke_payload = {
    'history': f'hist_id={history_id}',
    'inputs_by': 'name',
    'inputs': {
        'PE fastq input': {'src': 'hdca', 'id': collection_id},
        'adapter_forward': 'AGATCGGAAGAGCACACGTCTGAACTCCAGTCAC',
        'adapter_reverse': 'AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT',
        'reference_genome': 'mm10',
        'effective_genome_size': 1870000000,
        'normalize_profile': True,
    },
}
(root / 'configs' / '05_invoke_local_workflow_payload.json').write_text(json.dumps(invoke_payload, indent=2, sort_keys=True))
r = requests.post(f'{base}/api/workflows/{local_workflow_id}/invocations', headers=headers, json=invoke_payload, timeout=120)
r.raise_for_status()
inv = r.json()
save_json('07_invoke_local_workflow.json', inv)
local_invocation_id = inv['id']

# 6) Poll invocation/jobs summary/history until terminal or timeout
terminal = False
last_inv = None
last_jobs_summary = None
for poll in range(1, 181):
    inv_obj = requests.get(f'{base}/api/invocations/{local_invocation_id}', headers=headers, timeout=60).json()
    jobs_summary = requests.get(f'{base}/api/invocations/{local_invocation_id}/jobs_summary', headers=headers, timeout=60).json()
    hist = requests.get(f'{base}/api/histories/{history_id}', headers=headers, timeout=60).json()
    snap = {
        'poll': poll,
        'invocation_state': inv_obj.get('state'),
        'invocation_steps': len(inv_obj.get('steps', [])),
        'jobs_summary': jobs_summary,
        'history_state_ids': hist.get('state_ids'),
    }
    save_json(f'08_local_invocation_poll_{poll:03d}.json', snap)
    last_inv = inv_obj
    last_jobs_summary = jobs_summary

    states = jobs_summary.get('states', {}) or {}
    running = states.get('running', 0) + states.get('queued', 0) + states.get('new', 0) + states.get('waiting', 0)
    errored = states.get('error', 0) + states.get('failed', 0)
    ok = states.get('ok', 0)
    if running == 0 and (ok > 0 or errored > 0):
        terminal = True
        break
    time.sleep(10)

# Save final request/report/details
req = requests.get(f'{base}/api/invocations/{local_invocation_id}/request', headers=headers, timeout=60).json()
rep = requests.get(f'{base}/api/invocations/{local_invocation_id}/report', headers=headers, timeout=60).json()
contents = requests.get(f'{base}/api/histories/{history_id}/contents', headers=headers, timeout=120).json()
save_json('09_local_invocation_request.json', req)
save_json('10_local_invocation_report.json', rep)
save_json('11_local_history_contents_final.json', contents)

# Capture detailed step objects
steps_detail = []
for s in (last_inv or {}).get('steps', []):
    sid = s['id']
    d = requests.get(f'{base}/api/invocations/{local_invocation_id}/steps/{sid}', headers=headers, timeout=60).json()
    steps_detail.append(d)
save_json('12_local_invocation_steps_detail.json', steps_detail)

# Persist ids metadata
ids = {
    'galaxy_url': base,
    'history_name_local_ga': history_name,
    'history_id_local_ga': history_id,
    'dataset_ids': dataset_ids,
    'dataset_names': {did: dataset_details.get(did, {}).get('name') for did in dataset_ids},
    'read1_id': read1_id,
    'read2_id': read2_id,
    'collection_id': collection_id,
    'local_workflow_id': local_workflow_id,
    'local_invocation_id': local_invocation_id,
    'invocation_terminal_detected': terminal,
    'last_jobs_summary': last_jobs_summary,
}
(meta_dir / 'local_ga_run_ids.json').write_text(json.dumps(ids, indent=2, sort_keys=True))

print(json.dumps(ids, indent=2, sort_keys=True))
PY
