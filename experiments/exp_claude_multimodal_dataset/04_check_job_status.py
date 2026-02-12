#!/usr/bin/env python3
"""
Check the status of the fetch job
"""
import json
from bioblend.galaxy import GalaxyInstance

GALAXY_URL = "https://usegalaxy.org"
GALAXY_API_KEY = "92fc4ca07108fe3382d52070e909d732"

def main():
    gi = GalaxyInstance(url=GALAXY_URL, key=GALAXY_API_KEY)

    # Load upload info
    with open('api_responses/02_upload_result.json', 'r') as f:
        upload_result = json.load(f)

    # Get job ID from jobs array
    job_id = upload_result['jobs'][0]['id']

    print(f"Checking job: {job_id}")

    # Get job details
    job = gi.jobs.show_job(job_id)

    print(f"\nJob State: {job['state']}")
    print(f"Job Created: {job['create_time']}")
    print(f"Job Updated: {job['update_time']}")

    if job.get('stderr'):
        print(f"\nSTDERR:\n{job['stderr']}")

    if job.get('stdout'):
        print(f"\nSTDOUT:\n{job['stdout']}")

    # Save job details
    with open('api_responses/04_job_status.json', 'w') as f:
        json.dump(job, f, indent=2)

    print(f"\nJob details saved to api_responses/04_job_status.json")

if __name__ == "__main__":
    main()
