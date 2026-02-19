#!/bin/sh
set -eu
# Builds the ML chain: pipeline builder -> model fit -> prediction(x2) -> confusion plots(x2), then extracts workflow.
python3 - <<'PY'
from pathlib import Path
import requests, json, time

run = Path('experiments/Built_ML_workflow/runs/run_20260218_180758Z_setup')
api = run / 'api'; conf = run / 'configs'; meta = run / 'metadata'; out = run / 'outputs'

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

def run_tool(tag, tool_id, inputs):
    payload = {'history_id': hid, 'tool_id': tool_id, 'inputs': inputs}
    (conf / f'{tag}_payload.json').write_text(json.dumps(payload, indent=2, sort_keys=True))
    r = requests.post(f'{base}/api/tools', headers=headers, json=payload, timeout=120)
    r.raise_for_status()
    j = r.json()
    save(f'{tag}_submit.json', {'status': r.status_code, 'json': j})
    return j, j['jobs'][0]['id']

def poll(tag, job_id):
    for i in range(1, 121):
        j = requests.get(f'{base}/api/jobs/{job_id}', headers=headers, timeout=60).json()
        save(f'{tag}_job_poll_{i:03d}.json', j)
        if j.get('state') in ('ok', 'error', 'deleted'):
            return j
        time.sleep(5)
    raise RuntimeError(f'{tag} timeout')

PIPE='toolshed.g2.bx.psu.edu/repos/bgruening/sklearn_build_pipeline/sklearn_build_pipeline/1.0.11.0'
FIT='toolshed.g2.bx.psu.edu/repos/bgruening/sklearn_model_fit/sklearn_model_fit/1.0.11.0'
PRED='toolshed.g2.bx.psu.edu/repos/bgruening/model_prediction/model_prediction/1.0.11.0'
PLOT='toolshed.g2.bx.psu.edu/repos/bgruening/plotly_ml_performance_plots/plotly_ml_performance_plots/0.4'

pipe_inputs={'final_estimator': {'estimator_selector': {'selected_module': 'linear_model','selected_estimator': 'LogisticRegression','text_params': 'max_iter=1000,solver="lbfgs"'}}}
pipe_submit, pipe_job = run_tool('08_pipeline_builder', PIPE, pipe_inputs)
assert poll('08_pipeline_builder', pipe_job)['state'] == 'ok'
pipe_id = pipe_submit['outputs'][0]['id']

fit_inputs={
  'infile_estimator': {'src': 'hda', 'id': pipe_id},
  'is_deep_learning': False,
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
fit_submit, fit_job = run_tool('09_model_fit', FIT, fit_inputs)
assert poll('09_model_fit', fit_job)['state'] == 'ok'
model_id = fit_submit['outputs'][0]['id']

pred_ch_inputs={
  'infile_estimator': {'src': 'hda', 'id': model_id},
  'method': 'predict',
  'input_options|selected_input': 'tabular',
  'input_options|infile1': {'src': 'hda', 'id': name_to_id['Chowell_test_No_Response.tsv']},
  'input_options|header1': True,
  'input_options|column_selector_options_1|selected_column_selector_option': 'all_columns',
}
pred_ch_submit, pred_ch_job = run_tool('10_predict_chowell_test', PRED, pred_ch_inputs)
assert poll('10_predict_chowell_test', pred_ch_job)['state'] == 'ok'
pred_ch_id = pred_ch_submit['outputs'][0]['id']

pred_msk_inputs={
  'infile_estimator': {'src': 'hda', 'id': model_id},
  'method': 'predict',
  'input_options|selected_input': 'tabular',
  'input_options|infile1': {'src': 'hda', 'id': name_to_id['MSK1_No_Response.tsv']},
  'input_options|header1': True,
  'input_options|column_selector_options_1|selected_column_selector_option': 'all_columns',
}
pred_msk_submit, pred_msk_job = run_tool('11_predict_msk1_test', PRED, pred_msk_inputs)
assert poll('11_predict_msk1_test', pred_msk_job)['state'] == 'ok'
pred_msk_id = pred_msk_submit['outputs'][0]['id']

plot_ch_inputs={
  'infile_input': {'src': 'hda', 'id': name_to_id['Chowell_test_Response.tsv']},
  'infile_output': {'src': 'hda', 'id': pred_ch_id},
  'infile_trained_model': {'src': 'hda', 'id': model_id},
}
plot_ch_submit, plot_ch_job = run_tool('12_plot_confusion_chowell_test', PLOT, plot_ch_inputs)
assert poll('12_plot_confusion_chowell_test', plot_ch_job)['state'] == 'ok'

plot_msk_inputs={
  'infile_input': {'src': 'hda', 'id': name_to_id['MSK1_Response.tsv']},
  'infile_output': {'src': 'hda', 'id': pred_msk_id},
  'infile_trained_model': {'src': 'hda', 'id': model_id},
}
plot_msk_submit, plot_msk_job = run_tool('13_plot_confusion_msk1_test', PLOT, plot_msk_inputs)
assert poll('13_plot_confusion_msk1_test', plot_msk_job)['state'] == 'ok'

job_ids=[pipe_submit['jobs'][0]['id'],fit_submit['jobs'][0]['id'],pred_ch_submit['jobs'][0]['id'],pred_msk_submit['jobs'][0]['id'],plot_ch_submit['jobs'][0]['id'],plot_msk_submit['jobs'][0]['id']]
wf_payload={'from_history_id': hid, 'workflow_name': 'ML_workflow_built_pipeline', 'job_ids': job_ids}
wr=requests.post(f'{base}/api/workflows',headers=headers,json=wf_payload,timeout=120)
wr.raise_for_status()
wf=wr.json(); wf_id=wf['id']
save('14_extract_workflow_with_job_ids.json', {'status':wr.status_code,'json':wf})
wd=requests.get(f'{base}/api/workflows/{wf_id}/download',headers=headers,timeout=120); wd.raise_for_status()
(out/'ML_workflow_built_pipeline.ga').write_text(json.dumps(wd.json(),indent=2,sort_keys=True))

(meta/'ml_workflow_run_summary.json').write_text(json.dumps({'history_id':hid,'workflow_id':wf_id,'trained_model_id':model_id},indent=2,sort_keys=True))
print('workflow_id',wf_id)
PY
