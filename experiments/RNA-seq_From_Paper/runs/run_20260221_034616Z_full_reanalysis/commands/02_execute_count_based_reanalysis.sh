#!/bin/sh
set -eu
python3 - <<'PY'
import csv
import io
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

run = Path('experiments/RNA-seq_From_Paper/runs/run_20260221_034616Z_full_reanalysis')
api_dir = run / 'api'
cfg_dir = run / 'configs'
out_dir = run / 'outputs'
meta_dir = run / 'metadata'
for d in (api_dir, cfg_dir, out_dir, meta_dir):
    d.mkdir(parents=True, exist_ok=True)


def load_env(path: Path):
    env = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def save_json(path: Path, obj):
    path.write_text(json.dumps(obj, indent=2, sort_keys=True) + '\n')


def req_json(method, url, headers, *, params=None, payload=None, timeout=180):
    r = requests.request(method, url, headers=headers, params=params, json=payload, timeout=timeout)
    if r.status_code >= 400:
        raise RuntimeError(f'{method} {url} failed: {r.status_code} {r.text[:500]}')
    return r.json()


def parse_float(v):
    try:
        if v is None:
            return None
        s = str(v).strip()
        if s == '' or s.lower() in ('na', 'nan', 'none', 'null'):
            return None
        return float(s)
    except Exception:
        return None


def normalize_gene_name(v):
    return (v or '').strip().upper()


def pick_col(cols, *cands):
    clow = {c.lower(): c for c in cols}
    for cand in cands:
        if cand.lower() in clow:
            return clow[cand.lower()]
    for c in cols:
        lc = c.lower()
        for cand in cands:
            if cand.lower() in lc:
                return c
    return None


env = load_env(Path('.env'))
base = env.get('GALAXY_URL', 'https://usegalaxy.org').rstrip('/')
key = env.get('GALAXY_API_KEY')
if not key:
    raise SystemExit('GALAXY_API_KEY missing in .env')
headers = {'x-api-key': key}

# Source histories from paper (public perm histories with non-purged count tables)
santana_history = 'bbd44e69cb8906b5db3aaed71bf2d1f1'  # prjna904261-perm
wang_history = 'bbd44e69cb8906b5a2336651a2753df4'     # prjna1086003-perm

# Count-table HDAs extracted from the paper's collections
counts = {
    # Santana
    'SRR22376031': {'source_history': santana_history, 'hda_id': 'f9cad7b01a4721352391cc0e3811e368'},
    'SRR22376032': {'source_history': santana_history, 'hda_id': 'f9cad7b01a47213591221e4b6f3eafc5'},
    'SRR22376029': {'source_history': santana_history, 'hda_id': 'f9cad7b01a472135d47590d3dfdd8998'},
    'SRR22376030': {'source_history': santana_history, 'hda_id': 'f9cad7b01a47213529cc42d5ef3efac3'},
    'SRR22376027': {'source_history': santana_history, 'hda_id': 'f9cad7b01a472135839f6aba28e14b4d'},
    'SRR22376028': {'source_history': santana_history, 'hda_id': 'f9cad7b01a4721357948a31d72ead3e4'},
    # Wang in vitro
    'SRR28790270': {'source_history': wang_history, 'hda_id': 'f9cad7b01a47213536dad3ab719e2798'},
    'SRR28790272': {'source_history': wang_history, 'hda_id': 'f9cad7b01a47213507fad9e3c895b967'},
    'SRR28790274': {'source_history': wang_history, 'hda_id': 'f9cad7b01a47213501e4f21612bc975b'},
    'SRR28790276': {'source_history': wang_history, 'hda_id': 'f9cad7b01a4721353dec8b5735f1860c'},
    'SRR28790278': {'source_history': wang_history, 'hda_id': 'f9cad7b01a4721358483fe9162a6712a'},
    'SRR28790280': {'source_history': wang_history, 'hda_id': 'f9cad7b01a47213577e9eeadcd451a0d'},
    # Wang in vivo
    'SRR28791430': {'source_history': wang_history, 'hda_id': 'f9cad7b01a472135c5baf644277fc974'},
    'SRR28791431': {'source_history': wang_history, 'hda_id': 'f9cad7b01a4721351ed14018a0ab2eb7'},
    'SRR28791432': {'source_history': wang_history, 'hda_id': 'f9cad7b01a4721356643ca8eef8da196'},
    'SRR28791433': {'source_history': wang_history, 'hda_id': 'f9cad7b01a472135332205af055089ae'},
    'SRR28791434': {'source_history': wang_history, 'hda_id': 'f9cad7b01a472135f3554823b538e917'},
    'SRR28791437': {'source_history': wang_history, 'hda_id': 'f9cad7b01a472135ba99249e5426401d'},
    'SRR28791438': {'source_history': wang_history, 'hda_id': 'f9cad7b01a472135110eeb2772e6d872'},
}

