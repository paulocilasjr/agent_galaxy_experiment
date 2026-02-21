#!/bin/sh
set -eu
python3 - <<'PY'
import csv
import gzip
import io
import json
import math
import re
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

# ---------- Helpers ----------
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

def history_dataset_details(base, headers, history_id, dataset_id):
    return req_json('GET', f'{base}/api/histories/{history_id}/contents/{dataset_id}', headers)

def download_dataset_text(base, headers, history_id, dataset_id):
    r = requests.get(f'{base}/api/histories/{history_id}/contents/{dataset_id}/display', headers=headers, timeout=300)
    if r.status_code >= 400:
        raise RuntimeError(f'display failed for {dataset_id}: {r.status_code} {r.text[:300]}')
    return r.text

def normalize_gene_name(v):
    return (v or '').strip().upper()

# ---------- Inputs from paper ----------
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

all_srrs = sorted({s for c in comparisons for s in (c['changed_srrs'] + c['reference_srrs'])})

# ---------- Galaxy auth ----------
env = load_env(Path('.env'))
base = env.get('GALAXY_URL', 'https://usegalaxy.org').rstrip('/')
key = env.get('GALAXY_API_KEY')
if not key:
    raise SystemExit('GALAXY_API_KEY missing in .env')
headers = {'x-api-key': key}

# ---------- Provenance seed files ----------
(run / 'prompts' / '01_user_request.md').write_text(
    'User requested full paper-faithful Galaxy execution: create a new history, upload inputs, run workflow, and compare against published results.\n'
)
(run / 'prompts' / '02_execution_notes.md').write_text(
    'Execution uses local workflow: experiments/RNA-seq_From_Paper/configs/rna_seq_from_paper_master.ga\n'
    'Reference genome selector value: GCA_002759435.3\n'
    'Strandedness input: unstranded\n'
)

# ---------- 1) Validate user ----------
user = req_json('GET', f'{base}/api/users/current', headers)
save_json(api_dir / '01_users_current.json', user)

# ---------- 2) Resolve ENA FASTQ URLs ----------
ena_rows = []
for srr in all_srrs:
    url = f'https://www.ebi.ac.uk/ena/portal/api/filereport?accession={srr}&result=read_run&fields=run_accession,fastq_ftp&format=json'
    r = requests.get(url, timeout=120)
    r.raise_for_status()
    arr = r.json()
    if not arr or not arr[0].get('fastq_ftp'):
        raise RuntimeError(f'ENA returned no fastq_ftp for {srr}')
    parts = [p.strip() for p in arr[0]['fastq_ftp'].split(';') if p.strip()]
    if len(parts) != 2:
        raise RuntimeError(f'Expected paired FASTQ URLs for {srr}, got: {parts}')
    urls = [f'https://{p}' if p.startswith('ftp.sra.ebi.ac.uk/') else p for p in parts]
    ena_rows.append({'srr': srr, 'read1_url': urls[0], 'read2_url': urls[1]})

save_json(cfg_dir / '01_ena_fastq_urls.json', {'rows': ena_rows})

# Include annotation GTF as required workflow input
annotation_gtf_url = (
    'https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/002/759/435/'
    'GCA_002759435.3_Cand_auris_B8441_V3/'
    'GCA_002759435.3_Cand_auris_B8441_V3_genomic.gtf.gz'
)

# ---------- 3) Create history ----------
stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%SZ')
history_name = f'RNA-seq_From_Paper_{stamp}'
history = req_json('POST', f'{base}/api/histories', headers, payload={'name': history_name})
save_json(api_dir / '02_create_history.json', history)
history_id = history['id']

# ---------- 4) Upload all FASTQs + GTF ----------
elements = []
for row in ena_rows:
    srr = row['srr']
    elements.append({'name': f'{srr}_1.fastq.gz', 'src': 'url', 'url': row['read1_url'], 'ext': 'fastqsanger.gz', 'dbkey': '?'})
    elements.append({'name': f'{srr}_2.fastq.gz', 'src': 'url', 'url': row['read2_url'], 'ext': 'fastqsanger.gz', 'dbkey': '?'})

