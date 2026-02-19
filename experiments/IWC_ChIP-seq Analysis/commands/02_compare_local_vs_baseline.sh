#!/bin/sh
set -eu
python3 - <<'PY'
import csv
import hashlib
import json
import re
from pathlib import Path
import requests

root = Path('IWC_ChIP-seq Analysis')
api_dir = root / 'api'
out_dir = root / 'outputs'
meta_dir = root / 'metadata'
out_dir.mkdir(parents=True, exist_ok=True)

# load env
env = {}
for raw in Path('.env').read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    k, v = line.split('=', 1)
    env[k.strip()] = v.strip().strip('"').strip("'")
base = env.get('GALAXY_URL', 'https://usegalaxy.org').rstrip('/')
headers = {'x-api-key': env['GALAXY_API_KEY']}

# load ids
local_ids = json.loads((meta_dir / 'local_ga_run_ids.json').read_text())
baseline_history_id = 'bbd44e69cb8906b5a74b1a30aafedb83'
baseline_invocation_id = '2ca0bcda7a418ad4'
local_history_id = local_ids['history_id_local_ga']
local_invocation_id = local_ids['local_invocation_id']

# helper functions

def get_json(url):
    r = requests.get(url, headers=headers, timeout=120)
    r.raise_for_status()
    return r.json()

def get_text(url):
    r = requests.get(url, headers=headers, timeout=120)
    r.raise_for_status()
    return r.text

def get_bytes(url):
    r = requests.get(url, headers=headers, timeout=120)
    r.raise_for_status()
    return r.content

def first_leaf_dataset_id(collection_id):
    col = get_json(f'{base}/api/dataset_collections/{collection_id}')
    elements = col.get('elements', [])
    if not elements:
        return None
    cur = elements[0]
    while True:
        obj = cur.get('object') or {}
        if cur.get('element_type') == 'hda':
            return obj.get('id')
        if cur.get('element_type') == 'dataset_collection':
            cid = obj.get('id')
            sub = get_json(f'{base}/api/dataset_collections/{cid}')
            se = sub.get('elements', [])
            if not se:
                return None
            cur = se[0]
            continue
        return None

def dataset_details(history_id, dataset_id):
    return get_json(f'{base}/api/histories/{history_id}/contents/{dataset_id}')

def parse_mapping_stats(text):
    overall = None
    m = re.search(r'([0-9]+\.?[0-9]*)%\s+overall alignment rate', text)
    if m:
        overall = float(m.group(1))
    total_reads = None
    m2 = re.search(r'^(\d+)\s+reads; of these:', text, flags=re.M)
    if m2:
        total_reads = int(m2.group(1))
    return {'overall_alignment_rate_percent': overall, 'total_reads': total_reads}

def parse_narrowpeak(text):
    lines = [ln for ln in text.strip().splitlines() if ln.strip()]
    peak_count = len(lines)
    lengths = []
    signal_sum = 0.0
    signal_count = 0
    for ln in lines:
        parts = ln.split('\t')
        if len(parts) >= 3:
            try:
                start = int(parts[1]); end = int(parts[2])
                lengths.append(max(0, end - start))
            except Exception:
                pass
        if len(parts) >= 7:
            try:
                signal_sum += float(parts[6]); signal_count += 1
            except Exception:
                pass
    return {
        'peak_count': peak_count,
        'mean_peak_length': (sum(lengths) / len(lengths)) if lengths else None,
        'signal_value_sum': signal_sum if signal_count else None,
        'signal_value_count': signal_count,
    }

