#!/usr/bin/env python3
"""
Verify all uploads are complete
"""
import json
from bioblend.galaxy import GalaxyInstance

GALAXY_URL = "https://usegalaxy.org"
GALAXY_API_KEY = "92fc4ca07108fe3382d52070e909d732"

def main():
    gi = GalaxyInstance(url=GALAXY_URL, key=GALAXY_API_KEY)

    # Load uploaded datasets
    with open('metadata/uploaded_datasets.json', 'r') as f:
        uploaded_datasets = json.load(f)

    print("Checking current dataset status...")
    print("="*60)

    all_ok = True
    final_status = {}

    for file_name, info in uploaded_datasets.items():
        dataset_id = info['dataset_id']
        dataset = gi.datasets.show_dataset(dataset_id)

        state = dataset['state']
        size = dataset.get('file_size', 0)

        status_symbol = "✅" if state == "ok" else "⚠️ "

        print(f"\n{status_symbol} {file_name}")
        print(f"  State: {state}")
        print(f"  Size: {size:,} bytes ({size / (1024**2):.2f} MB)")
        print(f"  Dataset ID: {dataset_id}")

        final_status[file_name] = {
            'state': state,
            'size': size,
            'dataset_id': dataset_id
        }

        if state != 'ok':
            all_ok = False

        # Save individual status
        with open(f'api_responses/05_final_status_{file_name.replace(".", "_")}.json', 'w') as f:
            json.dump(dataset, f, indent=2)

    # Update final status
    with open('metadata/final_upload_status.json', 'w') as f:
        json.dump(final_status, f, indent=2)

    print("\n" + "="*60)
    if all_ok:
        print("✅ All uploads completed successfully!")
        return True
    else:
        print("⚠️  Some uploads are not in 'ok' state")
        return False

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