# GTF from paper history
gtf_source = {'source_history': wang_history, 'hda_id': 'f9cad7b01a472135d39caf31137cbae0'}

comparisons = [
    {
        'key': 'santana_tnSWI1_vs_AR0382_WT',
        'study': 'Santana et al. 2023',
        'changed_label': 'tnSWI1',
        'reference_label': 'AR0382_WT',
        'changed_srrs': ['SRR22376027', 'SRR22376028'],
        'reference_srrs': ['SRR22376031', 'SRR22376032'],
        'padj_threshold': 0.05,
        'lfc_threshold': 1.0,
        'published': {
            'r2': 0.94,
            'direction_agreement_pct': 99.0,
            'scf1_log2fc': -6.68,
            'mapped_genes': 203,
        },
    },
    {
        'key': 'santana_AR0387_WT_vs_AR0382_WT',
        'study': 'Santana et al. 2023',
        'changed_label': 'AR0387_WT',
        'reference_label': 'AR0382_WT',
        'changed_srrs': ['SRR22376029', 'SRR22376030'],
        'reference_srrs': ['SRR22376031', 'SRR22376032'],
        'padj_threshold': 0.05,
        'lfc_threshold': 1.0,
        'published': {
            'r2': 0.89,
            'direction_agreement_pct': 97.0,
            'scf1_log2fc': -7.25,
            'mapped_genes': 165,
        },
    },
    {
        'key': 'wang_AR0382_in_vitro_vs_AR0387_in_vitro',
        'study': 'Wang et al. 2024',
        'changed_label': 'AR0382_in_vitro',
        'reference_label': 'AR0387_in_vitro',
        'changed_srrs': ['SRR28790270', 'SRR28790272', 'SRR28790274'],
        'reference_srrs': ['SRR28790276', 'SRR28790278', 'SRR28790280'],
        'padj_threshold': 0.01,
        'lfc_threshold': 1.0,
        'published': {
            'r2': 0.98,
            'direction_agreement_pct': 100.0,
            'deg_count': 76,
            'scf1_log2fc': 8.61,
            'als4112_log2fc': 5.07,
        },
    },
    {
        'key': 'wang_AR0382_in_vivo_vs_AR0387_in_vivo',
        'study': 'Wang et al. 2024',
        'changed_label': 'AR0382_in_vivo',
        'reference_label': 'AR0387_in_vivo',
        'changed_srrs': ['SRR28791430', 'SRR28791431', 'SRR28791432'],
        'reference_srrs': ['SRR28791433', 'SRR28791434', 'SRR28791437', 'SRR28791438'],
        'padj_threshold': 0.01,
        'lfc_threshold': 1.0,
        'published': {
            'r2': 0.9998,
            'direction_agreement_pct': 100.0,
            'deg_count': 259,
            'scf1_log2fc': 4.47,
            'als4112_log2fc': 2.56,
        },
    },
]

# Save workflow used
rnaseq_de_wf_path = cfg_dir / 'rnaseq_de_filtering_plotting.ga'
if not rnaseq_de_wf_path.exists():
    wf_url = 'https://raw.githubusercontent.com/galaxyproject/iwc/main/workflows/transcriptomics/rnaseq-de/rnaseq-de-filtering-plotting.ga'
    wf_text = requests.get(wf_url, timeout=180).text
    rnaseq_de_wf_path.write_text(wf_text)

# 1) Create new history
stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%SZ')
history_name = f'RNA-seq_From_Paper_count_based_{stamp}'
history = req_json('POST', f'{base}/api/histories', headers, payload={'name': history_name})
save_json(api_dir / '20_create_history_count_based.json', history)
history_id = history['id']

# 2) Download count tables + GTF locally from published histories, then upload via upload1.
# URL-fetch jobs cannot pull authenticated /api/histories/.../display endpoints.
inputs_dir = run / 'inputs' / 'count_based'
inputs_dir.mkdir(parents=True, exist_ok=True)

