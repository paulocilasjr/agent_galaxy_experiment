#!/bin/sh
set -eu
python3 - <<'PY'
import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

root = Path('experiments/IWC_ATAC-seq_Workflow')
api_dir = root / 'api'
cfg_dir = root / 'configs'
meta_dir = root / 'metadata'
out_dir = root / 'outputs'
for d in (api_dir, cfg_dir, meta_dir, out_dir):
    d.mkdir(parents=True, exist_ok=True)

# Load Galaxy credentials
env = {}
for raw in Path('.env').read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    k, v = line.split('=', 1)
    env[k.strip()] = v.strip().strip('"').strip("'")

base = env.get('GALAXY_URL', 'https://usegalaxy.org').rstrip('/')
api_key = env.get('GALAXY_API_KEY')
if not api_key:
    raise SystemExit('GALAXY_API_KEY missing in .env')
headers = {'x-api-key': api_key}

created_utc = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
(meta_dir / 'created_utc.txt').write_text(created_utc + '\n')

def save_json(path_name: str, obj):
    (api_dir / path_name).write_text(json.dumps(obj, indent=2, sort_keys=True))

def req_json(method: str, url: str, **kwargs):
    r = requests.request(method, url, headers=headers, timeout=120, **kwargs)
    try:
        data = r.json()
    except Exception:
        data = {'raw_text': r.text}
    if not r.ok:
        raise RuntimeError(f'{method} {url} failed ({r.status_code}): {str(data)[:800]}')
    return data

def normalize(s: str) -> str:
    return re.sub(r'[^a-z0-9]+', '', (s or '').lower())

def first_leaf_dataset_id(collection_id: str):
    if not collection_id:
        return None
    col = req_json('GET', f'{base}/api/dataset_collections/{collection_id}')
    elements = col.get('elements') or []
    if not elements:
        return None
    cur = elements[0]
    while True:
        et = cur.get('element_type')
        obj = cur.get('object') or {}
        if et == 'hda':
            return obj.get('id')
        if et == 'dataset_collection':
            cid = obj.get('id')
            if not cid:
                return None
            sub = req_json('GET', f'{base}/api/dataset_collections/{cid}')
            se = sub.get('elements') or []
            if not se:
                return None
            cur = se[0]
            continue
        return None

# 1) User identity
user = req_json('GET', f'{base}/api/users/current')
save_json('01_users_current.json', user)

# 2) Discover published IWC ATAC workflow
wfs = req_json('GET', f'{base}/api/workflows', params={'show_published': 'true', 'skip_step_counts': 'true'})
selected = None
candidates = []
for w in wfs:
    owner = (w.get('owner') or '').lower()
    name = w.get('name') or ''
    if owner != 'iwc':
        continue
    if 'atacseq' in name.lower() or 'atac-seq' in name.lower():
        candidates.append({'id': w.get('id'), 'name': name, 'owner': w.get('owner')})
    if owner == 'iwc' and name == 'ATACseq (release v1.0)':
        selected = w

if selected is None:
    raise RuntimeError('Could not resolve published workflow `ATACseq (release v1.0)` under owner `iwc`')

save_json('02_workflow_candidates.json', {
    'selected': selected,
    'candidate_count': len(candidates),
    'candidates': candidates,
})
shared_workflow_id = selected['id']

# 3) Create history
history_name = 'IWC_ATAC-seq'
history = req_json('POST', f'{base}/api/histories', json={'name': history_name})
save_json('03_create_history.json', history)
history_id = history['id']

# 4) Upload example paired FASTQs
read1_url = 'https://zenodo.org/record/3862793/files/SRR891268_chr22_enriched_R1.fastq.gz'
read2_url = 'https://zenodo.org/record/3862793/files/SRR891268_chr22_enriched_R2.fastq.gz'
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
(cfg_dir / '02_fetch_payload_upload_urls.json').write_text(json.dumps(fetch_payload, indent=2, sort_keys=True))
fetch_resp = req_json('POST', f'{base}/api/tools/fetch', json=fetch_payload)
save_json('04_upload_fastq_urls_fetch.json', fetch_resp)

