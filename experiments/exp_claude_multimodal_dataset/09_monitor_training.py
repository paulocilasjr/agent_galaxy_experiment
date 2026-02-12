#!/usr/bin/env python3
"""
Step 6: Monitor Training Job to Completion
"""
import json
import time
from bioblend.galaxy import GalaxyInstance

GALAXY_URL = "https://usegalaxy.org"
GALAXY_API_KEY = "92fc4ca07108fe3382d52070e909d732"

def main():
    gi = GalaxyInstance(url=GALAXY_URL, key=GALAXY_API_KEY)

    # Load job metadata
    with open('metadata/training_job.json', 'r') as f:
        job_metadata = json.load(f)

    job_id = job_metadata['job_id']
    output_ids = [o['id'] for o in job_metadata['outputs']]

    print("Monitoring training job...")
    print("="*60)
    print(f"Job ID: {job_id}")
    print(f"Started at: {job_metadata['submitted_at']}")
    print("="*60)

    # Monitoring loop
    poll_interval = 30  # 30 seconds
    max_attempts = 240  # 2 hours max (240 * 30s = 7200s)
    attempt = 0

    while attempt < max_attempts:
        attempt += 1

        # Check job status
        try:
            job = gi.jobs.show_job(job_id)
            state = job['state']
            update_time = job['update_time']

            print(f"\n[Poll #{attempt}] {time.strftime('%Y-%m-%d %H:%M:%S')}")
            print(f"  Job State: {state}")
            print(f"  Last Updated: {update_time}")

            # Save periodic status
            if attempt % 10 == 0:  # Save every 10th poll
                with open(f'api_responses/09_job_status_poll_{attempt}.json', 'w') as f:
                    json.dump(job, f, indent=2)

            # Check if terminal state
            if state in ['ok', 'error', 'deleted']:
                print(f"\n{'='*60}")
                print(f"Job reached terminal state: {state}")
                print(f"{'='*60}")

                # Save final job status
                with open('api_responses/09_job_status_final.json', 'w') as f:
                    json.dump(job, f, indent=2)

                if state == 'ok':
                    print("✅ Training completed successfully!")

                    # Check output statuses
                    print("\nChecking output files...")
                    for idx, output_id in enumerate(output_ids):
                        try:
                            dataset = gi.datasets.show_dataset(output_id)
                            print(f"  Output {idx + 1}: {dataset['name']}")
                            print(f"    State: {dataset['state']}")
                            print(f"    Size: {dataset.get('file_size', 0):,} bytes")
                        except Exception as e:
                            print(f"  Output {idx + 1}: Error checking status - {e}")

                    return True

                elif state == 'error':
                    print("❌ Training job failed!")
                    if job.get('stderr'):
                        print(f"\nError message:\n{job['stderr'][:500]}")
                    return False

            # Wait before next poll
            if state not in ['ok', 'error', 'deleted']:
                time.sleep(poll_interval)

        except Exception as e:
            print(f"Error checking job status: {e}")
            time.sleep(poll_interval)

    print("\n⚠️  Monitoring timed out after {max_attempts} attempts")
    print("Job may still be running. Check manually or run this script again.")
    return False

if __name__ == "__main__":
    success = main()
    print(f"\nMonitoring {'completed' if success else 'ended'}.")
    exit(0 if success else 1)
