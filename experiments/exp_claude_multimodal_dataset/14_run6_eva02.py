#!/usr/bin/env python3
"""
Run 6: EVA-02 backbone @ 448px
================================
Run 5 result: Test ROC-AUC = 0.8053  (CAFormer-B36 @ 384px)

EVA-02 (eva02_base_patch14_448.mim_in22k_ft_in22k_in1k):
  - Masked Image Modeling pre-training + ImageNet-22k fine-tune x2
  - 448×448 resolution → finer spatial detail for TMA cores
  - State-of-the-art on many visual benchmarks, particularly pathology
  - Same model size class (Base) as CAFormer-B36, comparable runtime

Everything else kept identical to Run 5 (which is current best):
  preset=best_quality, threshold=0.12, validation_size=0.15, no batch_size
"""
import json, time, os
from bioblend.galaxy import GalaxyInstance

GALAXY_URL = "https://usegalaxy.org"
GALAXY_API_KEY = "92fc4ca07108fe3382d52070e909d732"
TOOL_ID = "toolshed.g2.bx.psu.edu/repos/goeckslab/multimodal_learner/multimodal_learner/0.1.5"


def main():
    gi = GalaxyInstance(url=GALAXY_URL, key=GALAXY_API_KEY)

    with open('metadata/uploaded_datasets.json') as f:
        datasets = json.load(f)
    with open('api_responses/02_history_info.json') as f:
        history_info = json.load(f)

    history_id       = history_info['id']
    train_dataset_id = datasets['HANCOCK_train_split.csv']['dataset_id']
    test_dataset_id  = datasets['HANCOCK_test_split.csv']['dataset_id']
    image_zip_id     = datasets['tma_cores_cd3_cd8_images.zip']['dataset_id']

    print("Run 6 — EVA-02 @ 448px vs CAFormer-B36 @ 384px")
    print("=" * 60)
    print(f"Baseline (Run 5): Test ROC-AUC = 0.8053  (CAFormer-B36)")
    print(f"Change: backbone_image = eva02_base_patch14_448.mim_in22k_ft_in22k_in1k")
    print("=" * 60)

    tool_inputs = {
        "input_csv": {"id": train_dataset_id, "src": "hda"},
        "target_column": "3",
        "sample_id_selector|use_sample_id": "yes",
        "sample_id_selector|sample_id_column": "1",
        "test_dataset_conditional|has_test_dataset": "yes",
        "test_dataset_conditional|input_test": {"id": test_dataset_id, "src": "hda"},

        # EVA-02 Base @ 448px — MIM pre-training + double ImageNet-22k fine-tune
        "use_images_conditional|use_images": "yes",
        "use_images_conditional|images_zip_repeat_0|images_zip": {"id": image_zip_id, "src": "hda"},
        "use_images_conditional|backbone_image": "eva02_base_patch14_448.mim_in22k_ft_in22k_in1k",
        "use_images_conditional|missing_image_strategy": False,

        "backbone_text": "microsoft/deberta-v3-base",
        "preset": "best_quality",
        "eval_metric": "roc_auc",
        "random_seed": 42,
        "time_limit": 7200,
        "deterministic": True,

        "customize_defaults_conditional|customize_defaults": "yes",
        "customize_defaults_conditional|threshold": "0.12",
        "customize_defaults_conditional|validation_size": "0.15",
        "customize_defaults_conditional|split_probabilities": "0.85 0.1 0.05",
    }

    os.makedirs('configs', exist_ok=True)
    with open('configs/14_run6_config.json', 'w') as f:
        json.dump(tool_inputs, f, indent=2, default=str)
    print("Config saved → configs/14_run6_config.json")

    result = gi.tools.run_tool(history_id=history_id, tool_id=TOOL_ID, tool_inputs=tool_inputs)
    job_id  = result['jobs'][0]['id'] if result.get('jobs') else None
    outputs = result.get('outputs', [])

    print(f"\nJob ID : {job_id}")
    for o in outputs:
        print(f"  {o['name']}  ({o['id']})")

    with open('api_responses/14_run6_submission.json', 'w') as f:
        json.dump(result, f, indent=2)

    job_metadata = {
        'job_id': job_id,
        'history_id': history_id,
        'tool_id': TOOL_ID,
        'submitted_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'run_number': 6,
        'baseline_test_roc_auc': 0.8053,
        'change': 'backbone_image = eva02_base_patch14_448.mim_in22k_ft_in22k_in1k',
        'outputs': [{'id': o['id'], 'name': o['name']} for o in outputs],
    }
    with open('metadata/training_job.json', 'w') as f:
        json.dump(job_metadata, f, indent=2)

    print("\nMonitor: python 09_monitor_training.py")
    return job_id


if __name__ == "__main__":
    main()
