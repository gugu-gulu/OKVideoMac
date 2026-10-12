#!/usr/bin/env python3
"""Record preferred image addresses before stripping/signing, preserving crash-time UUIDs."""
import json
from pathlib import Path
import re
import subprocess
import sys

def record(app):
    app=Path(app)
    candidates=[app/'Contents/MacOS/OKVideoMac',app/'Contents/Helpers/OKVideoMacRelauncher',
                app/'Contents/Resources/NodeRuntime/node']
    frameworks=app/'Contents/Frameworks'
    if frameworks.exists():candidates.extend(p for p in frameworks.rglob('*') if p.is_file() and not p.is_symlink())
    images={}
    for path in candidates:
        if not path.is_file() or 'Mach-O' not in subprocess.check_output(['file','-b',str(path)],text=True):continue
        uuid_output=subprocess.check_output(['xcrun','dwarfdump','--uuid',str(path)],text=True)
        match=re.search(r'UUID: ([A-Fa-f0-9-]+) \(arm64\)',uuid_output)
        if not match:raise SystemExit(f'Missing arm64 UUID: {path.name}')
        load_commands=subprocess.check_output(['otool','-l',str(path)],text=True)
        preferred=re.search(r'segname __TEXT\s+vmaddr (0x[0-9a-fA-F]+)',load_commands)
        if not preferred:raise SystemExit(f'Missing __TEXT VM address: {path.name}')
        uuid=match.group(1).upper();address=int(preferred.group(1),16)
        if uuid in images and images[uuid]!=address:raise SystemExit('Conflicting UUID/address')
        images[uuid]=address
    if not images:raise SystemExit('No executable image metadata generated')
    output=app/'Contents/Resources/CrashImageVMAddresses.json'
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(images,indent=2,sort_keys=True)+'\n')
    print(f'Recorded {len(images)} crash image UUID/VM addresses')

if __name__=='__main__':record(sys.argv[1])
