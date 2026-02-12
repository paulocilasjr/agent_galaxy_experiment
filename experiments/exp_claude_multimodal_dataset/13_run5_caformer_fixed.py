#!/usr/bin/env python3
"""
Run 5: CAFormer-B36 backbone — batch_size removed (deprecated key crash)
=========================================================================

Root cause of Run 4 crash:
  customize_defaults_conditional|batch_size generates BOTH:
    env.per_gpu_batch_size: 32   ← correct
    optimization.batch_size: 32  ← deprecated, doesn't exist → KeyError

  The `optimization` key no longer exists in AutoGluon 1.4 config
  (was renamed to `optim`). The tool generates both old and new keys
  when batch_size is passed, causing a fatal crash.

Good news from Run 4:
  backbone_image=caformer_b36 WAS applied — confirmed in overrides dict:
    model.timm_image.checkpoint_name = caformer_b36.sail_in22k_ft_in1k_384

Run 5 changes vs Run 3 (last successful run):
  ✓ backbone_image = caformer_b36.sail_in22k_ft_in1k_384  (confirmed working)
  ✓ threshold = 0.12                                       (keep)
  ✓ best_quality preset                                    (keep)
  ✓ validation_size = 0.15                                 (slightly more train data)
  ✗ batch_size = 32                                        (REMOVED — causes crash)
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

    history_id       = history_info['id']
    train_dataset_id = datasets['HANCOCK_train_split.csv']['dataset_id']
    test_dataset_id  = datasets['HANCOCK_test_split.csv']['dataset_id']
    image_zip_id     = datasets['tma_cores_cd3_cd8_images.zip']['dataset_id']

    print("Run 5 — CAFormer-B36 backbone (fixed: no batch_size)")
    print("=" * 60)
    print(f"History  : {history_id}")
    print(f"Train CSV: {train_dataset_id}")
    print(f"Test CSV : {test_dataset_id}")
    print(f"Image ZIP: {image_zip_id}")
    print()
    print("vs Run 3 baseline (test ROC-AUC=0.7582):")
    print("  + backbone_image = caformer_b36.sail_in22k_ft_in1k_384 (direct SELECT)")
    print("  + validation_size = 0.15  (more train rows: ~453 vs 426)")
    print("  = batch_size removed (crashed Run 4 with deprecated optim key)")
    print("  = threshold=0.12, best_quality, external test kept")
    print("=" * 60)

    tool_inputs = {
        # ── Data ──────────────────────────────────────────────────────────────
        "input_csv": {"id": train_dataset_id, "src": "hda"},
        "target_column": "3",           # column #3 (1-indexed) → 'target'

        "sample_id_selector|use_sample_id": "yes",
        "sample_id_selector|sample_id_column": "1",   # column #1 → 'patient_id'

        "test_dataset_conditional|has_test_dataset": "yes",
        "test_dataset_conditional|input_test": {"id": test_dataset_id, "src": "hda"},

        # ── Images: CAFormer-B36 via direct SELECT (confirmed applied in Run 4) ─
        "use_images_conditional|use_images": "yes",
        "use_images_conditional|images_zip_repeat_0|images_zip": {"id": image_zip_id, "src": "hda"},
        "use_images_conditional|backbone_image": "caformer_b36.sail_in22k_ft_in1k_384",
        "use_images_conditional|missing_image_strategy": False,

        # ── Model ─────────────────────────────────────────────────────────────
        "backbone_text": "microsoft/deberta-v3-base",
        "preset": "best_quality",
        "eval_metric": "roc_auc",
        "random_seed": 42,
        "time_limit": 7200,
        "deterministic": True,

        # ── Customisations ────────────────────────────────────────────────────
        "customize_defaults_conditional|customize_defaults": "yes",
        "customize_defaults_conditional|threshold": "0.12",
        "customize_defaults_conditional|validation_size": "0.15",
        "customize_defaults_conditional|split_probabilities": "0.85 0.1 0.05",
        # NOTE: batch_size intentionally omitted — causes deprecated key crash
        # NOTE: hyperparameters intentionally omitted — always escaped by Galaxy
    }

    import os; os.makedirs('configs', exist_ok=True)
    with open('configs/13_run5_config.json', 'w') as f:
        json.dump(tool_inputs, f, indent=2, default=str)
    print("Config saved → configs/13_run5_config.json")

    try:
        result = gi.tools.run_tool(
            history_id=history_id,
            tool_id=TOOL_ID,
            tool_inputs=tool_inputs
        )

        job_id  = result['jobs'][0]['id'] if result.get('jobs') else None
        outputs = result.get('outputs', [])

        print(f"\nJob submitted!")
        print(f"Job ID : {job_id}")
        for o in outputs:
            print(f"  {o['name']}  ({o['id']})")

        with open('api_responses/13_run5_submission.json', 'w') as f:
            json.dump(result, f, indent=2)

        job_metadata = {
            'job_id': job_id,
            'history_id': history_id,
            'tool_id': TOOL_ID,
            'submitted_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'run_number': 5,
            'baseline_test_roc_auc': 0.7582,
            'improvements': [
                'CAFormer-B36 backbone via direct SELECT param',
                'validation_size=0.15 (more training rows)',
                'batch_size removed (was crashing with deprecated optim key)',
            ],
            'outputs': [{'id': o['id'], 'name': o['name']} for o in outputs],
        }
        with open('metadata/training_job.json', 'w') as f:
            json.dump(job_metadata, f, indent=2)

        print("\nMetadata → metadata/training_job.json")
        print("Monitor: python 09_monitor_training.py")
        return True

    except Exception as e:
        print(f"Submission failed: {e}")
        import traceback; traceback.print_exc()
        return False


if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