# Upload annotation GTF
# Keep as gtf.gz so Galaxy can decompress/handle directly.
elements.append({'name': 'GCA_002759435.3_Cand_auris_B8441_V3_genomic.gtf.gz', 'src': 'url', 'url': annotation_gtf_url, 'ext': 'gtf.gz', 'dbkey': '?'})

fetch_payload = {
    'history_id': history_id,
    'targets': [{'destination': {'type': 'hdas'}, 'elements': elements}],
}
save_json(cfg_dir / '02_fetch_payload_upload_fastqs_gtf.json', fetch_payload)
fetch_resp = req_json('POST', f'{base}/api/tools/fetch', headers, payload=fetch_payload, timeout=300)
save_json(api_dir / '03_upload_fetch.json', fetch_resp)

uploaded_ids = [o['id'] for o in fetch_resp.get('outputs', [])]
if len(uploaded_ids) != len(elements):
    # still continue, but this is important
    save_json(api_dir / '03b_upload_fetch_warning.json', {'expected': len(elements), 'received': len(uploaded_ids)})

# ---------- 5) Poll uploads ----------
dataset_details = {}
for poll in range(1, 721):  # up to 2 hours at 10s
    snap = {'poll': poll, 'datasets': []}
    all_terminal = True
    for did in uploaded_ids:
        d = history_dataset_details(base, headers, history_id, did)
        dataset_details[did] = d
        state = d.get('state')
        snap['datasets'].append({'id': did, 'name': d.get('name'), 'state': state})
        if state not in ('ok', 'error', 'failed_metadata', 'discarded'):
            all_terminal = False
    save_json(api_dir / f'04_upload_poll_{poll:03d}.json', snap)
    if all_terminal:
        break
    time.sleep(10)

failed_uploads = [
    {'id': did, 'name': d.get('name'), 'state': d.get('state')}
    for did, d in dataset_details.items()
    if d.get('state') != 'ok'
]
if failed_uploads:
    save_json(api_dir / '04b_upload_failures.json', {'failed': failed_uploads})
    raise RuntimeError(f'Upload failures detected: {failed_uploads[:5]}')

name_to_hda = {d.get('name'): did for did, d in dataset_details.items()}

# ---------- 6) Build condition collections ----------
# Build per-SRR paired collection first by referencing uploaded *_1/*_2 datasets.
def create_list_paired_collection(name, srrs):
    elems = []
    for srr in srrs:
        r1 = name_to_hda.get(f'{srr}_1.fastq.gz')
        r2 = name_to_hda.get(f'{srr}_2.fastq.gz')
        if not r1 or not r2:
            raise RuntimeError(f'Missing uploaded FASTQ for {srr}: r1={r1} r2={r2}')
        elems.append({
            'name': srr,
            'src': 'new_collection',
            'collection_type': 'paired',
            'element_identifiers': [
                {'name': 'forward', 'src': 'hda', 'id': r1},
                {'name': 'reverse', 'src': 'hda', 'id': r2},
            ],
        })
    payload = {
        'history_id': history_id,
        'collection_type': 'list:paired',
        'name': name,
        'element_identifiers': elems,
    }
    save_json(cfg_dir / f'03_collection_payload_{name}.json', payload)
    col = req_json('POST', f'{base}/api/dataset_collections', headers, payload=payload)
    save_json(api_dir / f'05_create_collection_{name}.json', col)
    return col['id']

condition_to_srrs = {}
for c in comparisons:
    condition_to_srrs[c['changed_label']] = c['changed_srrs']
    condition_to_srrs[c['reference_label']] = c['reference_srrs']

condition_collection_ids = {}
for condition, srrs in sorted(condition_to_srrs.items()):
    cid = create_list_paired_collection(f'{condition}_list_paired', srrs)
    condition_collection_ids[condition] = cid