def collect_run_metrics(run_name, history_id, invocation_id, step_detail_path):
    steps = json.loads(Path(step_detail_path).read_text())
    by_label = {s.get('workflow_step_label'): s for s in steps}

    inv = get_json(f'{base}/api/invocations/{invocation_id}')
    jobs_summary = get_json(f'{base}/api/invocations/{invocation_id}/jobs_summary')
    req = get_json(f'{base}/api/invocations/{invocation_id}/request')
    report = get_json(f'{base}/api/invocations/{invocation_id}/report')

    # collections/datasets of interest
    bowtie = by_label.get('Bowtie2 map on reference', {})
    macs2 = by_label.get('Call Peaks with MACS2', {})
    macs2_summary = by_label.get('summary of MACS2', {})
    bigwig_step = by_label.get('Bigwig from MACS2', {})
    multiqc = by_label.get('MultiQC', {})

    mapping_stats_col = (bowtie.get('output_collections') or {}).get('mapping_stats', {}).get('id')
    narrow_col = (macs2.get('output_collections') or {}).get('output_narrowpeaks', {}).get('id')
    summits_col = (macs2.get('output_collections') or {}).get('output_summits', {}).get('id')
    bigwig_col = (bigwig_step.get('output_collections') or {}).get('out_file1', {}).get('id')
    summary_col = (macs2_summary.get('output_collections') or {}).get('output', {}).get('id')
    multiqc_stats_hda = (multiqc.get('outputs') or {}).get('stats', {}).get('id')

    mapping_stats_id = first_leaf_dataset_id(mapping_stats_col) if mapping_stats_col else None
    narrow_id = first_leaf_dataset_id(narrow_col) if narrow_col else None
    summits_id = first_leaf_dataset_id(summits_col) if summits_col else None
    bigwig_id = first_leaf_dataset_id(bigwig_col) if bigwig_col else None
    summary_id = first_leaf_dataset_id(summary_col) if summary_col else None

    mapping_text = get_text(f'{base}/api/histories/{history_id}/contents/{mapping_stats_id}/display') if mapping_stats_id else ''
    narrow_bytes = get_bytes(f'{base}/api/histories/{history_id}/contents/{narrow_id}/display') if narrow_id else b''
    narrow_text = narrow_bytes.decode('utf-8', errors='replace') if narrow_bytes else ''
    summits_text = get_text(f'{base}/api/histories/{history_id}/contents/{summits_id}/display') if summits_id else ''
    summary_text = get_text(f'{base}/api/histories/{history_id}/contents/{summary_id}/display') if summary_id else ''

    mapping_metrics = parse_mapping_stats(mapping_text) if mapping_text else {}
    narrow_metrics = parse_narrowpeak(narrow_text) if narrow_text else {}

    bigwig_details = dataset_details(history_id, bigwig_id) if bigwig_id else {}
    multiqc_stats_details = dataset_details(history_id, multiqc_stats_hda) if multiqc_stats_hda else {}

    run = {
        'run_name': run_name,
        'history_id': history_id,
        'invocation_id': invocation_id,
        'invocation_state': inv.get('state'),
        'invocation_steps': len(inv.get('steps', [])),
        'jobs_summary': jobs_summary,
        'report_title': report.get('title'),
        'request_inputs': req.get('inputs'),
        'tools_by_step': [
            {
                'order': s.get('order_index'),
                'label': s.get('workflow_step_label'),
                'tool_id': (s.get('jobs') or [{}])[0].get('tool_id') if s.get('jobs') else None,
            }
            for s in sorted(steps, key=lambda x: x.get('order_index', 0))
        ],
        'key_outputs': {
            'mapping_stats_dataset_id': mapping_stats_id,
            'narrowpeak_dataset_id': narrow_id,
            'summits_dataset_id': summits_id,
            'bigwig_dataset_id': bigwig_id,
            'summary_dataset_id': summary_id,
            'multiqc_stats_dataset_id': multiqc_stats_hda,
        },
        'metrics': {
            'mapping_stats': mapping_metrics,
            'narrowpeak': {
                **narrow_metrics,
                'sha256': hashlib.sha256(narrow_bytes).hexdigest() if narrow_bytes else None,
                'bytes': len(narrow_bytes),
            },
            'summits_line_count': len([ln for ln in summits_text.strip().splitlines() if ln.strip()]) if summits_text else None,
            'macs2_summary_line_count': len([ln for ln in summary_text.strip().splitlines() if ln.strip()]) if summary_text else None,
            'bigwig_file_size': bigwig_details.get('file_size'),
            'multiqc_stats_file_size': multiqc_stats_details.get('file_size'),
        },
    }
    return run

local = collect_run_metrics('local_ga_release_0_14', local_history_id, local_invocation_id, api_dir / '12_local_invocation_steps_detail.json')
baseline = collect_run_metrics('baseline_iwc_release_v1_0', baseline_history_id, baseline_invocation_id, api_dir / '13_baseline_invocation_steps_detail.json')

# compare
comp = {
    'galaxy_url': base,
    'baseline': baseline,
    'local': local,
    'comparison': {
        'same_narrowpeak_sha256': local['metrics']['narrowpeak']['sha256'] == baseline['metrics']['narrowpeak']['sha256'],
        'narrowpeak_peak_count_delta': (local['metrics']['narrowpeak']['peak_count'] or 0) - (baseline['metrics']['narrowpeak']['peak_count'] or 0),
        'narrowpeak_signal_sum_delta': (local['metrics']['narrowpeak'].get('signal_value_sum') or 0.0) - (baseline['metrics']['narrowpeak'].get('signal_value_sum') or 0.0),
        'overall_alignment_rate_delta_pct_points': (local['metrics']['mapping_stats'].get('overall_alignment_rate_percent') or 0.0) - (baseline['metrics']['mapping_stats'].get('overall_alignment_rate_percent') or 0.0),
        'summits_line_count_delta': (local['metrics'].get('summits_line_count') or 0) - (baseline['metrics'].get('summits_line_count') or 0),
        'bigwig_file_size_delta_bytes': (local['metrics'].get('bigwig_file_size') or 0) - (baseline['metrics'].get('bigwig_file_size') or 0),
    },
}

