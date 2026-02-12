#!/usr/bin/env python3
"""
Step 5: Configure and Submit Multimodal Learner Training Job
"""
import json
import time
from bioblend.galaxy import GalaxyInstance

GALAXY_URL = "https://usegalaxy.org"
GALAXY_API_KEY = "92fc4ca07108fe3382d52070e909d732"
TOOL_ID = "toolshed.g2.bx.psu.edu/repos/goeckslab/multimodal_learner/multimodal_learner/0.1.5"

def main():
    gi = GalaxyInstance(url=GALAXY_URL, key=GALAXY_API_KEY)

    # Load metadata
    with open('metadata/uploaded_datasets.json', 'r') as f:
        datasets = json.load(f)

    with open('metadata/column_config.json', 'r') as f:
        column_config = json.load(f)

    with open('api_responses/02_history_info.json', 'r') as f:
        history_info = json.load(f)

    history_id = history_info['id']

    # Extract dataset IDs
    train_dataset_id = datasets['HANCOCK_train_split.csv']['dataset_id']
    test_dataset_id = datasets['HANCOCK_test_split.csv']['dataset_id']
    image_zip_id = datasets['tma_cores_cd3_cd8_images.zip']['dataset_id']

    # Extract column indices
    target_col_idx = column_config['target_column']['index']  # 2
    patient_id_idx = column_config['patient_id_column']['index']  # 0
    cd3_image_idx = column_config['image_columns'][0]['index']  # 38
    cd8_image_idx = column_config['image_columns'][1]['index']  # 39

    print("Configuring Multimodal Learner...")
    print("="*60)
    print(f"History ID: {history_id}")
    print(f"Train Dataset: {train_dataset_id}")
    print(f"Test Dataset: {test_dataset_id}")
    print(f"Image ZIP: {image_zip_id}")
    print(f"\nColumn Configuration:")
    print(f"  Target: Column {target_col_idx}")
    print(f"  Patient ID: Column {patient_id_idx}")
    print(f"  CD3 Image Path: Column {cd3_image_idx}")
    print(f"  CD8 Image Path: Column {cd8_image_idx}")

    # Build configuration based on previous successful experiment
    tool_inputs = {
        # Training data
        "data_train": {"id": train_dataset_id, "src": "hda"},

        # Test data (separate test set)
        "data_test|data_test_selector": "separate",
        "data_test|data_test_file": {"id": test_dataset_id, "src": "hda"},

        # Target column (0-indexed)
        "target_col": str(target_col_idx),

        # Sample ID for leakage prevention
        "sample_id_col|sample_id_selector": "enabled",
        "sample_id_col|sample_id": str(patient_id_idx),

        # Image modality
        "image_data|image_selector": "enabled",
        "image_data|image_zip": {"id": image_zip_id, "src": "hda"},
        "image_data|image_col_0|image_col": str(cd3_image_idx),
        "image_data|image_col_1|image_col": str(cd8_image_idx),

        # Model configuration
        "model_config|config_selector": "yaml",
        "model_config|yaml_content": """model:
  names:
    - timm_image
    - ft_transformer
    - fusion_mlp

  timm_image:
    checkpoint_name: caformer_b36.sail_in22k_ft_in1k_384
    data_types:
      - image
    train_transforms:
      - resize_shorter_side
      - center_crop
      - trivial_augment
    val_transforms:
      - resize_shorter_side
      - center_crop
    image_size: 384

  ft_transformer:
    data_types:
      - categorical
      - numerical
    token_dim: 192
    num_blocks: 3

  fusion_mlp:
    hidden_sizes:
      - 128
    activation: leaky_relu
    dropout: 0.1

optim:
  optim_type: adamw
  lr: 0.0001
  weight_decay: 0.001
  max_epochs: 20
  batch_size: 128
  patience: 10
  val_check_interval: 0.5

env:
  num_gpus: 1
  precision: "16-mixed"
  seed: 42
  num_workers: 8
""",

        # Training settings
        "eval_metric": "roc_auc",
        "random_seed": 42,
        "time_limit": 7200,  # 2 hours
        "deterministic": True,
    }

    # Save configuration
    config_file = 'configs/08_multimodal_training_config.json'
    with open(config_file, 'w') as f:
        json.dump(tool_inputs, f, indent=2)

    print(f"\n✅ Configuration saved to: {config_file}")

    # Submit job
    print("\n" + "="*60)
    print("Submitting training job...")
    print("="*60)

    try:
        result = gi.tools.run_tool(
            history_id=history_id,
            tool_id=TOOL_ID,
            tool_inputs=tool_inputs
        )

        print("✅ Training job submitted successfully!")

        # Extract job and output information
        job_id = result['jobs'][0]['id'] if result.get('jobs') else None
        outputs = result.get('outputs', [])

        print(f"\nJob ID: {job_id}")
        print(f"Outputs: {len(outputs)} files")

        for output in outputs:
            print(f"  - {output['name']} ({output['id']})")

        # Save submission result
        with open('api_responses/08_training_submission.json', 'w') as f:
            json.dump(result, f, indent=2)

        # Save job metadata
        job_metadata = {
            'job_id': job_id,
            'history_id': history_id,
            'tool_id': TOOL_ID,
            'submitted_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'outputs': [{'id': o['id'], 'name': o['name']} for o in outputs]
        }

        with open('metadata/training_job.json', 'w') as f:
            json.dump(job_metadata, f, indent=2)

        print("\n" + "="*60)
        print("✅ Phase 5 Complete: Training job submitted")
        print("="*60)
        print(f"Job ID: {job_id}")
        print(f"Expected runtime: ~30-120 minutes")
        print(f"\nMetadata saved to: metadata/training_job.json")

        return True

    except Exception as e:
        print(f"❌ Failed to submit job: {e}")
        return False

if __name__ == "__main__":
    import os
    os.makedirs('configs', exist_ok=True)
    success = main()
    exit(0 if success else 1)