download_manifest = []
for srr, meta in sorted(counts.items()):
    name = f'{srr}_counts.tsv'
    url = f"{base}/api/histories/{meta['source_history']}/contents/{meta['hda_id']}/display?to_ext=tabular"
    r = requests.get(url, headers=headers, timeout=180)
    if r.status_code >= 400:
        raise RuntimeError(f'Failed to download source count table {srr}: {r.status_code} {r.text[:200]}')
    path = inputs_dir / name
    path.write_text(r.text)
    download_manifest.append({'name': name, 'path': str(path), 'source_url': url})

gtf_name = 'GCA_002759435.3_Cand_auris_B8441_V3.ncbiGene.gtf.gz'
gtf_url = f"{base}/api/histories/{gtf_source['source_history']}/contents/{gtf_source['hda_id']}/display"
gtf_resp = requests.get(gtf_url, headers=headers, timeout=180)
if gtf_resp.status_code >= 400:
    raise RuntimeError(f'Failed to download source GTF: {gtf_resp.status_code} {gtf_resp.text[:200]}')
gtf_path = inputs_dir / gtf_name
gtf_path.write_bytes(gtf_resp.content)
download_manifest.append({'name': gtf_name, 'path': str(gtf_path), 'source_url': gtf_url})
save_json(cfg_dir / '20_download_manifest_count_inputs.json', {'files': download_manifest})

uploaded_ids = []
for i, entry in enumerate(download_manifest, start=1):
    name = entry['name']
    path = Path(entry['path'])
    form_data = {
        'history_id': history_id,
        'tool_id': 'upload1',
        'files_0|NAME': name,
        'files_0|type': 'upload_dataset',
    }
    file_handle = path.open('rb')
    try:
        r = requests.post(
            f'{base}/api/tools',
            headers=headers,
            data=form_data,
            files={'files_0|file_data': (name, file_handle)},
            timeout=300,
        )
    finally:
        file_handle.close()
    if r.status_code >= 400:
        raise RuntimeError(f'Upload failed for {name}: {r.status_code} {r.text[:300]}')
    obj = r.json()
    save_json(api_dir / f'21_upload_local_{i:02d}_{name}.json', obj)
    for out in obj.get('outputs', []):
        uploaded_ids.append(out['id'])

# Poll upload states
uploaded = {}
for poll in range(1, 301):
    snap = {'poll': poll, 'datasets': []}
    all_terminal = True
    for did in uploaded_ids:
        d = req_json('GET', f'{base}/api/histories/{history_id}/contents/{did}', headers)
        uploaded[did] = d
        st = d.get('state')
        snap['datasets'].append({'id': did, 'name': d.get('name'), 'state': st})
        if st not in ('ok', 'error', 'failed_metadata', 'discarded'):
            all_terminal = False
    save_json(api_dir / f'22_upload_poll_count_{poll:03d}.json', snap)
    if all_terminal:
        break
    time.sleep(3)

failed = [d for d in uploaded.values() if d.get('state') != 'ok']
if failed:
    save_json(api_dir / '22b_upload_failures_count_based.json', {'failed': failed})
    raise RuntimeError(f'Count-input upload failures: {len(failed)}')

name_to_id = {d.get('name'): did for did, d in uploaded.items()}
gtf_hda_id = name_to_id[gtf_name]

# 3) Create condition collections (list)
condition_map = {
    'AR0382_WT': ['SRR22376031', 'SRR22376032'],
    'AR0387_WT': ['SRR22376029', 'SRR22376030'],
    'tnSWI1': ['SRR22376027', 'SRR22376028'],
    'AR0382_in_vitro': ['SRR28790270', 'SRR28790272', 'SRR28790274'],
    'AR0387_in_vitro': ['SRR28790276', 'SRR28790278', 'SRR28790280'],
    'AR0382_in_vivo': ['SRR28791430', 'SRR28791431', 'SRR28791432'],
    'AR0387_in_vivo': ['SRR28791433', 'SRR28791434', 'SRR28791437', 'SRR28791438'],
}
condition_collection_ids = {}
for cond, srrs in condition_map.items():
    elems = []
    for srr in srrs:
        hda_id = name_to_id[f'{srr}_counts.tsv']
        elems.append({'name': srr, 'src': 'hda', 'id': hda_id})
    payload = {
        'history_id': history_id,
        'collection_type': 'list',
        'name': f'{cond}_counts',
        'element_identifiers': elems,
    }
    save_json(cfg_dir / f'23_collection_payload_{cond}.json', payload)
    col = req_json('POST', f'{base}/api/dataset_collections', headers, payload=payload)
    save_json(api_dir / f'23_create_collection_{cond}.json', col)
    condition_collection_ids[cond] = col['id']

