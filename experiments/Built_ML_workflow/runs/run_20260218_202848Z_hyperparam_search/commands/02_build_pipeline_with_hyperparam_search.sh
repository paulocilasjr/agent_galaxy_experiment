#!/bin/sh
set -eu
# Build chain: pipeline builder -> SearchCV -> prediction(x2) -> confusion plots(x2), then extract workflow.
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
out = run / 'outputs'; out.mkdir(parents=True, exist_ok=True)

env = {}
for raw in Path('.env').read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    k, v = line.split('=', 1)
    env[k.strip()] = v.strip().strip('"').strip("'")
base = env.get('GALAXY_URL', 'https://usegalaxy.org').rstrip('/')
headers = {'x-api-key': env['GALAXY_API_KEY']}

ids = json.loads((meta / 'uploaded_dataset_ids.json').read_text())
hid = ids['history_id']
name_to_id = ids['name_to_id']

def save(name, obj):
    (api / name).write_text(json.dumps(obj, indent=2, sort_keys=True))

def get_json(url, **kwargs):
    r = requests.get(url, headers=headers, timeout=kwargs.pop('timeout', 120), **kwargs)
    r.raise_for_status()
    return r.json()

def dataset_details(did):
    return get_json(f'{base}/api/histories/{hid}/contents/{did}')

def run_tool(tag, tool_id, inputs):
    payload = {'history_id': hid, 'tool_id': tool_id, 'inputs': inputs}
    (conf / f'{tag}_payload.json').write_text(json.dumps(payload, indent=2, sort_keys=True))
    r = requests.post(f'{base}/api/tools', headers=headers, json=payload, timeout=240)
    body = None
    try:
        body = r.json()
    except Exception:
        body = {'raw_text': r.text}
    save(f'{tag}_submit.json', {'status': r.status_code, 'json': body})
    r.raise_for_status()
    return body, body['jobs'][0]['id']

def poll(tag, job_id):
    for i in range(1, 181):
        j = get_json(f'{base}/api/jobs/{job_id}', timeout=60)
        save(f'{tag}_job_poll_{i:03d}.json', j)
        if j.get('state') in ('ok', 'error', 'deleted'):
            return j
        time.sleep(5)
    raise RuntimeError(f'{tag} timeout: {job_id}')

def download_dataset(did, target, binary=False):
    r = requests.get(f'{base}/api/histories/{hid}/contents/{did}/display', headers=headers, timeout=240)
    r.raise_for_status()
    if binary:
        target.write_bytes(r.content)
    else:
        target.write_text(r.text)

def parse_prediction_values(tsv_path):
    rows = tsv_path.read_text().splitlines()
    if not rows:
        return []
    vals = []
    for line in rows[1:]:
        if not line.strip():
            continue
        vals.append(line.split('\t')[0].strip())
    return vals

def parse_response_values(dataset_id):
    text = requests.get(f'{base}/api/histories/{hid}/contents/{dataset_id}/display', headers=headers, timeout=120).text
    lines = text.splitlines()
    if not lines:
        return []
    header = lines[0].split('\t')
    idx = header.index('Response') if 'Response' in header else len(header) - 1
    vals = []
    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split('\t')
        if idx < len(parts):
            vals.append(parts[idx].strip())
    return vals

def confusion_counts(y_true, y_pred):
    n = min(len(y_true), len(y_pred))
    tp = tn = fp = fn = 0
    for t, p in zip(y_true[:n], y_pred[:n]):
        t1 = str(t).strip()
        p1 = str(p).strip()
        t_pos = (t1 == '1')
        p_pos = (p1 == '1')
        if t_pos and p_pos:
            tp += 1
        elif (not t_pos) and (not p_pos):
            tn += 1
        elif (not t_pos) and p_pos:
            fp += 1
        else:
            fn += 1
    acc = (tp + tn) / n if n else 0.0
    return {'n': n, 'tp': tp, 'tn': tn, 'fp': fp, 'fn': fn, 'accuracy': round(acc, 6)}

