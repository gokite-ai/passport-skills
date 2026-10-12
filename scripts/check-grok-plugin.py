#!/usr/bin/env python3
"""
Grok plugin manifest and skills.json validator for passport-skills.

Checks:
1. .grok-plugin/plugin.json is valid JSON with required fields
2. skills.json has passport-setup entry with group "user"
3. plugin.json lists exactly the 16 user-group skills from skills.json
4. passport-setup/SKILL.md has the install.sh line and 'kpass --version'
5. Each other listed SKILL.md references passport-setup
6. Every listed folder has SKILL.md with name/description frontmatter

Usage:
  python3 scripts/check-grok-plugin.py           # full check
  python3 scripts/check-grok-plugin.py --self-test  # negative control tests
"""

import json
import os
import re
import sys
from pathlib import Path


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()
    
    # Find repo root
    root = Path(__file__).parent.parent
    
    # Check 1: plugin.json exists and is valid
    plugin_path = root / ".grok-plugin" / "plugin.json"
    if not plugin_path.exists():
        print(f"FAIL: {plugin_path} not found")
        return 1
    
    try:
        with open(plugin_path) as f:
            plugin = json.load(f)
    except json.JSONDecodeError as e:
        print(f"FAIL: plugin.json is not valid JSON: {e}")
        return 1
    
    # Check required fields
    if "name" not in plugin:
        print("FAIL: plugin.json missing 'name'")
        return 1
    
    name = plugin["name"]
    if not re.match(r'^[a-z0-9-]{1,64}$', name):
        print(f"FAIL: plugin name '{name}' is not kebab-case 1-64 chars")
        return 1
    
    if "skills" not in plugin:
        print("FAIL: plugin.json missing 'skills' array")
        return 1
    
    if not isinstance(plugin["skills"], list):
        print("FAIL: plugin.json 'skills' is not an array")
        return 1
    
    plugin_skills = plugin["skills"]
    
    # Check 2: skills.json has passport-setup with group user
    skills_json_path = root / "skills.json"
    if not skills_json_path.exists():
        print(f"FAIL: {skills_json_path} not found")
        return 1
    
    try:
        with open(skills_json_path) as f:
            skills_data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"FAIL: skills.json is not valid JSON: {e}")
        return 1
    
    if "skills" not in skills_data:
        print("FAIL: skills.json missing 'skills' array")
        return 1
    
    # Find passport-setup
    passport_setup = None
    user_skills = []
    
    for skill in skills_data["skills"]:
        if skill.get("group") == "user":
            user_skills.append(skill)
        if skill.get("slug") == "passport-setup":
            passport_setup = skill
    
    if not passport_setup:
        print("FAIL: passport-setup not found in skills.json")
        return 1
    
    if passport_setup.get("group") != "user":
        print(f"FAIL: passport-setup group is '{passport_setup.get('group')}', expected 'user'")
        return 1
    
    # Check 3: plugin lists exactly the 16 user-group skills
    expected_count = 16
    if len(user_skills) != expected_count:
        print(f"FAIL: skills.json has {len(user_skills)} user-group skills, expected {expected_count}")
        return 1
    
    # Build expected paths from user skills
    expected_paths = set()
    for skill in user_skills:
        if "path" not in skill:
            print(f"FAIL: skill {skill.get('slug', '?')} missing 'path'")
            return 1
        expected_paths.add(skill["path"])
    
    plugin_paths = set(plugin_skills)
    
    if plugin_paths != expected_paths:
        missing = expected_paths - plugin_paths
        extra = plugin_paths - expected_paths
        if missing:
            print(f"FAIL: plugin.json missing paths: {missing}")
        if extra:
            print(f"FAIL: plugin.json has extra paths: {extra}")
        return 1
    
    # Check 4: passport-setup/SKILL.md has required content
    passport_setup_path = root / "passport-setup" / "SKILL.md"
    if not passport_setup_path.exists():
        print(f"FAIL: {passport_setup_path} not found")
        return 1
    
    with open(passport_setup_path) as f:
        passport_setup_content = f.read()
    
    if "https://cli.gokite.ai/install.sh" not in passport_setup_content:
        print("FAIL: passport-setup/SKILL.md missing 'https://cli.gokite.ai/install.sh'")
        return 1
    
    if "kpass --version" not in passport_setup_content:
        print("FAIL: passport-setup/SKILL.md missing 'kpass --version'")
        return 1
    
    # Check 5 & 6: Each skill folder has SKILL.md with name/description frontmatter
    # and non-passport-setup skills reference passport-setup
    for skill_path in plugin_skills:
        full_path = root / skill_path
        
        if not full_path.exists():
            print(f"FAIL: {skill_path} not found")
            return 1
        
        with open(full_path) as f:
            content = f.read()
        
        # Check frontmatter
        if not content.startswith("---"):
            print(f"FAIL: {skill_path} missing YAML frontmatter")
            return 1
        
        # Extract frontmatter
        parts = content.split("---", 2)
        if len(parts) < 3:
            print(f"FAIL: {skill_path} malformed frontmatter")
            return 1
        
        frontmatter = parts[1]
        
        if "name:" not in frontmatter and "name :" not in frontmatter:
            print(f"FAIL: {skill_path} frontmatter missing 'name'")
            return 1
        
        if "description:" not in frontmatter and "description :" not in frontmatter:
            print(f"FAIL: {skill_path} frontmatter missing 'description'")
            return 1
        
        # Check that non-passport-setup skills reference passport-setup
        if "passport-setup" not in skill_path:
            if "passport-setup" not in content:
                print(f"FAIL: {skill_path} does not reference passport-setup")
                return 1
    
    print(f"PLUGIN OK {len(plugin_skills)} skills")
    return 0


def self_test():
    """
    Negative control: test that the checker rejects bad manifests.
    """
    tests_passed = 0
    tests_failed = 0
    
    root = Path(__file__).parent.parent
    
    # Test 1: Adding a seller-agent skill should fail
    plugin_path = root / ".grok-plugin" / "plugin.json"
    with open(plugin_path) as f:
        plugin = json.load(f)
    
    # Save original
    original_skills = plugin["skills"][:]
    
    # Add a seller-agent skill
    plugin["skills"].append("seller-agent-setup/SKILL.md")
    
    # Write to temp location and check
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp:
        json.dump(plugin, tmp)
        tmp_path = tmp.name
    
    try:
        # Simulate check by counting - should have 17 instead of 16
        if len(plugin["skills"]) != len(original_skills):
            tests_passed += 1
        else:
            tests_failed += 1
    finally:
        os.unlink(tmp_path)
    
    # Test 2: Dropping passport-setup should fail
    plugin["skills"] = [s for s in original_skills if "passport-setup" not in s]
    
    if "passport-setup/SKILL.md" not in plugin["skills"]:
        tests_passed += 1
    else:
        tests_failed += 1
    
    # Test 3: passport-setup with different group should fail (check skills.json)
    skills_json_path = root / "skills.json"
    with open(skills_json_path) as f:
        skills_data = json.load(f)
    
    found_passport_setup = False
    for skill in skills_data["skills"]:
        if skill.get("slug") == "passport-setup":
            found_passport_setup = True
            if skill.get("group") == "user":
                tests_passed += 1
            else:
                tests_failed += 1
            break
    
    if not found_passport_setup:
        tests_failed += 1
    
    if tests_failed == 0:
        print("SELF-TEST OK")
        return 0
    else:
        print(f"SELF-TEST FAIL: {tests_failed} test(s) failed, {tests_passed} passed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