# 4) Import rnaseq-de workflow
wf_obj = json.loads(rnaseq_de_wf_path.read_text())
import_payload = {'workflow': wf_obj}
save_json(cfg_dir / '24_import_rnaseq_de_workflow_payload.json', import_payload)
imported = req_json('POST', f'{base}/api/workflows', headers, payload=import_payload)
save_json(api_dir / '24_import_rnaseq_de_workflow.json', imported)
workflow_id = imported['id']

wf_download = req_json('GET', f'{base}/api/workflows/{workflow_id}/download', headers)
save_json(api_dir / '25_rnaseq_de_workflow_download.json', wf_download)
(out_dir / 'rnaseq_de_filtering_plotting_imported.ga').write_text(json.dumps(wf_download, indent=2, sort_keys=True) + '\n')

# 5) Invoke per comparison
invocations = []
for c in comparisons:
    invoke_inputs = {
        'Counts from changed condition': {'src': 'hdca', 'id': condition_collection_ids[c['changed_label']]},
        'Counts from reference condition': {'src': 'hdca', 'id': condition_collection_ids[c['reference_label']]},
        'Count files have header': False,
        'Gene Annotaton': {'src': 'hda', 'id': gtf_hda_id},
        'Adjusted p-value threshold': c['padj_threshold'],
        'log2 fold change threshold': c['lfc_threshold'],
    }
    payload = {'history': f'hist_id={history_id}', 'inputs_by': 'name', 'inputs': invoke_inputs}
    save_json(cfg_dir / f'26_invoke_payload_{c["key"]}.json', payload)
    inv = req_json('POST', f'{base}/api/workflows/{workflow_id}/invocations', headers, payload=payload)
    save_json(api_dir / f'26_invoke_{c["key"]}.json', inv)
    invocations.append({'comparison': c, 'invocation_id': inv['id']})

# 6) Poll all invocations
inv_status = {}
for poll in range(1, 721):
    cycle = {'poll': poll, 'invocations': []}
    all_done = True
    for item in invocations:
        inv_id = item['invocation_id']
        inv_obj = req_json('GET', f'{base}/api/invocations/{inv_id}', headers)
        jobs = req_json('GET', f'{base}/api/invocations/{inv_id}/jobs_summary', headers)
        states = jobs.get('states') or {}
        running = sum(int(states.get(k, 0) or 0) for k in ('new', 'queued', 'running', 'waiting', 'resubmitted'))
        terminal = sum(int(states.get(k, 0) or 0) for k in ('ok', 'error', 'failed', 'deleted', 'paused', 'skipped', 'deleted_new'))
        done = running == 0 and terminal > 0
        inv_status[inv_id] = {'done': done, 'states': states, 'comparison_key': item['comparison']['key']}
        cycle['invocations'].append({
            'invocation_id': inv_id,
            'comparison_key': item['comparison']['key'],
            'invocation_state': inv_obj.get('state'),
            'jobs_summary': jobs,
            'done': done,
        })
        if not done:
            all_done = False
    save_json(api_dir / f'27_invocation_poll_{poll:03d}.json', cycle)
    if all_done:
        break
    time.sleep(10)