PIPE='toolshed.g2.bx.psu.edu/repos/bgruening/sklearn_build_pipeline/sklearn_build_pipeline/1.0.11.0'
SEARCH='toolshed.g2.bx.psu.edu/repos/bgruening/sklearn_searchcv/sklearn_searchcv/1.0.11.0'
PRED='toolshed.g2.bx.psu.edu/repos/bgruening/model_prediction/model_prediction/1.0.11.0'
PLOT='toolshed.g2.bx.psu.edu/repos/bgruening/plotly_ml_performance_plots/plotly_ml_performance_plots/0.4'

# Capture build schemas for traceability.
for tag, tool in [
    ('07_build_pipeline_builder', PIPE),
    ('07_build_searchcv', SEARCH),
    ('07_build_model_prediction', PRED),
    ('07_build_plotly_perf', PLOT),
]:
    r = requests.get(f'{base}/api/tools/{tool}/build', headers=headers, params={'history_id': hid}, timeout=180)
    r.raise_for_status()
    save(f'{tag}.json', r.json())

# Pipeline builder (default estimator from tool defaults)
pipe_submit, pipe_job = run_tool('08_pipeline_builder', PIPE, {})
pipe_state = poll('08_pipeline_builder', pipe_job)
if pipe_state.get('state') != 'ok':
    raise RuntimeError('Pipeline builder failed')
pipe_id = pipe_submit['outputs'][0]['id']
save('08_pipeline_builder_output_dataset.json', dataset_details(pipe_id))

# Hyperparameter search on Chowell_train_Response.
search_inputs = {
    'search_algos|selected_search_algo': 'GridSearchCV',
    'infile_estimator': {'src': 'hda', 'id': pipe_id},
    'is_deep_learning': False,
    'search_params_builder|param_set_0|sp_name': 'C',
    'search_params_builder|param_set_0|sp_list': '[0.01, 0.1, 1.0, 10.0, 100.0]',
    'search_params_builder|param_set_1|sp_name': 'max_iter',
    'search_params_builder|param_set_1|sp_list': '[1000, 2000, 4000]',
    'options|scoring|primary_scoring': 'f1_weighted',
    'options|cv_selector|selected_cv': 'default',
    'options|error_score': True,
    'options|return_train_score': False,
    'options|verbose': '0',
    'outer_split|split_mode': 'no',
    'save': 'save_estimator',
    'input_options|selected_input': 'tabular',
    'input_options|infile1': {'src': 'hda', 'id': name_to_id['Chowell_train_Response.tsv']},
    'input_options|header1': True,
    'input_options|column_selector_options_1|selected_column_selector_option': 'all_but_by_header_name',
    'input_options|column_selector_options_1|col1': 'Response',
    'input_options|infile2': {'src': 'hda', 'id': name_to_id['Chowell_train_Response.tsv']},
    'input_options|header2': True,
    'input_options|column_selector_options_2|selected_column_selector_option2': 'by_header_name',
    'input_options|column_selector_options_2|col2': 'Response',
}
search_submit, search_job = run_tool('09_searchcv', SEARCH, search_inputs)
search_state = poll('09_searchcv', search_job)
if search_state.get('state') != 'ok':
    raise RuntimeError('SearchCV failed')

search_output_details = [dataset_details(o['id']) for o in search_submit.get('outputs', [])]
save('09_searchcv_output_datasets.json', search_output_details)

model_id = None
cv_results_id = None
for d in search_output_details:
    ext = (d.get('file_ext') or '').lower()
    name = (d.get('name') or '').lower()
    if ext == 'h5mlm' or 'estimator' in name or 'model' in name:
        if model_id is None:
            model_id = d.get('id')
    if ext in ('tabular', 'tsv') or 'cv_results' in name or 'score' in name:
        if cv_results_id is None:
            cv_results_id = d.get('id')

