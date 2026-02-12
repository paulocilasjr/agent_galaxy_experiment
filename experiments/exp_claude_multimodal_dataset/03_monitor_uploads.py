#!/usr/bin/env python3
"""
Step 3: Monitor Upload Status
"""
import os
import json
import time
from bioblend.galaxy import GalaxyInstance

# Galaxy credentials
GALAXY_URL = "https://usegalaxy.org"
GALAXY_API_KEY = "92fc4ca07108fe3382d52070e909d732"

def check_dataset_status(gi, dataset_id, file_name):
    """Check the status of a single dataset"""
    try:
        dataset = gi.datasets.show_dataset(dataset_id)
        state = dataset['state']
        size = dataset.get('file_size', 0)

        print(f"{file_name}:")
        print(f"  State: {state}")
        print(f"  Size: {size} bytes")

        return dataset

    except Exception as e:
        print(f"Error checking {file_name}: {e}")
        return None

def monitor_all_uploads(gi, uploaded_datasets, max_attempts=120, poll_interval=10):
    """Monitor all uploads until completion"""
    print("Monitoring uploads...")
    print("="*60)

    all_complete = False
    attempt = 0

    while not all_complete and attempt < max_attempts:
        attempt += 1
        print(f"\nPoll #{attempt} (waiting {poll_interval}s between checks)")
        print("-"*60)

        states = {}
        for file_name, info in uploaded_datasets.items():
            dataset_id = info['dataset_id']
            dataset = check_dataset_status(gi, dataset_id, file_name)

            if dataset:
                states[file_name] = dataset['state']

                # Save status
                with open(f'api_responses/03_status_{file_name.replace(".", "_")}_{attempt}.json', 'w') as f:
                    json.dump(dataset, f, indent=2)

        # Check if all are complete
        complete_states = ['ok', 'error', 'failed']
        all_complete = all([state in complete_states for state in states.values()])

        if all_complete:
            print("\n✅ All uploads reached terminal state!")
            break

        # Wait before next poll
        if not all_complete:
            time.sleep(poll_interval)

    # Final summary
    print("\n" + "="*60)
    print("FINAL STATUS:")
    print("="*60)

    final_status = {}
    for file_name, info in uploaded_datasets.items():
        dataset_id = info['dataset_id']
        dataset = gi.datasets.show_dataset(dataset_id)
        state = dataset['state']
        size = dataset.get('file_size', 0)

        print(f"{file_name}: {state} ({size:,} bytes)")
        final_status[file_name] = {
            'state': state,
            'size': size,
            'dataset_id': dataset_id
        }

    # Save final status
    with open('metadata/final_upload_status.json', 'w') as f:
        json.dump(final_status, f, indent=2)

    return final_status

def main():
    # Load uploaded datasets
    with open('metadata/uploaded_datasets.json', 'r') as f:
        uploaded_datasets = json.load(f)

    print(f"Monitoring {len(uploaded_datasets)} datasets...")

    # Connect to Galaxy
    gi = GalaxyInstance(url=GALAXY_URL, key=GALAXY_API_KEY)

    # Monitor uploads
    final_status = monitor_all_uploads(gi, uploaded_datasets)

    # Check if all succeeded
    all_ok = all([info['state'] == 'ok' for info in final_status.values()])

    if all_ok:
        print("\n✅ Phase 2 Complete: All uploads successful!")
        return True
    else:
        print("\n⚠️ Some uploads did not complete successfully")
        return False

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
