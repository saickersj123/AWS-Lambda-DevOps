#!/usr/bin/env python3
import re
import subprocess
import sys
from pathlib import Path

def update_packages(requirements_file='requirements-dev.txt'):
    # Read requirements file
    req_path = Path(requirements_file)
    if not req_path.exists():
        print(f"Error: {requirements_file} not found")
        return False
    
    with open(req_path, 'r') as f:
        content = f.read()
    
    # Extract package names (ignoring comments and version numbers)
    packages = []
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        # Extract package name (part before any version specifier)
        match = re.match(r'^([a-zA-Z0-9_.-]+)', line)
        if match:
            packages.append(match.group(1))
    
    if not packages:
        print(f"No packages found in {requirements_file}")
        return False
    
    print(f"Found {len(packages)} packages to update")
    
    # Update packages one by one
    updated_packages = {}
    for package in packages:
        print(f"Updating {package}...")
        try:
            subprocess.check_call([sys.executable, '-m', 'pip', 'install', '--upgrade', package])
            
            # Get installed version
            result = subprocess.check_output([sys.executable, '-m', 'pip', 'show', package])
            version_line = [line for line in result.decode('utf-8').splitlines() 
                           if line.startswith('Version:')][0]
            version = version_line.split(':', 1)[1].strip()
            updated_packages[package] = version
            print(f"  Updated {package} to version {version}")
        except Exception as e:
            print(f"  Failed to update {package}: {e}")
    
    # Update requirements file
    new_content = []
    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            new_content.append(line)
            continue
        
        match = re.match(r'^([a-zA-Z0-9_.-]+)', stripped)
        if match and match.group(1) in updated_packages:
            package = match.group(1)
            new_content.append(f"{package}>={updated_packages[package]}")
        else:
            new_content.append(line)
    
    with open(req_path, 'w') as f:
        f.write('\n'.join(new_content))
    
    print(f"\nUpdated {len(updated_packages)} packages in {requirements_file}")
    return True

if __name__ == '__main__':
    req_file = sys.argv[1] if len(sys.argv) > 1 else 'requirements-dev.txt'
    update_packages(req_file) 