dataset_ids = [o['id'] for o in fetch_resp.get('outputs', [])]
dataset_details = {}
for poll in range(1, 91):
    all_done = True
    snap = {'poll': poll, 'datasets': []}
    for did in dataset_ids:
        d = req_json('GET', f'{base}/api/histories/{history_id}/contents/{did}')
        dataset_details[did] = d
        snap['datasets'].append({
            'id': did,
            'hid': d.get('hid'),
            'name': d.get('name'),
            'state': d.get('state'),
        })
        if d.get('state') not in ('ok', 'error', 'failed_metadata'):
            all_done = False
    save_json(f'05_upload_poll_{poll:02d}.json', snap)
    if all_done:
        break
    time.sleep(5)

# Resolve uploaded datasets
read1_id = None
read2_id = None
for did, d in dataset_details.items():
    name = (d.get('name') or '').lower()
    if name.endswith('_r1.fastq.gz') or name.endswith('r1.fastq.gz') or 'r1.fastq' in name:
        read1_id = did
    if name.endswith('_r2.fastq.gz') or name.endswith('r2.fastq.gz') or 'r2.fastq' in name:
        read2_id = did
if read1_id is None or read2_id is None:
    if len(dataset_ids) >= 2:
        read1_id, read2_id = dataset_ids[0], dataset_ids[1]
    else:
        raise RuntimeError('Could not resolve R1/R2 dataset IDs')

# 5) Create list:paired collection
collection_payload = {
    'history_id': history_id,
    'collection_type': 'list:paired',
    'name': 'SRR891268_chr22_enriched_list_paired',
    'element_identifiers': [{
        'name': 'SRR891268_chr22_enriched',
        'src': 'new_collection',
        'collection_type': 'paired',
        'element_identifiers': [
            {'name': 'forward', 'src': 'hda', 'id': read1_id},
            {'name': 'reverse', 'src': 'hda', 'id': read2_id},
        ],
    }],
}
(cfg_dir / '03_collection_payload.json').write_text(json.dumps(collection_payload, indent=2, sort_keys=True))
collection = req_json('POST', f'{base}/api/dataset_collections', json=collection_payload)
save_json('06_create_paired_collection.json', collection)
collection_id = collection['id']

# 6) Import selected published workflow into account
import_payload = {'shared_workflow_id': shared_workflow_id}
(cfg_dir / '04_import_published_workflow_payload.json').write_text(json.dumps(import_payload, indent=2, sort_keys=True))
imported = req_json('POST', f'{base}/api/workflows', json=import_payload)
save_json('07_import_published_workflow.json', imported)
workflow_id = imported['id']

# Download imported workflow definition for provenance
wf_download = req_json('GET', f'{base}/api/workflows/{workflow_id}/download')
save_json('08_imported_workflow_download.json', wf_download)
(out_dir / 'ATACseq_release_v1_0_imported.ga').write_text(json.dumps(wf_download, indent=2, sort_keys=True))
(cfg_dir / 'atacseq_release_v1_0_imported.ga').write_text(json.dumps(wf_download, indent=2, sort_keys=True))

# 7) Resolve runtime input labels from workflow definition
steps = wf_download.get('steps', {})
input_like = []
for k, s in steps.items():
    if s.get('type') in ('data_collection_input', 'data_input', 'parameter_input'):
        input_like.append({
            'order': int(k),
            'type': s.get('type'),
            'label': s.get('label') or '',
            'name': s.get('name') or '',
            'inputs': s.get('inputs') or [],
        })
input_like = sorted(input_like, key=lambda x: x['order'])
save_json('09_workflow_runtime_inputs.json', input_like)

label_pool = [x['label'] for x in input_like if x.get('label')]
norm_to_label = {normalize(lbl): lbl for lbl in label_pool}

def pick_label(variants):
    for v in variants:
        nv = normalize(v)
        if nv in norm_to_label:
            return norm_to_label[nv]
    return None