(out_dir / 'local_vs_baseline_comparison.json').write_text(json.dumps(comp, indent=2, sort_keys=True))
(meta_dir / 'local_vs_baseline_metrics_summary.json').write_text(json.dumps(comp['comparison'], indent=2, sort_keys=True))

# csv table
rows = [
    ('metric', 'baseline_iwc_release_v1_0', 'local_ga_release_0_14'),
    ('overall_alignment_rate_percent', baseline['metrics']['mapping_stats'].get('overall_alignment_rate_percent'), local['metrics']['mapping_stats'].get('overall_alignment_rate_percent')),
    ('narrowpeak_peak_count', baseline['metrics']['narrowpeak'].get('peak_count'), local['metrics']['narrowpeak'].get('peak_count')),
    ('narrowpeak_signal_value_sum', baseline['metrics']['narrowpeak'].get('signal_value_sum'), local['metrics']['narrowpeak'].get('signal_value_sum')),
    ('summits_line_count', baseline['metrics'].get('summits_line_count'), local['metrics'].get('summits_line_count')),
    ('bigwig_file_size', baseline['metrics'].get('bigwig_file_size'), local['metrics'].get('bigwig_file_size')),
    ('multiqc_stats_file_size', baseline['metrics'].get('multiqc_stats_file_size'), local['metrics'].get('multiqc_stats_file_size')),
    ('narrowpeak_sha256', baseline['metrics']['narrowpeak'].get('sha256'), local['metrics']['narrowpeak'].get('sha256')),
]
with (out_dir / 'local_vs_baseline_comparison.csv').open('w', newline='') as f:
    w = csv.writer(f)
    w.writerows(rows)

md = []
md.append('# Local `.ga` vs Baseline IWC v1.0: Final Output Comparison')
md.append('')
md.append(f'- Baseline invocation: `{baseline_invocation_id}` (history `{baseline_history_id}`)')
md.append(f'- Local invocation: `{local_invocation_id}` (history `{local_history_id}`)')
md.append('')
md.append('## Result Equivalence Verdict')
if comp['comparison']['same_narrowpeak_sha256']:
    md.append('- NarrowPeak files are byte-identical (`sha256` match).')
else:
    md.append('- NarrowPeak files are different (`sha256` mismatch).')
md.append('')
md.append('## Key Metrics')
md.append(f"- Overall alignment rate (%): baseline `{baseline['metrics']['mapping_stats'].get('overall_alignment_rate_percent')}`, local `{local['metrics']['mapping_stats'].get('overall_alignment_rate_percent')}`, delta `{comp['comparison']['overall_alignment_rate_delta_pct_points']}`")
md.append(f"- Peak count (narrowPeak lines): baseline `{baseline['metrics']['narrowpeak'].get('peak_count')}`, local `{local['metrics']['narrowpeak'].get('peak_count')}`, delta `{comp['comparison']['narrowpeak_peak_count_delta']}`")
md.append(f"- Summits line count: baseline `{baseline['metrics'].get('summits_line_count')}`, local `{local['metrics'].get('summits_line_count')}`, delta `{comp['comparison']['summits_line_count_delta']}`")
md.append(f"- BigWig file size (bytes): baseline `{baseline['metrics'].get('bigwig_file_size')}`, local `{local['metrics'].get('bigwig_file_size')}`, delta `{comp['comparison']['bigwig_file_size_delta_bytes']}`")
md.append('')
md.append('## Workflow/Tool Differences Confirmed in Executed Runs')
for b, l in zip(baseline['tools_by_step'], local['tools_by_step']):
    if b.get('label') != l.get('label') or b.get('tool_id') != l.get('tool_id'):
        md.append(f"- Step order `{b.get('order')}`: baseline `{b.get('label')}` / `{b.get('tool_id')}` vs local `{l.get('label')}` / `{l.get('tool_id')}`")

(out_dir / 'local_vs_baseline_comparison.md').write_text('\n'.join(md) + '\n')

print(json.dumps(comp['comparison'], indent=2, sort_keys=True))
PY
