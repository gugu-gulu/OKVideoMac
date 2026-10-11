#!/usr/bin/env python3
import hashlib,json,pathlib,re,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
APP=ROOT/'build/CrashVisibilityPrototype.app'
manifest=json.loads((ROOT/'build/symbol-manifest.json').read_text())
def uuid(path):
    return re.findall(r'UUID: ([A-Fa-f0-9-]+) \(([^)]+)\)',subprocess.check_output(['xcrun','dwarfdump','--uuid',str(path)],text=True))
teams=set()
for item in manifest:
    binary=APP/item['path'];dsym=ROOT/'build/symbols'/(binary.name+'.dSYM')
    expected=[(item['uuid'],'arm64')]
    assert uuid(binary)==expected and uuid(dsym)==expected, 'binary/dSYM UUID mismatch'
    dwarf=dsym/'Contents/Resources/DWARF'/binary.name
    assert dwarf.stat().st_size>1000
    lines=subprocess.check_output(['xcrun','dwarfdump','--debug-line',str(dsym)],text=True)
    assert ('CrashFixture.c' if binary.suffix=='.dylib' else 'Entry.swift') in lines, 'missing own-source line tables'
    subprocess.run(['codesign','--verify','--strict','--verbose=2',str(binary if binary.suffix=='.dylib' else APP)],check=True)
    details=subprocess.run(['codesign','-dv','--verbose=4',str(binary if binary.suffix=='.dylib' else APP)],capture_output=True,text=True,check=True).stderr
    assert 'runtime' in details and 'Authority=Developer ID Application:' in details
    teams.add(re.search(r'TeamIdentifier=(.+)',details).group(1))
    entitlements=subprocess.run(['codesign','-d','--entitlements',':-',str(binary if binary.suffix=='.dylib' else APP)],capture_output=True,text=True,check=True)
    assert 'disable-library-validation' not in entitlements.stdout
    linked=subprocess.check_output(['otool','-L',str(binary)],text=True)
    assert '/Users/' not in '\n'.join(linked.splitlines()[1:]), 'absolute build-path load command'
    item['sha256']=hashlib.sha256(binary.read_bytes()).hexdigest()
# Both dependencies are linked statically; only the intentionally loaded C fixture is embedded.
assert len(teams)==1 and 'not set' not in teams
assert sorted(p.name for p in (APP/'Contents/Frameworks').iterdir())==['libCVPCrashFixture.dylib']
(ROOT/'build/package-verification.json').write_text(json.dumps({'result':'PASS','signing':'Developer ID + Hardened Runtime; local prototype, no timestamp','notarization':'NOT_TESTED — local prototype','images':manifest},ensure_ascii=False,indent=2))
print('PASS: exact images, Release line tables, UUIDs, strict signature, Hardened Runtime, load commands')