# Collect step outputs and ensure no failures
records = []
for item in invocations:
    c = item['comparison']
    inv_id = item['invocation_id']
    states = inv_status[inv_id]['states']
    if int(states.get('error', 0) or 0) > 0 or int(states.get('failed', 0) or 0) > 0:
        raise RuntimeError(f'Invocation {inv_id} failed for {c["key"]}: {states}')

    inv_obj = req_json('GET', f'{base}/api/invocations/{inv_id}', headers)
    step_details = []
    for s in inv_obj.get('steps', []):
        sid = s.get('id')
        if sid:
            step_details.append(req_json('GET', f'{base}/api/invocations/{inv_id}/steps/{sid}', headers))
    save_json(api_dir / f'28_invocation_steps_{c["key"]}.json', step_details)

    # Outputs live on the DESeq2/Volcano/Concatenate steps
    annotated_id = None
    counts_id = None
    plots_id = None
    volcano_id = None
    for d in step_details:
        lbl = d.get('workflow_step_label') or ''
        outs = d.get('outputs') or []
        for o in outs:
            ds = o.get('dataset') or {}
            did = ds.get('id')
            if not did:
                continue
            wlabel = (o.get('workflow_output_label') or '').lower()
            if 'annotated deseq2 results table' in wlabel:
                annotated_id = did
            if 'deseq2 normalized counts' in wlabel:
                counts_id = did
            if 'deseq2 plots' in wlabel:
                plots_id = did
            if 'volcano plot of de genes' in wlabel:
                volcano_id = did

    if not annotated_id:
        # Fallback by workflow output labels in report
        rep = req_json('GET', f'{base}/api/invocations/{inv_id}/report', headers)
        save_json(api_dir / f'29_invocation_report_{c["key"]}.json', rep)
        outs = rep.get('outputs') or []
        for o in outs:
            label = (o.get('label') or '').lower()
            did = (o.get('dataset') or {}).get('id')
            if not did:
                continue
            if 'annotated deseq2 results table' in label:
                annotated_id = did
            elif 'deseq2 normalized counts' in label:
                counts_id = did
            elif 'deseq2 plots' in label:
                plots_id = did
            elif 'volcano plot of de genes' in label:
                volcano_id = did

    if not annotated_id:
        raise RuntimeError(f'Could not resolve annotated DESeq2 output for {c["key"]}')

    records.append({
        'comparison_key': c['key'],
        'invocation_id': inv_id,
        'annotated_id': annotated_id,
        'normalized_counts_id': counts_id,
        'deseq2_plots_id': plots_id,
        'volcano_id': volcano_id,
    })

# 7) Download annotated results and build comparison report
summary_rows = []
for c in comparisons:
    rec = next(r for r in records if r['comparison_key'] == c['key'])
    text = requests.get(
        f"{base}/api/histories/{history_id}/contents/{rec['annotated_id']}/display",
        headers=headers,
        timeout=300,
    ).text
    out_tsv = out_dir / f"{c['key']}__annotated_deseq2_results.tsv"
    out_tsv.write_text(text)

    rows = list(csv.DictReader(io.StringIO(text), delimiter='\t'))
    cols = list(rows[0].keys()) if rows else []
    col_gene_id = pick_col(cols, 'GeneID', 'gene_id')
    col_gene_name = pick_col(cols, 'Gene name', 'gene_name', 'gene')
    col_lfc = pick_col(cols, 'log2(FC)', 'log2FoldChange', 'log2fc', 'log2 fold change')
    col_padj = pick_col(cols, 'P-adj', 'padj', 'adj_p_value', 'fdr')
    if not col_lfc or not col_padj:
        raise RuntimeError(f'Missing log2FC/padj columns for {c["key"]}. cols={cols}')

    deg_count = 0
    scf1_lfc = None
    als4112_lfc = None
    for r in rows:
        lfc = parse_float(r.get(col_lfc))
        padj = parse_float(r.get(col_padj))
        if lfc is not None and padj is not None and padj < c['padj_threshold'] and abs(lfc) >= c['lfc_threshold']:
            deg_count += 1

        gene_name = normalize_gene_name(r.get(col_gene_name, '')) if col_gene_name else ''
        gene_id = (r.get(col_gene_id) or '').strip() if col_gene_id else ''
        if lfc is None:
            continue
        if gene_name == 'SCF1' or gene_id in ('B9J08_03708', 'B9J08_001458'):
            scf1_lfc = lfc
        if gene_name == 'ALS4112':
            als4112_lfc = lfc

    pub = c['published']
    summary_rows.append({
        'comparison_key': c['key'],
        'study': c['study'],
        'changed_label': c['changed_label'],
        'reference_label': c['reference_label'],
        'observed_deg_count_thresholded': deg_count,
        'published_deg_count_thresholded': pub.get('deg_count'),
        'observed_scf1_log2fc': scf1_lfc,
        'published_scf1_log2fc': pub.get('scf1_log2fc'),
        'delta_scf1_log2fc': None if (scf1_lfc is None or pub.get('scf1_log2fc') is None) else scf1_lfc - pub.get('scf1_log2fc'),
        'observed_als4112_log2fc': als4112_lfc,
        'published_als4112_log2fc': pub.get('als4112_log2fc'),
        'delta_als4112_log2fc': None if (als4112_lfc is None or pub.get('als4112_log2fc') is None) else als4112_lfc - pub.get('als4112_log2fc'),
        'published_r2': pub.get('r2'),
        'published_direction_agreement_pct': pub.get('direction_agreement_pct'),
        'published_mapped_genes': pub.get('mapped_genes'),
    })