# ---------- 7) Import local master workflow ----------
workflow_path = Path('experiments/RNA-seq_From_Paper/configs/rna_seq_from_paper_master.ga')
wf_obj = json.loads(workflow_path.read_text())
import_payload = {'workflow': wf_obj}
save_json(cfg_dir / '04_import_workflow_payload.json', import_payload)
imported = req_json('POST', f'{base}/api/workflows', headers, payload=import_payload)
save_json(api_dir / '06_import_workflow.json', imported)
workflow_id = imported['id']

wf_download = req_json('GET', f'{base}/api/workflows/{workflow_id}/download', headers)
save_json(api_dir / '07_imported_workflow_download.json', wf_download)
(out_dir / 'rna_seq_from_paper_master_imported.ga').write_text(json.dumps(wf_download, indent=2, sort_keys=True) + '\n')

# ---------- 8) Invoke workflow for each comparison ----------
invocations = []
for c in comparisons:
    invoke_inputs = {
        'Changed condition FASTQ pairs': {'src': 'hdca', 'id': condition_collection_ids[c['changed_label']]},
        'Reference condition FASTQ pairs': {'src': 'hdca', 'id': condition_collection_ids[c['reference_label']]},
        'Forward adapter': '',
        'Reverse adapter': '',
        'Generate additional QC reports': False,
        'Reference genome': 'GCA_002759435.3',
        'GTF file of annotation': {'src': 'hda', 'id': name_to_hda['GCA_002759435.3_Cand_auris_B8441_V3_genomic.gtf.gz']},
        'Strandedness': 'unstranded',
        'Use featureCounts for generating count tables': False,
        'Compute Cufflinks FPKM': False,
        'Compute StringTie FPKM': False,
        'Count files have header': False,
        'Adjusted p-value threshold': c['padj_threshold'],
        'log2 fold change threshold': c['lfc_threshold'],
    }
    payload = {
        'history': f'hist_id={history_id}',
        'inputs_by': 'name',
        'inputs': invoke_inputs,
    }
    save_json(cfg_dir / f'05_invoke_payload_{c["key"]}.json', payload)
    inv = req_json('POST', f'{base}/api/workflows/{workflow_id}/invocations', headers, payload=payload, timeout=240)
    save_json(api_dir / f'08_invoke_{c["key"]}.json', inv)
    invocations.append({'comparison': c, 'invocation_id': inv['id']})

# ---------- 9) Poll all invocations ----------
terminal_states = {'ok', 'error', 'failed', 'deleted', 'skipped', 'paused', 'cancelled'}
inv_status = {i['invocation_id']: {'done': False} for i in invocations}
for poll in range(1, 1441):  # up to 8h at 20s
    cycle = {'poll': poll, 'invocations': []}
    all_done = True
    for item in invocations:
        inv_id = item['invocation_id']
        inv_obj = req_json('GET', f'{base}/api/invocations/{inv_id}', headers)
        jobs = req_json('GET', f'{base}/api/invocations/{inv_id}/jobs_summary', headers)
        states = (jobs.get('states') or {})
        running = sum(int(states.get(k, 0) or 0) for k in ('new', 'queued', 'running', 'waiting', 'resubmitted'))
        terminal = sum(int(states.get(k, 0) or 0) for k in ('ok', 'error', 'failed', 'deleted', 'paused', 'skipped', 'deleted_new'))
        done = running == 0 and terminal > 0
        inv_status[inv_id] = {
            'done': done,
            'state': inv_obj.get('state'),
            'jobs_summary': jobs,
            'comparison_key': item['comparison']['key'],
        }
        cycle['invocations'].append({
            'invocation_id': inv_id,
            'comparison_key': item['comparison']['key'],
            'invocation_state': inv_obj.get('state'),
            'jobs_summary': jobs,
            'running_jobs': running,
            'terminal_jobs': terminal,
            'done': done,
        })
        if not done:
            all_done = False
    save_json(api_dir / f'09_invocation_poll_{poll:04d}.json', cycle)
    if all_done:
        break
    time.sleep(20)

