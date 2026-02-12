#!/usr/bin/env python3
"""
Run 3: Improved training submission
Addresses all issues found from Run 2 analysis:

  ISSUE 1 — All classification metrics (Precision/Recall/F1/MCC) = 0
             Model predicts ALL negatives because default threshold=0.5
             but max predicted score was only ~0.33.
             FIX: Set threshold=0.12 (optimal from ROC curve inspection)

  ISSUE 2 — minimum_cat_count=100 collapses most clinical features
             With only 426 training rows and 78/22 class split, most
             clinical category values have <100 occurrences and get merged.
             FIX: Set minimum_cat_count=2

  ISSUE 3 — Hyperparameters YAML encoded as __cn__ (newline escape)
             Galaxy translates newlines → __cn__, tool tries to open it as
             a file path → silently skipped. num_gpus=1 was never applied.
             FIX: Pass hyperparameters as compact JSON (no newlines needed)

  ISSUE 4 — Focal loss not active — class imbalance (78% neg / 22% pos)
             means model is rewarded for always predicting negative.
             FIX: Enable focal loss (alpha=0.75 weights positive class)

  ISSUE 5 — Swin-Base backbone is decent but CAFormer-B36 is stronger
             for fine-grained medical/pathology imaging.
             FIX: Switch to caformer_b36.sail_in22k_ft_in1k_384

  ISSUE 6 — Only 80% of train CSV used (20% withheld for val).
             With external test set provided, the internal 20% test is
             replaced by external, so the 0.7/0.1/0.2 split becomes
             effectively 0.8/0.2. Push to 0.85/0.15 for more train data.
             FIX: split_probabilities="0.85 0.1 0.05" → tool uses 0.85/0.15

  ISSUE 7 — medium_quality preset: training completed in only ~14 min
             of the 7200s budget. Upgrade to best_quality for ensembling.
             FIX: preset=best_quality
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

    # ── Hyperparameters as compact JSON (no newlines → avoids __cn__ issue) ──
    # ISSUE 3 fix: JSON instead of YAML
    hyperparameters = json.dumps({
        "env": {
            "num_gpus": 1           # ISSUE 3 fix: force single GPU (NCCL vGPU safety)
        },
        "data": {
            "categorical": {
                "minimum_cat_count": 2   # ISSUE 2 fix: was 100, collapsed most features
            }
        },
        "optim": {
            "focal_loss": {
                "alpha": 0.75,      # ISSUE 4 fix: up-weight minority (recurrence) class
                "gamma": 2.0        # standard focal loss gamma
            }
        },
        "model": {
            "timm_image": {
                # ISSUE 5 fix: stronger pathology-friendly ViT backbone
                "checkpoint_name": "caformer_b36.sail_in22k_ft_in1k_384"
            }
        }
    }, separators=(',', ':'))   # compact, no spaces or newlines

    print("Run 3 — Improved Multimodal Training")
    print("=" * 60)
    print(f"History  : {history_id}")
    print(f"Train CSV: {train_dataset_id}")
    print(f"Test CSV : {test_dataset_id}")
    print(f"Image ZIP: {image_zip_id}")
    print(f"\nHyperparameters: {hyperparameters}")
    print("=" * 60)

    tool_inputs = {
        # ── Data ──────────────────────────────────────────────────────────────
        "input_csv": {"id": train_dataset_id, "src": "hda"},
        "target_column": "3",           # column #3 (1-indexed) = 'target'

        "sample_id_selector|use_sample_id": "yes",
        "sample_id_selector|sample_id_column": "1",   # column #1 = 'patient_id'

        "test_dataset_conditional|has_test_dataset": "yes",
        "test_dataset_conditional|input_test": {"id": test_dataset_id, "src": "hda"},

        # ── Images ────────────────────────────────────────────────────────────
        "use_images_conditional|use_images": "yes",
        "use_images_conditional|images_zip_repeat_0|images_zip": {"id": image_zip_id, "src": "hda"},
        "use_images_conditional|backbone_image": "swin_base_patch4_window7_224.ms_in22k_ft_in1k",
        "use_images_conditional|missing_image_strategy": False,

        # ── Training preset & metric ───────────────────────────────────────────
        "backbone_text": "microsoft/deberta-v3-base",
        "preset": "best_quality",       # ISSUE 7 fix: was medium_quality, headroom in budget
        "eval_metric": "roc_auc",
        "random_seed": 42,
        "time_limit": 7200,
        "deterministic": True,

        # ── Customisations ────────────────────────────────────────────────────
        "customize_defaults_conditional|customize_defaults": "yes",

        # ISSUE 1 fix: lower threshold from default 0.5 → 0.12
        # (from ROC curve: at ~0.12 score we see meaningful TPR with acceptable FPR)
        "customize_defaults_conditional|threshold": "0.12",

        # ISSUE 6 fix: more training data (tool uses 0.85/0.15 train/val
        # when external test is provided, the last value is effectively unused)
        "customize_defaults_conditional|split_probabilities": "0.85 0.1 0.05",

        # ISSUE 2+3+4+5 fix: compact JSON hyperparameters
        "customize_defaults_conditional|hyperparameters": hyperparameters,
    }

    # Save config
    import os; os.makedirs('configs', exist_ok=True)
    with open('configs/11_run3_config.json', 'w') as f:
        json.dump(tool_inputs, f, indent=2, default=str)
    print("Config saved → configs/11_run3_config.json")

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

        with open('api_responses/11_run3_submission.json', 'w') as f:
            json.dump(result, f, indent=2)

        job_metadata = {
            'job_id': job_id,
            'history_id': history_id,
            'tool_id': TOOL_ID,
            'submitted_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'run_number': 3,
            'improvements': [
                'threshold=0.12 (fix all-zero predictions)',
                'minimum_cat_count=2 (fix collapsed clinical features)',
                'hyperparameters as JSON not YAML (fix __cn__ encoding)',
                'focal_loss alpha=0.75 (fix class imbalance)',
                'CAFormer-B36 image backbone (stronger for pathology)',
                'split_probabilities 0.85/0.1/0.05 (more train data)',
                'best_quality preset (exploit unused time budget)',
            ],
            'outputs': [{'id': o['id'], 'name': o['name']} for o in outputs],
        }
        with open('metadata/training_job.json', 'w') as f:
            json.dump(job_metadata, f, indent=2)

        print("\nMetadata updated → metadata/training_job.json")
        print("Monitor: python 09_monitor_training.py")
        return True

    except Exception as e:
        print(f"Submission failed: {e}")
        import traceback; traceback.print_exc()
        return False


if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