if model_id is None:
    # Fallback: inspect history datasets created by this job.
    contents = get_json(f'{base}/api/histories/{hid}/contents', params={'details': 'all'}, timeout=180)
    for d in contents:
        if d.get('creating_job') == search_job:
            ext = (d.get('file_ext') or '').lower()
            name = (d.get('name') or '').lower()
            if model_id is None and (ext == 'h5mlm' or 'estimator' in name or 'model' in name):
                model_id = d.get('id')
            if cv_results_id is None and (ext in ('tabular', 'tsv') or 'cv_results' in name or 'score' in name):
                cv_results_id = d.get('id')

if model_id is None:
    raise RuntimeError('Could not resolve tuned model dataset from SearchCV outputs')

# Predict on Chowell test features
pred_ch_inputs = {
    'infile_estimator': {'src': 'hda', 'id': model_id},
    'method': 'predict',
    'input_options|selected_input': 'tabular',
    'input_options|infile1': {'src': 'hda', 'id': name_to_id['Chowell_test_No_Response.tsv']},
    'input_options|header1': True,
    'input_options|column_selector_options_1|selected_column_selector_option': 'all_columns',
}
pred_ch_submit, pred_ch_job = run_tool('10_predict_chowell_test', PRED, pred_ch_inputs)
if poll('10_predict_chowell_test', pred_ch_job).get('state') != 'ok':
    raise RuntimeError('Prediction Chowell test failed')
pred_ch_id = pred_ch_submit['outputs'][0]['id']

# Predict on MSK1 test features
pred_msk_inputs = {
    'infile_estimator': {'src': 'hda', 'id': model_id},
    'method': 'predict',
    'input_options|selected_input': 'tabular',
    'input_options|infile1': {'src': 'hda', 'id': name_to_id['MSK1_No_Response.tsv']},
    'input_options|header1': True,
    'input_options|column_selector_options_1|selected_column_selector_option': 'all_columns',
}
pred_msk_submit, pred_msk_job = run_tool('11_predict_msk1_test', PRED, pred_msk_inputs)
if poll('11_predict_msk1_test', pred_msk_job).get('state') != 'ok':
    raise RuntimeError('Prediction MSK1 failed')
pred_msk_id = pred_msk_submit['outputs'][0]['id']

# Confusion matrix + PR + ROC for Chowell
plot_ch_inputs = {
    'infile_input': {'src': 'hda', 'id': name_to_id['Chowell_test_Response.tsv']},
    'infile_output': {'src': 'hda', 'id': pred_ch_id},
    'infile_trained_model': {'src': 'hda', 'id': model_id},
}
plot_ch_submit, plot_ch_job = run_tool('12_plot_confusion_chowell_test', PLOT, plot_ch_inputs)
if poll('12_plot_confusion_chowell_test', plot_ch_job).get('state') != 'ok':
    raise RuntimeError('Plot Chowell failed')
plot_ch_details = [dataset_details(o['id']) for o in plot_ch_submit.get('outputs', [])]
save('12_plot_confusion_chowell_test_outputs.json', plot_ch_details)

# Confusion matrix + PR + ROC for MSK1
plot_msk_inputs = {
    'infile_input': {'src': 'hda', 'id': name_to_id['MSK1_Response.tsv']},
    'infile_output': {'src': 'hda', 'id': pred_msk_id},
    'infile_trained_model': {'src': 'hda', 'id': model_id},
}
plot_msk_submit, plot_msk_job = run_tool('13_plot_confusion_msk1_test', PLOT, plot_msk_inputs)
if poll('13_plot_confusion_msk1_test', plot_msk_job).get('state') != 'ok':
    raise RuntimeError('Plot MSK1 failed')
plot_msk_details = [dataset_details(o['id']) for o in plot_msk_submit.get('outputs', [])]
save('13_plot_confusion_msk1_test_outputs.json', plot_msk_details)