# Verify none ended with fatal errors
final_invocation_records = []
for item in invocations:
    inv_id = item['invocation_id']
    report = req_json('GET', f'{base}/api/invocations/{inv_id}/report', headers)
    request_obj = req_json('GET', f'{base}/api/invocations/{inv_id}/request', headers)
    steps = req_json('GET', f'{base}/api/invocations/{inv_id}', headers).get('steps', [])

    step_details = []
    for s in steps:
        sid = s.get('id')
        if not sid:
            continue
        d = req_json('GET', f'{base}/api/invocations/{inv_id}/steps/{sid}', headers)
        step_details.append(d)

    save_json(api_dir / f'10_invocation_request_{item["comparison"]["key"]}.json', request_obj)
    save_json(api_dir / f'11_invocation_report_{item["comparison"]["key"]}.json', report)
    save_json(api_dir / f'12_invocation_steps_{item["comparison"]["key"]}.json', step_details)

    states = (inv_status[inv_id]['jobs_summary'].get('states') or {})
    if int(states.get('error', 0) or 0) > 0 or int(states.get('failed', 0) or 0) > 0:
        raise RuntimeError(f'Invocation {inv_id} ({item["comparison"]["key"]}) has failed jobs: {states}')

    # Extract key output dataset ids from step details by workflow step label
    by_label = {d.get('workflow_step_label'): d for d in step_details if d.get('workflow_step_label')}
    de_step = by_label.get('Differential expression and visualization (IWC rnaseq-de)', {})
    out_vals = de_step.get('outputs') or []

    # We expect hda outputs for de plots/norm counts/annotated table/volcano
    out_map = {}
    for o in out_vals:
        out_map[o.get('workflow_output_label') or o.get('output_name') or o.get('name')] = o

    # Normalize labels
    annotated_id = None
    norm_counts_id = None
    de_plots_id = None
    volcano_id = None
    for label, obj in out_map.items():
        ds = obj.get('dataset') or {}
        did = ds.get('id')
        if not did:
            continue
        l = (label or '').lower()
        if 'annotated deseq2 results' in l:
            annotated_id = did
        elif 'normalized counts' in l:
            norm_counts_id = did
        elif 'deseq2 plots' in l:
            de_plots_id = did
        elif 'volcano' in l:
            volcano_id = did

    if not annotated_id:
        raise RuntimeError(f'Could not resolve annotated DESeq2 results output for {item["comparison"]["key"]}')

    final_invocation_records.append({
        'comparison_key': item['comparison']['key'],
        'invocation_id': inv_id,
        'annotated_deseq2_results_id': annotated_id,
        'normalized_counts_id': norm_counts_id,
        'deseq2_plots_id': de_plots_id,
        'volcano_plot_id': volcano_id,
    })

# ---------- 10) Download key outputs ----------
comparison_tables = {}
for rec in final_invocation_records:
    key_name = rec['comparison_key']
    tsv_text = download_dataset_text(base, headers, history_id, rec['annotated_deseq2_results_id'])
    out_path = out_dir / f'{key_name}__annotated_deseq2_results.tsv'
    out_path.write_text(tsv_text)
    comparison_tables[key_name] = out_path

# ---------- 11) Parse tables + compare to paper ----------
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

def load_table(path: Path):
    text = path.read_text(errors='replace')
    rows = list(csv.DictReader(io.StringIO(text), delimiter='\t'))
    return rows

def pick_col(cols, *cands):
    clow = {c.lower(): c for c in cols}
    for cand in cands:
        if cand.lower() in clow:
            return clow[cand.lower()]
    # fuzzy
    for c in cols:
        lc = c.lower()
        for cand in cands:
            if cand.lower() in lc:
                return c
    return None

