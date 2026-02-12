#!/usr/bin/env python3
"""
Step 1: Verify Galaxy API Connectivity
"""
import os
from bioblend.galaxy import GalaxyInstance
import json

# Load credentials from .env
GALAXY_URL = "https://usegalaxy.org"
GALAXY_API_KEY = "92fc4ca07108fe3382d52070e909d732"

def verify_connection():
    """Verify connection to Galaxy API"""
    print(f"Connecting to Galaxy at: {GALAXY_URL}")

    try:
        gi = GalaxyInstance(url=GALAXY_URL, key=GALAXY_API_KEY)

        # Get current user info
        user = gi.users.get_current_user()

        print(f"✅ Connection successful!")
        print(f"User: {user['email']}")
        print(f"User ID: {user['id']}")

        # Save user info
        with open('api_responses/01_user_info.json', 'w') as f:
            json.dump(user, f, indent=2)

        return gi, user

    except Exception as e:
        print(f"❌ Connection failed: {e}")
        raise

if __name__ == "__main__":
    # Create directory for API responses
    os.makedirs('api_responses', exist_ok=True)

    gi, user = verify_connection()
    print("\n✅ Phase 1.1 Complete: Galaxy API connectivity verified")
