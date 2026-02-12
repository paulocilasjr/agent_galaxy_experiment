#!/usr/bin/env python3
"""
Step 2: Create Galaxy History and Upload Datasets from Zenodo
"""
import os
import json
import time
from bioblend.galaxy import GalaxyInstance

# Galaxy credentials
GALAXY_URL = "https://usegalaxy.org"
GALAXY_API_KEY = "92fc4ca07108fe3382d52070e909d732"

# Dataset URLs from Zenodo
ZENODO_URLS = {
    "HANCOCK_train_split.csv": "https://zenodo.org/records/17933596/files/HANCOCK_train_split.csv",
    "HANCOCK_test_split.csv": "https://zenodo.org/records/17933596/files/HANCOCK_test_split.csv",
    "tma_cores_cd3_cd8_images.zip": "https://zenodo.org/records/17727354/files/tma_cores_cd3_cd8_images.zip"
}

def create_history(gi):
    """Create a new Galaxy history"""
    history_name = "Claude-Multimodal-Recurrence-Prediction"

    print(f"Creating history: {history_name}")

    history = gi.histories.create_history(name=history_name)

    print(f"✅ History created!")
    print(f"History ID: {history['id']}")
    print(f"History Name: {history['name']}")

    # Save history info
    with open('api_responses/02_history_info.json', 'w') as f:
        json.dump(history, f, indent=2)

    return history

def upload_all_from_urls(gi, history_id, urls_dict):
    """Upload all files from URLs to Galaxy history using fetch API"""
    print(f"\nPreparing batch upload of {len(urls_dict)} files")

    try:
        # Build elements list for fetch API
        elements = []
        for file_name, url in urls_dict.items():
            elements.append({
                "src": "url",
                "url": url,
                "name": file_name
            })

        # Build fetch payload
        payload = {
            "history_id": history_id,
            "targets": [{
                "destination": {"type": "hdas"},
                "elements": elements
            }]
        }

        # Save fetch payload
        with open('metadata/fetch_payload.json', 'w') as f:
            json.dump(payload, f, indent=2)

        print("Submitting fetch request...")

        # Use direct API call for fetch (gi.url already has /api)
        result = gi.make_post_request(
            url=gi.url + "/tools/fetch",
            payload=payload
        )

        print(f"✅ Batch upload submitted!")

        # Parse results
        dataset_ids = []
        if result.get('outputs'):
            for output in result['outputs']:
                dataset_id = output['id']
                dataset_ids.append(dataset_id)
                print(f"Dataset ID: {dataset_id}")

        return result, dataset_ids

    except Exception as e:
        print(f"❌ Upload failed: {e}")
        raise

def monitor_upload(gi, dataset_id, file_name, max_attempts=60, poll_interval=10):
    """Monitor upload status until completion"""
    print(f"\nMonitoring upload: {file_name}")

    for attempt in range(max_attempts):
        try:
            dataset = gi.datasets.show_dataset(dataset_id)
            state = dataset['state']

            print(f"Attempt {attempt + 1}/{max_attempts}: State = {state}")

            if state == 'ok':
                print(f"✅ Upload complete: {file_name}")
                return dataset
            elif state in ['error', 'failed']:
                print(f"❌ Upload failed: {file_name}")
                print(f"Error: {dataset.get('misc_info', 'Unknown error')}")
                return dataset
            elif state in ['queued', 'running', 'new', 'uploading']:
                time.sleep(poll_interval)
            else:
                print(f"⚠️ Unknown state: {state}")
                time.sleep(poll_interval)

        except Exception as e:
            print(f"Error checking status: {e}")
            time.sleep(poll_interval)

    print(f"⚠️ Timeout waiting for upload: {file_name}")
    return None

def main():
    # Create directories
    os.makedirs('api_responses', exist_ok=True)
    os.makedirs('metadata', exist_ok=True)

    # Connect to Galaxy
    print("Connecting to Galaxy...")
    gi = GalaxyInstance(url=GALAXY_URL, key=GALAXY_API_KEY)

    # Create history
    history = create_history(gi)
    history_id = history['id']

    # Upload all datasets using batch fetch
    result, dataset_ids = upload_all_from_urls(gi, history_id, ZENODO_URLS)

    # Save upload result
    with open('api_responses/02_upload_result.json', 'w') as f:
        json.dump(result, f, indent=2)

    # Build uploaded datasets metadata
    uploaded_datasets = {}
    file_names = list(ZENODO_URLS.keys())

    for idx, file_name in enumerate(file_names):
        dataset_id = dataset_ids[idx] if idx < len(dataset_ids) else None

        # Determine file type
        if file_name.endswith('.csv'):
            file_type = 'csv'
        elif file_name.endswith('.zip'):
            file_type = 'zip'
        else:
            file_type = 'auto'

        uploaded_datasets[file_name] = {
            'dataset_id': dataset_id,
            'url': ZENODO_URLS[file_name],
            'file_type': file_type
        }

    # Save uploaded dataset metadata
    with open('metadata/uploaded_datasets.json', 'w') as f:
        json.dump(uploaded_datasets, f, indent=2)

    print("\n" + "="*60)
    print("✅ Phase 2 Complete: History created and uploads submitted")
    print("="*60)
    print(f"History ID: {history_id}")
    print(f"Total datasets uploaded: {len(uploaded_datasets)}")
    print("\nNow monitoring uploads to completion...")

    # Monitor all uploads
    dataset_status = {}
    for file_name, info in uploaded_datasets.items():
        dataset = monitor_upload(gi, info['dataset_id'], file_name)
        if dataset:
            dataset_status[file_name] = dataset
            # Save individual dataset status
            with open(f'api_responses/02_status_{file_name.replace(".", "_")}.json', 'w') as f:
                json.dump(dataset, f, indent=2)

    # Save final status
    with open('metadata/upload_status.json', 'w') as f:
        json.dump(dataset_status, f, indent=2)

    print("\n" + "="*60)
    print("✅ All uploads monitored")
    print("="*60)

    # Summary
    for file_name, dataset in dataset_status.items():
        print(f"{file_name}: {dataset['state']}")

if __name__ == "__main__":
    main()