label_fastq = pick_label(['PE fastq input', 'pe fastq input'])
label_ref = pick_label(['reference_genome', 'Reference genome', 'reference genome'])
label_eff = pick_label(['effective_genome_size', 'Effective genome size', 'effective genome size'])
label_bin = pick_label(['bin_size', 'Bin size', 'bin size'])

missing = [
    ('PE fastq input', label_fastq),
    ('reference_genome', label_ref),
    ('effective_genome_size', label_eff),
    ('bin_size', label_bin),
]
missing = [name for name, got in missing if not got]
if missing:
    raise RuntimeError(f'Could not map required runtime inputs from workflow labels. Missing: {missing}; labels available: {label_pool}')

invoke_inputs = {
    label_fastq: {'src': 'hdca', 'id': collection_id},
    label_ref: 'hg19',
    label_eff: 2700000000,
    label_bin: 1000,
}
invoke_payload = {
    'history': f'hist_id={history_id}',
    'inputs_by': 'name',
    'inputs': invoke_inputs,
}
(cfg_dir / '05_invoke_workflow_payload.json').write_text(json.dumps(invoke_payload, indent=2, sort_keys=True))

# 8) Invoke workflow
inv = req_json('POST', f'{base}/api/workflows/{workflow_id}/invocations', json=invoke_payload)
save_json('10_invoke_workflow.json', inv)
invocation_id = inv['id']

# 9) Poll invocation/jobs
last_inv = None
last_jobs = None
for poll in range(1, 301):
    inv_obj = req_json('GET', f'{base}/api/invocations/{invocation_id}')
    jobs = req_json('GET', f'{base}/api/invocations/{invocation_id}/jobs_summary')
    hist = req_json('GET', f'{base}/api/histories/{history_id}')

    snap = {
        'poll': poll,
        'invocation_id': invocation_id,
        'invocation_state': inv_obj.get('state'),
        'invocation_steps': len(inv_obj.get('steps', [])),
        'jobs_summary': jobs,
        'history_state_ids': hist.get('state_ids'),
    }
    save_json(f'11_invocation_poll_{poll:03d}.json', snap)
    last_inv = inv_obj
    last_jobs = jobs

    states = jobs.get('states') or {}
    running = sum(int(states.get(k, 0) or 0) for k in ('new', 'queued', 'running', 'waiting', 'resubmitted'))
    terminal_seen = sum(int(states.get(k, 0) or 0) for k in ('ok', 'error', 'failed', 'deleted', 'paused', 'skipped', 'deleted_new'))
    if running == 0 and terminal_seen > 0:
        break
    time.sleep(10)

# 10) Save final invocation details + history snapshot
inv_req = req_json('GET', f'{base}/api/invocations/{invocation_id}/request')
inv_rep = req_json('GET', f'{base}/api/invocations/{invocation_id}/report')
hist_contents = req_json('GET', f'{base}/api/histories/{history_id}/contents', params={'details': 'all'})
save_json('12_invocation_request.json', inv_req)
save_json('13_invocation_report.json', inv_rep)
save_json('14_history_contents_final.json', hist_contents)

# Step details for audit
steps_detail = []
for s in (last_inv or {}).get('steps', []):
    sid = s.get('id')
    if not sid:
        continue
    d = req_json('GET', f'{base}/api/invocations/{invocation_id}/steps/{sid}')
    steps_detail.append(d)
save_json('15_invocation_steps_detail.json', steps_detail)

# Optional key output collection/dataset extraction
steps_by_label = {s.get('workflow_step_label'): s for s in steps_detail if s.get('workflow_step_label')}

def get_hda_file(did, out_path: Path, binary=False):
    r = requests.get(f'{base}/api/histories/{history_id}/contents/{did}/display', headers=headers, timeout=180)
    r.raise_for_status()
    if binary:
        out_path.write_bytes(r.content)
    else:
        out_path.write_text(r.text)

