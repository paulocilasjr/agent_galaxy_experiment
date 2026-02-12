#!/usr/bin/env python3
"""
Step 10: Corrected Training Submission
Fixes from failed run (job bbd44e69cb8906b533e168e5d5747487):

  Bug 1: Wrong dataset — used test split; now uses train split
  Bug 2: Wrong parameter names — Galaxy silently ignored them; now use correct names
  Bug 3: Wrong target column — passed "1" (→ patient_id); now pass "target"
  Bug 4: NCCL multi-GPU crash — server has 3 vGPUs, NCCL fails; force num_gpus=1
"""
import json
import time
from bioblend.galaxy import GalaxyInstance

GALAXY_URL = "https://usegalaxy.org"
GALAXY_API_KEY = "92fc4ca07108fe3382d52070e909d732"
TOOL_ID = "toolshed.g2.bx.psu.edu/repos/goeckslab/multimodal_learner/multimodal_learner/0.1.5"


def main():
    gi = GalaxyInstance(url=GALAXY_URL, key=GALAXY_API_KEY)

    with open('metadata/uploaded_datasets.json', 'r') as f:
        datasets = json.load(f)
    with open('api_responses/02_history_info.json', 'r') as f:
        history_info = json.load(f)

    history_id = history_info['id']
    train_dataset_id = datasets['HANCOCK_train_split.csv']['dataset_id']   # f9cad7b01a472135e849184d64d68f38
    test_dataset_id  = datasets['HANCOCK_test_split.csv']['dataset_id']    # f9cad7b01a4721350e0fd2a678772f8b
    image_zip_id     = datasets['tma_cores_cd3_cd8_images.zip']['dataset_id']

    print("Submitting CORRECTED Multimodal Learner training job")
    print("=" * 60)
    print(f"History ID  : {history_id}")
    print(f"Train CSV   : {train_dataset_id}")
    print(f"Test CSV    : {test_dataset_id}")
    print(f"Image ZIP   : {image_zip_id}")
    print()
    print("Fixes applied vs previous failed run:")
    print("  [1] input_csv now points to TRAIN split")
    print("  [2] target_column = 'target'  (was '1' → fell back to patient_id)")
    print("  [3] Correct Galaxy parameter names for all conditionals")
    print("  [4] num_gpus=1 forced via hyperparameters (was 3 → NCCL crash)")
    print("=" * 60)

    # Extra AutoGluon hyperparameters — force single-GPU to avoid NCCL vGPU error
    hyperparameters_yaml = "env:\n  num_gpus: 1\n"

    tool_inputs = {
        # ── Input data ────────────────────────────────────────────────────────
        # FIX 1 + 2: correct param name AND correct dataset (train, not test)
        "input_csv": {"id": train_dataset_id, "src": "hda"},

        # FIX 3: Galaxy data_column params require 1-indexed integers
        # target = column 2 (0-indexed) = column 3 (1-indexed)
        "target_column": "3",

        # ── Sample ID (prevent data leakage) ──────────────────────────────────
        # patient_id = column 0 (0-indexed) = column 1 (1-indexed)
        "sample_id_selector|use_sample_id": "yes",
        "sample_id_selector|sample_id_column": "1",

        # ── Test dataset ──────────────────────────────────────────────────────
        "test_dataset_conditional|has_test_dataset": "yes",
        "test_dataset_conditional|input_test": {"id": test_dataset_id, "src": "hda"},

        # ── Image modality ────────────────────────────────────────────────────
        # FIX 2: correct conditional path for images
        "use_images_conditional|use_images": "yes",
        "use_images_conditional|images_zip_repeat_0|images_zip": {"id": image_zip_id, "src": "hda"},
        "use_images_conditional|backbone_image": "swin_base_patch4_window7_224.ms_in22k_ft_in1k",
        "use_images_conditional|missing_image_strategy": False,

        # ── Standard training settings ────────────────────────────────────────
        "backbone_text": "microsoft/deberta-v3-base",
        "preset": "medium_quality",
        "eval_metric": "roc_auc",
        "random_seed": 42,
        "time_limit": 7200,
        "deterministic": True,

        # ── FIX 4: force single GPU via hyperparameters ───────────────────────
        "customize_defaults_conditional|customize_defaults": "yes",
        "customize_defaults_conditional|hyperparameters": hyperparameters_yaml,
    }

    # Save config for reference
    with open('configs/10_corrected_training_config.json', 'w') as f:
        json.dump(tool_inputs, f, indent=2, default=str)
    print("Configuration saved to configs/10_corrected_training_config.json")

    try:
        result = gi.tools.run_tool(
            history_id=history_id,
            tool_id=TOOL_ID,
            tool_inputs=tool_inputs
        )

        job_id   = result['jobs'][0]['id'] if result.get('jobs') else None
        outputs  = result.get('outputs', [])

        print(f"\nJob submitted successfully!")
        print(f"Job ID : {job_id}")
        print(f"Outputs: {len(outputs)} files")
        for o in outputs:
            print(f"  - {o['name']}  ({o['id']})")

        # Persist API response
        with open('api_responses/10_training_submission.json', 'w') as f:
            json.dump(result, f, indent=2)

        # Update job metadata so monitor script can pick it up
        job_metadata = {
            'job_id': job_id,
            'history_id': history_id,
            'tool_id': TOOL_ID,
            'submitted_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'run_number': 2,
            'fixes': [
                'correct dataset (train not test)',
                'target_column = target',
                'correct Galaxy param names',
                'num_gpus=1 to avoid NCCL vGPU error',
            ],
            'outputs': [{'id': o['id'], 'name': o['name']} for o in outputs],
        }
        with open('metadata/training_job.json', 'w') as f:
            json.dump(job_metadata, f, indent=2)

        print(f"\nMetadata updated: metadata/training_job.json")
        print("Run  python 09_monitor_training.py  to track progress.")
        return True

    except Exception as e:
        print(f"Submission failed: {e}")
        import traceback; traceback.print_exc()
        return False


if __name__ == "__main__":
    import os
    os.makedirs('configs', exist_ok=True)
    os.makedirs('api_responses', exist_ok=True)
    success = main()
    exit(0 if success else 1)
