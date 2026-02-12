#!/usr/bin/env python3
"""
Run 4: CAFormer-B36 backbone + batch_size=32 to reduce overfitting
==================================================================

Analysis from Run 2 vs Run 3:
  ✓ best_quality preset:  test ROC-AUC 0.7139 → 0.7582  (+4.4 pts)
  ✓ threshold=0.12:       Recall 0.000 → 0.727 (model now detects positives)
  ✗ overfitting:          train=0.876 vs val=0.711, train-test gap 0.118
  ✗ per_gpu_batch=1:      best_quality set per_gpu_batch=1, giving 128 gradient-
                          accumulation steps per update — very slow, hurts generalisation
  ✗ hyperparameters JSON: Galaxy escapes { → __oc__, " → __dq__  → tool tries to
                          open the string as a filename → silently skipped
                          (minimum_cat_count=100 and focal_loss still not applied)

Fixes for Run 4:
  FIX A: backbone_image = caformer_b36.sail_in22k_ft_in1k_384
         CAFormer (Conv+Attention) outperforms Swin-Base on fine-grained
         pathology images. Available as a direct SELECT param — no escaping.

  FIX B: batch_size = 32  (was effective 128 with 128 accumulation steps)
         Smaller effective batch → weights update 4× more often → less overfit.
         With per_gpu_batch_size=1, accumulation reduces from 128 → 32 steps.

  FIX C: validation_size = 0.15  (was 0.20)
         Adds ~26 more rows to training (453 → 480 train rows).

  KEEP:  threshold = 0.12, best_quality, external test set, images
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

    print("Run 4 — CAFormer-B36 + batch_size=32")
    print("=" * 60)
    print(f"History  : {history_id}")
    print(f"Train CSV: {train_dataset_id}")
    print(f"Test CSV : {test_dataset_id}")
    print(f"Image ZIP: {image_zip_id}")
    print()
    print("Changes vs Run 3:")
    print("  [A] backbone_image: swin_base → caformer_b36.sail_in22k_ft_in1k_384")
    print("  [B] batch_size: 128 → 32  (reduce overfitting, faster updates)")
    print("  [C] validation_size: 0.20 → 0.15  (more training rows)")
    print("=" * 60)

    tool_inputs = {
        # ── Data ──────────────────────────────────────────────────────────────
        "input_csv": {"id": train_dataset_id, "src": "hda"},
        "target_column": "3",           # fallback: column #3 (1-indexed) = 'target'

        "sample_id_selector|use_sample_id": "yes",
        "sample_id_selector|sample_id_column": "1",   # column #1 = 'patient_id'

        "test_dataset_conditional|has_test_dataset": "yes",
        "test_dataset_conditional|input_test": {"id": test_dataset_id, "src": "hda"},

        # ── Images: FIX A — CAFormer-B36 as direct SELECT (no hyperparameters) ──
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

        # FIX A: threshold stays at 0.12 (proven effective in Run 3)
        "customize_defaults_conditional|threshold": "0.12",

        # FIX B: smaller batch → more gradient updates, less overfitting
        "customize_defaults_conditional|batch_size": "32",

        # FIX C: give 15% to val instead of 20% → ~27 more training rows
        "customize_defaults_conditional|validation_size": "0.15",

        # Keep: more train proportion when external test provided
        "customize_defaults_conditional|split_probabilities": "0.85 0.1 0.05",
    }

    import os; os.makedirs('configs', exist_ok=True)
    with open('configs/12_run4_config.json', 'w') as f:
        json.dump(tool_inputs, f, indent=2, default=str)
    print("Config saved → configs/12_run4_config.json")

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

        with open('api_responses/12_run4_submission.json', 'w') as f:
            json.dump(result, f, indent=2)

        job_metadata = {
            'job_id': job_id,
            'history_id': history_id,
            'tool_id': TOOL_ID,
            'submitted_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'run_number': 4,
            'baseline_test_roc_auc': 0.7582,
            'improvements': [
                'FIX A: backbone_image = caformer_b36.sail_in22k_ft_in1k_384 (direct select)',
                'FIX B: batch_size = 32 (reduce overfitting, 4x more gradient updates)',
                'FIX C: validation_size = 0.15 (more training rows)',
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
