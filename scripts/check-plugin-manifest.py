#!/usr/bin/env python3
"""Check that .grok-plugin/plugin.json lists exactly the user-group skills from skills.json."""
import json
import sys
from pathlib import Path

def main():
    repo_root = Path(__file__).parent.parent
    skills_json_path = repo_root / "skills.json"
    plugin_json_path = repo_root / ".grok-plugin" / "plugin.json"
    
    # Read skills.json
    with open(skills_json_path) as f:
        skills_data = json.load(f)
    
    # Read plugin.json
    with open(plugin_json_path) as f:
        plugin_data = json.load(f)
    
    # Get all user-group skills (group is "user" or not specified)
    user_skills = []
    for skill in skills_data.get("skills", []):
        group = skill.get("group", "user")  # Default to "user" if not specified
        if group == "user":
            path = skill.get("path")
            if path:
                user_skills.append(path)
    
    # Build expected set: user-group skills, excluding cloud-deploy. kite-router
    # was pulled from the bundle in 3.5.12 (D266) until Router works end to end.
    expected_skills = set(user_skills)
    expected_skills.discard("cloud-deploy/SKILL.md")  # Remove cloud-deploy if present
    
    # Get the skills from plugin.json
    plugin_skills_list = plugin_data.get("skills", [])
    
    # Check for duplicates in plugin.json
    if len(plugin_skills_list) != len(set(plugin_skills_list)):
        duplicates = [s for s in plugin_skills_list if plugin_skills_list.count(s) > 1]
        print(f"Error: plugin.json contains duplicate skill entries: {set(duplicates)}", file=sys.stderr)
        sys.exit(1)
    
    plugin_skills = set(plugin_skills_list)
    
    # Check if they match
    if plugin_skills != expected_skills:
        missing = expected_skills - plugin_skills
        extra = plugin_skills - expected_skills
        if missing:
            print(f"Error: plugin.json is missing expected skills: {sorted(missing)}", file=sys.stderr)
        if extra:
            print(f"Error: plugin.json has unexpected skills: {sorted(extra)}", file=sys.stderr)
        sys.exit(1)
    
    # Check that all listed paths exist
    for skill_path in plugin_skills:
        full_path = repo_root / skill_path
        if not full_path.exists():
            print(f"Error: skill path does not exist: {skill_path}", file=sys.stderr)
            sys.exit(1)
    
    # kite-router must stay out until Router is done (D266).
    if "kite-router/SKILL.md" in plugin_skills:
        print("Error: kite-router/SKILL.md is pulled from the bundle (D266) but listed in plugin.json", file=sys.stderr)
        sys.exit(1)
    
    # Success
    print(f"plugin skills ok: {len(plugin_skills)}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