key_outputs = {
    'mapping_stats_dataset_id': None,
    'narrowpeak_dataset_id': None,
    'multiqc_dataset_id': None,
}

bowtie_step = steps_by_label.get('Bowtie2 map on reference', {})
bowtie_cols = bowtie_step.get('output_collections') or {}
mapping_col = (bowtie_cols.get('mapping_stats') or {}).get('id')
if mapping_col:
    key_outputs['mapping_stats_dataset_id'] = first_leaf_dataset_id(mapping_col)

macs2_step = steps_by_label.get('Call Peaks with MACS2', {})
macs2_cols = macs2_step.get('output_collections') or {}
narrow_col = None
for k, v in macs2_cols.items():
    if 'narrow' in (k or '').lower():
        narrow_col = v.get('id')
        break
if narrow_col:
    key_outputs['narrowpeak_dataset_id'] = first_leaf_dataset_id(narrow_col)

# MultiQC output can be direct hda output on step
multiqc_step = steps_by_label.get('MultiQC', {})
multiqc_outputs = multiqc_step.get('outputs') or {}
if multiqc_outputs:
    # pick first output dataset id from step outputs
    for _name, obj in multiqc_outputs.items():
        did = obj.get('id')
        if did:
            key_outputs['multiqc_dataset_id'] = did
            break

# Download key outputs if present
if key_outputs['mapping_stats_dataset_id']:
    get_hda_file(key_outputs['mapping_stats_dataset_id'], out_dir / 'mapping_stats.txt', binary=False)
if key_outputs['narrowpeak_dataset_id']:
    get_hda_file(key_outputs['narrowpeak_dataset_id'], out_dir / 'macs2_narrowpeak.bed', binary=False)
if key_outputs['multiqc_dataset_id']:
    # likely html; if not, still save text
    get_hda_file(key_outputs['multiqc_dataset_id'], out_dir / 'multiqc_report.html', binary=False)

(meta_dir / 'run_ids.json').write_text(json.dumps({
    'galaxy_url': base,
    'created_utc': created_utc,
    'history_name': history_name,
    'history_id': history_id,
    'shared_workflow_id': shared_workflow_id,
    'imported_workflow_id': workflow_id,
    'imported_workflow_name': imported.get('name'),
    'invocation_id': invocation_id,
    'collection_id': collection_id,
    'read1_dataset_id': read1_id,
    'read2_dataset_id': read2_id,
    'runtime_inputs_by_label': invoke_inputs,
    'jobs_summary_last': last_jobs,
    'key_outputs': key_outputs,
}, indent=2, sort_keys=True))

# Write run manifest
manifest = {
    'experiment_name': 'IWC_ATAC-seq_Workflow',
    'created_utc': created_utc,
    'status': 'completed',
    'galaxy_url': base,
    'history_name': history_name,
    'history_id': history_id,
    'workflow_name_page': 'ATAC-seq Analysis: Chromatin Accessibility Profiling',
    'workflow_name_galaxy': imported.get('name'),
    'shared_workflow_id': shared_workflow_id,
    'imported_workflow_id': workflow_id,
    'invocation_id': invocation_id,
    'inputs': {
        'read1_url': read1_url,
        'read2_url': read2_url,
        'reference_genome': 'hg19',
        'effective_genome_size': 2700000000,
        'bin_size': 1000,
    },
    'artifacts': {
        'workflow_file': str(out_dir / 'ATACseq_release_v1_0_imported.ga'),
        'mapping_stats': str(out_dir / 'mapping_stats.txt') if key_outputs['mapping_stats_dataset_id'] else None,
        'narrowpeak': str(out_dir / 'macs2_narrowpeak.bed') if key_outputs['narrowpeak_dataset_id'] else None,
        'multiqc': str(out_dir / 'multiqc_report.html') if key_outputs['multiqc_dataset_id'] else None,
    },
}
(root / 'run_manifest.yaml').write_text(
    '\n'.join([
        'experiment_name: IWC_ATAC-seq_Workflow',
        f'created_utc: {created_utc}',
        'status: completed',
        f'galaxy_url: {base}',
        f'history_name: {history_name}',
        f'history_id: {history_id}',
        'workflow_name_page: "ATAC-seq Analysis: Chromatin Accessibility Profiling"',
        f'workflow_name_galaxy: "{(imported.get("name") or "").replace("\"", "\\\"")}"',
        f'shared_workflow_id: {shared_workflow_id}',
        f'imported_workflow_id: {workflow_id}',
        f'invocation_id: {invocation_id}',
        'inputs:',
        f'  read1_url: {read1_url}',
        f'  read2_url: {read2_url}',
        '  reference_genome: hg19',
        '  effective_genome_size: 2700000000',
        '  bin_size: 1000',
        'artifacts:',
        f'  workflow_file: {out_dir / "ATACseq_release_v1_0_imported.ga"}',
        f'  mapping_stats: {(out_dir / "mapping_stats.txt") if key_outputs["mapping_stats_dataset_id"] else ""}',
        f'  narrowpeak: {(out_dir / "macs2_narrowpeak.bed") if key_outputs["narrowpeak_dataset_id"] else ""}',
        f'  multiqc: {(out_dir / "multiqc_report.html") if key_outputs["multiqc_dataset_id"] else ""}',
    ]) + '\n'
)

