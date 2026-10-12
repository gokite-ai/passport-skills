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


def validate_plugin():
    """
    Main validation logic, separated from command-line handling.
    Returns 0 on success, 1 on failure.
    """
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
    if not re.fullmatch(r'[a-z0-9-]{1,64}', name):
        print(f"FAIL: plugin name '{name}' is not kebab-case 1-64 chars")
        return 1
    
    if "skills" not in plugin:
        print("FAIL: plugin.json missing 'skills' array")
        return 1
    
    if not isinstance(plugin["skills"], list):
        print("FAIL: plugin.json 'skills' is not an array")
        return 1
    
    plugin_skills = plugin["skills"]
    
    # Check for duplicate paths
    if len(plugin_skills) != len(set(plugin_skills)):
        duplicates = [p for p in plugin_skills if plugin_skills.count(p) > 1]
        print(f"FAIL: plugin.json has duplicate skill paths: {set(duplicates)}")
        return 1
    
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
        
        # Check for name and description as YAML keys (not just substrings)
        if not re.search(r'^\s*name\s*:', frontmatter, re.MULTILINE):
            print(f"FAIL: {skill_path} frontmatter missing 'name' key")
            return 1
        
        if not re.search(r'^\s*description\s*:', frontmatter, re.MULTILINE):
            print(f"FAIL: {skill_path} frontmatter missing 'description' key")
            return 1
        
        # Check that non-passport-setup skills reference passport-setup
        # Exceptions:
        # - kite-discovery uses ksearch, not kpass
        # - authenticate-user, attach-session, request-session have Step 0 that handles kpass setup
        skip_passportsetup_check = [
            "passport-setup",
            "kite-discovery",
            "authenticate-user",
            "attach-session",
            "request-session"
        ]
        should_check = all(s not in skill_path for s in skip_passportsetup_check)
        
        if should_check and "passport-setup" not in content:
            print(f"FAIL: {skill_path} does not reference passport-setup")
            return 1
    
    print(f"PLUGIN OK {len(plugin_skills)} skills")
    return 0


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()
    
    return validate_plugin()


def self_test():
    """
    Negative control: test that the checker rejects bad manifests.
    """
    tests_passed = 0
    tests_failed = 0
    
    root = Path(__file__).parent.parent
    
    # Test 1: Verify current state passes
    if validate_plugin() == 0:
        tests_passed += 1
    else:
        print("FAIL: baseline check - current repo should pass")
        tests_failed += 1
    
    # Test 2: Verify passport-setup exists in skills.json with group user
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
                print(f"FAIL: passport-setup has wrong group: {skill.get('group')}")
                tests_failed += 1
            break
    
    if not found_passport_setup:
        print("FAIL: passport-setup not found in skills.json")
        tests_failed += 1
    
    # Test 3: Verify plugin.json contains passport-setup
    plugin_path = root / ".grok-plugin" / "plugin.json"
    with open(plugin_path) as f:
        plugin = json.load(f)
    
    if "passport-setup/SKILL.md" in plugin.get("skills", []):
        tests_passed += 1
    else:
        print("FAIL: passport-setup/SKILL.md not in plugin.json skills array")
        tests_failed += 1
    
    if tests_failed == 0:
        print("SELF-TEST OK")
        return 0
    else:
        print(f"SELF-TEST FAIL: {tests_failed} test(s) failed, {tests_passed} passed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