results_summary = []
for c in comparisons:
    key_name = c['key']
    rows = load_table(comparison_tables[key_name])
    if not rows:
        raise RuntimeError(f'No rows parsed for {key_name}')
    cols = list(rows[0].keys())

    col_gene_id = pick_col(cols, 'GeneID', 'gene_id')
    col_gene_name = pick_col(cols, 'Gene name', 'gene_name', 'gene')
    col_lfc = pick_col(cols, 'log2(FC)', 'log2FoldChange', 'log2fc', 'log2 fold change')
    col_padj = pick_col(cols, 'P-adj', 'padj', 'adj_p_value', 'fdr')

    if not col_lfc or not col_padj:
        raise RuntimeError(f'Could not find required columns in {key_name}. cols={cols}')

    # DEG count under paper threshold
    deg_count = 0
    for r in rows:
        lfc = parse_float(r.get(col_lfc))
        padj = parse_float(r.get(col_padj))
        if lfc is None or padj is None:
            continue
        if padj < c['padj_threshold'] and abs(lfc) >= c['lfc_threshold']:
            deg_count += 1

    # SCF1 / ALS4112 lookup
    scf1_lfc = None
    als4112_lfc = None
    for r in rows:
        gene_name = normalize_gene_name(r.get(col_gene_name, '')) if col_gene_name else ''
        gene_id = (r.get(col_gene_id) or '').strip() if col_gene_id else ''
        lfc = parse_float(r.get(col_lfc))
        if lfc is None:
            continue
        if gene_name == 'SCF1' or gene_id == 'B9J08_03708' or gene_id == 'B9J08_001458':
            scf1_lfc = lfc
        if gene_name == 'ALS4112':
            als4112_lfc = lfc

    published = c['published']
    row = {
        'comparison_key': key_name,
        'study': c['study'],
        'changed_label': c['changed_label'],
        'reference_label': c['reference_label'],
        'observed_deg_count_thresholded': deg_count,
        'published_deg_count_thresholded': published.get('deg_count'),
        'observed_scf1_log2fc': scf1_lfc,
        'published_scf1_log2fc': published.get('scf1_log2fc'),
        'delta_scf1_log2fc': None if (scf1_lfc is None or published.get('scf1_log2fc') is None) else scf1_lfc - published.get('scf1_log2fc'),
        'observed_als4112_log2fc': als4112_lfc,
        'published_als4112_log2fc': published.get('als4112_log2fc'),
        'delta_als4112_log2fc': None if (als4112_lfc is None or published.get('als4112_log2fc') is None) else als4112_lfc - published.get('als4112_log2fc'),
        'published_r2': published.get('r2'),
        'published_direction_agreement_pct': published.get('direction_agreement_pct'),
        'published_mapped_genes': published.get('mapped_genes'),
    }
    results_summary.append(row)

save_json(out_dir / 'paper_vs_observed_summary.json', {'rows': results_summary})

