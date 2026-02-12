#!/usr/bin/env python3
"""
Step 4: Retrieve Multimodal Learner Tool Schema
"""
import json
from bioblend.galaxy import GalaxyInstance

GALAXY_URL = "https://usegalaxy.org"
GALAXY_API_KEY = "92fc4ca07108fe3382d52070e909d732"

# Multimodal Learner tool ID
TOOL_ID = "toolshed.g2.bx.psu.edu/repos/goeckslab/multimodal_learner/multimodal_learner/0.1.5"

def main():
    gi = GalaxyInstance(url=GALAXY_URL, key=GALAXY_API_KEY)

    print(f"Retrieving tool schema for: {TOOL_ID}")
    print("="*60)

    # Get tool details
    try:
        tool = gi.tools.show_tool(TOOL_ID)

        print(f"Tool Name: {tool['name']}")
        print(f"Tool ID: {tool['id']}")
        print(f"Tool Version: {tool['version']}")

        # Save full tool schema
        with open('api_responses/07_multimodal_tool_schema.json', 'w') as f:
            json.dump(tool, f, indent=2)

        print(f"\n✅ Tool schema saved to api_responses/07_multimodal_tool_schema.json")

    except Exception as e:
        print(f"❌ Failed to retrieve tool schema: {e}")
        print("\nTrying to list available tools...")

        # Search for multimodal tools
        all_tools = gi.tools.get_tools()
        multimodal_tools = [t for t in all_tools if 'multimodal' in t['name'].lower()]

        print(f"Found {len(multimodal_tools)} multimodal tools:")
        for tool in multimodal_tools:
            print(f"  - {tool['name']} ({tool['id']})")

        return False

    # Get tool build (parameters)
    try:
        print("\nRetrieving tool build information...")
        tool_build = gi.tools.build(TOOL_ID)

        with open('api_responses/07_multimodal_tool_build.json', 'w') as f:
            json.dump(tool_build, f, indent=2)

        print(f"✅ Tool build info saved to api_responses/07_multimodal_tool_build.json")

        # Extract key parameters
        print("\nKey Parameters:")
        print("-"*60)
        if 'inputs' in tool_build:
            for input_param in tool_build['inputs'][:10]:  # Show first 10
                name = input_param.get('name', 'unknown')
                param_type = input_param.get('type', 'unknown')
                print(f"  - {name} ({param_type})")

    except Exception as e:
        print(f"⚠️  Could not retrieve tool build: {e}")

    print("\n" + "="*60)
    print("✅ Phase 4 Complete: Multimodal Learner tool schema retrieved")
    print("="*60)

    return True

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