# Extract executed tool chain as Galaxy workflow.
job_ids = [
    pipe_submit['jobs'][0]['id'],
    search_submit['jobs'][0]['id'],
    pred_ch_submit['jobs'][0]['id'],
    pred_msk_submit['jobs'][0]['id'],
    plot_ch_submit['jobs'][0]['id'],
    plot_msk_submit['jobs'][0]['id'],
]
wf_payload = {
    'from_history_id': hid,
    'workflow_name': 'ML_workflow_built_pipeline_hyperparam_search',
    'job_ids': job_ids,
}
(conf / '14_extract_workflow_with_job_ids_payload.json').write_text(json.dumps(wf_payload, indent=2, sort_keys=True))
wf_resp = requests.post(f'{base}/api/workflows', headers=headers, json=wf_payload, timeout=180)
wf_resp.raise_for_status()
wf = wf_resp.json()
save('14_extract_workflow_with_job_ids.json', {'status': wf_resp.status_code, 'json': wf})
wf_id = wf['id']

wf_download = requests.get(f'{base}/api/workflows/{wf_id}/download', headers=headers, timeout=180)
wf_download.raise_for_status()
wf_json = wf_download.json()
save('15_download_built_workflow_with_job_ids.json', wf_json)
(out / 'ML_workflow_built_pipeline_hyperparam_search.ga').write_text(json.dumps(wf_json, indent=2, sort_keys=True))

# Snapshot history after full chain.
h_after = get_json(f'{base}/api/histories/{hid}/contents', params={'details': 'all'}, timeout=180)
save('16_history_contents_after_full_chain.json', h_after)

# Resolve key output IDs from plot outputs.
def resolve_plot_ids(details, fallback_ids):
    confusion = precision = roc = None
    for d in details:
        name = (d.get('name') or '').lower()
        ext = (d.get('file_ext') or '').lower()
        did = d.get('id')
        if confusion is None and (ext in ('png', 'jpg', 'jpeg', 'svg') or 'confusion' in name):
            confusion = did
            continue
        if precision is None and ('precision' in name or 'recall' in name or 'fscore' in name):
            precision = did
            continue
        if roc is None and ('roc' in name or 'auc' in name):
            roc = did
            continue
    # Fallback to known ordering from this tool: confusion, precision/recall, roc.
    ordered = [d.get('id') for d in details] if details else list(fallback_ids)
    if confusion is None and len(ordered) > 0:
        confusion = ordered[0]
    if precision is None and len(ordered) > 1:
        precision = ordered[1]
    if roc is None and len(ordered) > 2:
        roc = ordered[2]
    return confusion, precision, roc

plot_ch_ids = [o['id'] for o in plot_ch_submit.get('outputs', [])]
plot_msk_ids = [o['id'] for o in plot_msk_submit.get('outputs', [])]
conf_ch_id, pr_ch_id, roc_ch_id = resolve_plot_ids(plot_ch_details, plot_ch_ids)
conf_msk_id, pr_msk_id, roc_msk_id = resolve_plot_ids(plot_msk_details, plot_msk_ids)

# Download requested outputs.
pred_ch_file = out / 'predictions_chowell_test_hyperparam.tsv'
pred_msk_file = out / 'predictions_msk1_test_hyperparam.tsv'
conf_ch_file = out / 'confusion_matrix_chowell_test_hyperparam.png'
conf_msk_file = out / 'confusion_matrix_msk1_test_hyperparam.png'
pr_ch_file = out / 'precision_recall_fscore_chowell_test_hyperparam.html'
pr_msk_file = out / 'precision_recall_fscore_msk1_test_hyperparam.html'
roc_ch_file = out / 'roc_auc_chowell_test_hyperparam.html'
roc_msk_file = out / 'roc_auc_msk1_test_hyperparam.html'

for did, path, binary in [
    (pred_ch_id, pred_ch_file, False),
    (pred_msk_id, pred_msk_file, False),
    (conf_ch_id, conf_ch_file, True),
    (conf_msk_id, conf_msk_file, True),
    (pr_ch_id, pr_ch_file, False),
    (pr_msk_id, pr_msk_file, False),
    (roc_ch_id, roc_ch_file, False),
    (roc_msk_id, roc_msk_file, False),
]:
    if did:
        download_dataset(did, path, binary=binary)