# CSV summary
csv_path = out_dir / 'paper_vs_observed_summary.csv'
fieldnames = list(results_summary[0].keys()) if results_summary else []
with csv_path.open('w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=fieldnames)
    w.writeheader()
    w.writerows(results_summary)

# Markdown report
md = []
md.append('# RNA-seq From Paper: Galaxy Reproduction Report')
md.append('')
md.append(f'- generated_utc: `{datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}`')
md.append(f'- galaxy_url: `{base}`')
md.append(f'- history_name: `{history_name}`')
md.append(f'- history_id: `{history_id}`')
md.append(f'- imported_workflow_id: `{workflow_id}`')
md.append('')
md.append('## Execution Summary')
md.append('')
md.append('- New Galaxy history was created and populated with all paper SRR FASTQs from PRJNA904261 and PRJNA1086003.')
md.append('- Local workflow `configs/rna_seq_from_paper_master.ga` was imported and invoked for all four paper comparisons.')
md.append('- STAR reference selector was set to `GCA_002759435.3` and annotation GTF uploaded from NCBI.')
md.append('')
md.append('## Comparison Against Published Paper Values')
md.append('')
md.append('| comparison | observed DEG count (thresholded) | published DEG count | observed SCF1 log2FC | published SCF1 log2FC | observed ALS4112 log2FC | published ALS4112 log2FC | published R2 | published direction agreement |')
md.append('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
for r in results_summary:
    md.append(
        '| {comparison_key} | {observed_deg_count_thresholded} | {published_deg_count_thresholded} | {observed_scf1_log2fc} | {published_scf1_log2fc} | {observed_als4112_log2fc} | {published_als4112_log2fc} | {published_r2} | {published_direction_agreement_pct} |'.format(**r)
    )

md.append('')
md.append('## Notes')
md.append('')
md.append('- This report compares directly computable outputs from the executed workflow to values explicitly reported in Anton et al. 2025.')
md.append('- Published R2 and direction-agreement values require published supplementary fold-change tables for exact recomputation; those tables are not part of this workflow output set.')
md.append('- For Santana comparisons, published mapped-gene counts are reported for reference context (203 and 165).')
md.append('')
md.append('## Output Files')
md.append('')
md.append('- `paper_vs_observed_summary.json`')
md.append('- `paper_vs_observed_summary.csv`')
for c in comparisons:
    md.append(f'- `{c["key"]}__annotated_deseq2_results.tsv`')

(out_dir / 'paper_vs_observed_report.md').write_text('\n'.join(md) + '\n')

# ---------- 12) Persist metadata/manifests ----------
ids = {
    'history_name': history_name,
    'history_id': history_id,
    'imported_workflow_id': workflow_id,
    'comparisons': [
        {
            'comparison_key': rec['comparison_key'],
            'invocation_id': rec['invocation_id'],
            'annotated_deseq2_results_id': rec['annotated_deseq2_results_id'],
            'normalized_counts_id': rec['normalized_counts_id'],
            'deseq2_plots_id': rec['deseq2_plots_id'],
            'volcano_plot_id': rec['volcano_plot_id'],
        }
        for rec in final_invocation_records
    ],
    'condition_collections': condition_collection_ids,
    'gtf_dataset_id': name_to_hda['GCA_002759435.3_Cand_auris_B8441_V3_genomic.gtf.gz'],
}
save_json(meta_dir / 'galaxy_run_ids.json', ids)

# Update run_manifest
manifest_path = run / 'run_manifest.yaml'
manifest = manifest_path.read_text().splitlines()
out_lines = []
for line in manifest:
    if line.startswith('status:'):
        out_lines.append('status: completed')
    elif line.startswith('tool_name:'):
        out_lines.append('tool_name: "Galaxy Workflow"')
    elif line.startswith('tool_id:'):
        out_lines.append(f'tool_id: "{workflow_id}"')
    elif line.startswith('tool_version:'):
        out_lines.append('tool_version: "local imported ga"')
    elif line.startswith('history_name:'):
        out_lines.append(f'history_name: "{history_name}"')
    elif line.startswith('history_id:'):
        out_lines.append(f'history_id: "{history_id}"')
    else:
        out_lines.append(line)
manifest_path.write_text('\n'.join(out_lines) + '\n')

# Journal update
journal = run / 'journal.md'
with journal.open('a') as j:
    j.write(f'\n### {datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")} - Full Galaxy execution completed\n')
    j.write(f'- Created history `{history_name}` (`{history_id}`).\n')
    j.write(f'- Imported workflow `{workflow_id}` from `configs/rna_seq_from_paper_master.ga`.\n')
    j.write(f'- Invoked 4 comparisons and collected DE outputs.\n')
    j.write(f'- Report: `outputs/paper_vs_observed_report.md`.\n')

print(json.dumps({'history_id': history_id, 'workflow_id': workflow_id, 'comparisons': [r['comparison_key'] for r in results_summary]}, indent=2))
PY