save_json(out_dir / 'paper_vs_observed_summary_count_based.json', {'rows': summary_rows})
with (out_dir / 'paper_vs_observed_summary_count_based.csv').open('w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(summary_rows[0].keys()))
    w.writeheader()
    w.writerows(summary_rows)

md = []
md.append('# RNA-seq From Paper: Count-Based DE Reanalysis Report')
md.append('')
md.append(f'- generated_utc: `{datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}`')
md.append(f'- galaxy_url: `{base}`')
md.append(f'- history_name: `{history_name}`')
md.append(f'- history_id: `{history_id}`')
md.append(f'- workflow_id: `{workflow_id}`')
md.append('')
md.append('## Analysis Scope')
md.append('')
md.append('- Reproduced the DE analysis stage using the same count-table inputs from the paper public histories.')
md.append('- Ran IWC `rnaseq-de-filtering-plotting` workflow for all 4 paper comparisons in a new history.')
md.append('')
md.append('## Comparison Against Published Values')
md.append('')
md.append('| comparison | observed DEG count (thresholded) | published DEG count | observed SCF1 log2FC | published SCF1 log2FC | observed ALS4112 log2FC | published ALS4112 log2FC | published R2 | published direction agreement |')
md.append('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
for r in summary_rows:
    md.append(
        '| {comparison_key} | {observed_deg_count_thresholded} | {published_deg_count_thresholded} | {observed_scf1_log2fc} | {published_scf1_log2fc} | {observed_als4112_log2fc} | {published_als4112_log2fc} | {published_r2} | {published_direction_agreement_pct} |'.format(**r)
    )
md.append('')
md.append('## Notes')
md.append('')
md.append('- Published R2/direction-agreement values come from Anton et al. 2025 and are included for reference.')
md.append('- Exact recomputation of R2 against the publication supplementary fold-change tables requires those supplementary tables as explicit input files.')

(out_dir / 'paper_vs_observed_report_count_based.md').write_text('\n'.join(md) + '\n')

# Metadata + manifest updates
save_json(meta_dir / 'count_based_run_ids.json', {
    'history_name': history_name,
    'history_id': history_id,
    'workflow_id': workflow_id,
    'condition_collection_ids': condition_collection_ids,
    'records': records,
})

manifest_path = run / 'run_manifest.yaml'
manifest_lines = manifest_path.read_text().splitlines()
out_lines = []
for line in manifest_lines:
    if line.startswith('status:'):
        out_lines.append('status: completed')
    elif line.startswith('tool_name:'):
        out_lines.append('tool_name: "IWC rnaseq-de"')
    elif line.startswith('tool_id:'):
        out_lines.append(f'tool_id: "{workflow_id}"')
    elif line.startswith('tool_version:'):
        out_lines.append('tool_version: "rnaseq-de-filtering-plotting.ga"')
    elif line.startswith('history_name:'):
        out_lines.append(f'history_name: "{history_name}"')
    elif line.startswith('history_id:'):
        out_lines.append(f'history_id: "{history_id}"')
    else:
        out_lines.append(line)
manifest_path.write_text('\n'.join(out_lines) + '\n')

with (run / 'journal.md').open('a') as j:
    j.write(f'\n### {datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")} - Count-based DE reanalysis completed\n')
    j.write(f'- Created history `{history_name}` (`{history_id}`).\n')
    j.write(f'- Uploaded 19 count tables + GTF from paper public histories.\n')
    j.write(f'- Imported workflow `{workflow_id}` and ran 4 DE comparisons.\n')
    j.write(f'- Report: `outputs/paper_vs_observed_report_count_based.md`.\n')

print(json.dumps({'history_id': history_id, 'workflow_id': workflow_id, 'comparisons': [c['key'] for c in comparisons]}, indent=2))
PY