# Confusion counts from predictions vs gold labels.
y_true_ch = parse_response_values(name_to_id['Chowell_test_Response.tsv'])
y_true_msk = parse_response_values(name_to_id['MSK1_Response.tsv'])
y_pred_ch = parse_prediction_values(pred_ch_file)
y_pred_msk = parse_prediction_values(pred_msk_file)

counts = {
    'chowell_test': confusion_counts(y_true_ch, y_pred_ch),
    'msk1_test': confusion_counts(y_true_msk, y_pred_msk),
}
(out / 'confusion_matrix_counts_hyperparam.json').write_text(json.dumps(counts, indent=2, sort_keys=True))
(out / 'confusion_matrix_counts_hyperparam.tsv').write_text(
    'cohort\tn\ttp\ttn\tfp\tfn\taccuracy\n'
    + f"chowell_test\t{counts['chowell_test']['n']}\t{counts['chowell_test']['tp']}\t{counts['chowell_test']['tn']}\t{counts['chowell_test']['fp']}\t{counts['chowell_test']['fn']}\t{counts['chowell_test']['accuracy']:.6f}\n"
    + f"msk1_test\t{counts['msk1_test']['n']}\t{counts['msk1_test']['tp']}\t{counts['msk1_test']['tn']}\t{counts['msk1_test']['fp']}\t{counts['msk1_test']['fn']}\t{counts['msk1_test']['accuracy']:.6f}\n"
)

# Input shape summary for this run.
shape_rows = ids.get('shape_rows', [])
shape_lines = ['dataset\trows\tcols\tdataset_id\thid\tstate']
for r in shape_rows:
    shape_lines.append(
        f"{r.get('name')}\t{r.get('rows_inferred')}\t{r.get('cols_inferred')}\t{r.get('dataset_id')}\t{r.get('hid')}\t{r.get('state')}"
    )
(out / 'input_shape_summary.tsv').write_text('\n'.join(shape_lines) + '\n')

summary = {
    'history_id': hid,
    'workflow_id': wf_id,
    'pipeline_estimator_id': pipe_id,
    'cv_results_id': cv_results_id,
    'tuned_model_id': model_id,
    'prediction_chowell_id': pred_ch_id,
    'prediction_msk1_id': pred_msk_id,
    'confusion_chowell_id': conf_ch_id,
    'confusion_msk1_id': conf_msk_id,
    'precision_recall_chowell_id': pr_ch_id,
    'precision_recall_msk1_id': pr_msk_id,
    'roc_auc_chowell_id': roc_ch_id,
    'roc_auc_msk1_id': roc_msk_id,
    'job_ids': {
        'pipeline_builder': pipe_job,
        'searchcv': search_job,
        'prediction_chowell': pred_ch_job,
        'prediction_msk1': pred_msk_job,
        'plot_chowell': plot_ch_job,
        'plot_msk1': plot_msk_job,
    },
    'hyperparameter_grid': {
        'C': [0.01, 0.1, 1.0, 10.0, 100.0],
        'max_iter': [1000, 2000, 4000],
    },
}
(meta / 'ml_workflow_run_summary.json').write_text(json.dumps(summary, indent=2, sort_keys=True))
(meta / 'downloaded_output_files.json').write_text(json.dumps({
    'predictions_chowell': str(pred_ch_file),
    'predictions_msk1': str(pred_msk_file),
    'confusion_chowell': str(conf_ch_file),
    'confusion_msk1': str(conf_msk_file),
    'precision_recall_chowell': str(pr_ch_file),
    'precision_recall_msk1': str(pr_msk_file),
    'roc_auc_chowell': str(roc_ch_file),
    'roc_auc_msk1': str(roc_msk_file),
}, indent=2, sort_keys=True))

# Final history snapshot.
h_final = get_json(f'{base}/api/histories/{hid}/contents', params={'details': 'all'}, timeout=180)
save('17_history_contents_final.json', h_final)

print('history_id', hid)
print('workflow_id', wf_id)
print('tuned_model_id', model_id)
print('confusion_matrix_chowell_id', conf_ch_id)
print('confusion_matrix_msk1_id', conf_msk_id)
PY