# Journal
journal_lines = [
    '# IWC_ATAC-seq_Workflow Journal',
    '',
    f'- Timestamp (UTC): {created_utc}',
    f'- Galaxy server: `{base}`',
    '',
    '## 1. Workflow Resolution',
    f'- Requested page workflow name: `ATAC-seq Analysis: Chromatin Accessibility Profiling`',
    f'- Selected published Galaxy workflow: `{selected.get("name")}`',
    f'- Shared workflow ID: `{shared_workflow_id}`',
    f'- Imported workflow ID: `{workflow_id}`',
    '',
    '## 2. History + Inputs',
    f'- Created history: `{history_name}` (`{history_id}`)',
    f'- Uploaded R1: `{read1_url}` -> `{read1_id}`',
    f'- Uploaded R2: `{read2_url}` -> `{read2_id}`',
    f'- Created collection (`list:paired`): `{collection_id}`',
    '',
    '## 3. Invocation',
    f'- Invocation ID: `{invocation_id}`',
    '- Runtime parameters used (IWC example):',
    '  - `reference_genome = hg19`',
    '  - `effective_genome_size = 2700000000`',
    '  - `bin_size = 1000`',
    f'- Final jobs summary: `{json.dumps(last_jobs, sort_keys=True)}`',
    '',
    '## 4. Saved Artifacts',
    f'- Workflow file: `{out_dir / "ATACseq_release_v1_0_imported.ga"}`',
    f'- Invocation request: `{api_dir / "12_invocation_request.json"}`',
    f'- Invocation report: `{api_dir / "13_invocation_report.json"}`',
    f'- Invocation steps detail: `{api_dir / "15_invocation_steps_detail.json"}`',
    f'- Final history contents snapshot: `{api_dir / "14_history_contents_final.json"}`',
]
if key_outputs['mapping_stats_dataset_id']:
    journal_lines.append(f'- Mapping stats downloaded: `{out_dir / "mapping_stats.txt"}`')
if key_outputs['narrowpeak_dataset_id']:
    journal_lines.append(f'- MACS2 narrowPeak downloaded: `{out_dir / "macs2_narrowpeak.bed"}`')
if key_outputs['multiqc_dataset_id']:
    journal_lines.append(f'- MultiQC report downloaded: `{out_dir / "multiqc_report.html"}`')

(root / 'journal.md').write_text('\n'.join(journal_lines) + '\n')

print(json.dumps({
    'history_id': history_id,
    'shared_workflow_id': shared_workflow_id,
    'imported_workflow_id': workflow_id,
    'invocation_id': invocation_id,
    'key_outputs': key_outputs,
}, indent=2, sort_keys=True))
PY
