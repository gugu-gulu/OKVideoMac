#!/usr/bin/env python3
"""Record UUIDs and preferred VM addresses of this build before strip/sign."""
import json, pathlib, plistlib, re, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / 'build/CrashVisibilityPrototype.app'
images = {}
manifest = []
for relative in ['Contents/MacOS/CrashVisibilityPrototype', 'Contents/Frameworks/libCVPCrashFixture.dylib']:
    binary = APP / relative
    uuid = re.search(r'UUID: ([A-Fa-f0-9-]+) \(arm64\)', subprocess.check_output(['xcrun','dwarfdump','--uuid',str(binary)],text=True)).group(1).upper()
    headers = subprocess.check_output(['otool','-l',str(binary)],text=True)
    vmaddr = int(re.search(r'segname __TEXT\s+vmaddr (0x[0-9a-fA-F]+)',headers).group(1),16)
    images[uuid] = vmaddr
    manifest.append({'path':relative,'uuid':uuid,'architecture':'arm64','vmaddr':vmaddr})
(APP/'Contents/Resources/ImageVMAddresses.json').write_text(json.dumps(images,indent=2))
(ROOT/'build/symbol-manifest.json').write_text(json.dumps(manifest,indent=2))
plist = {'CFBundleIdentifier':'com.okvideomac.CrashVisibilityPrototype','CFBundleName':'Crash Visibility Prototype',
         'CFBundleDisplayName':'Crash Visibility Prototype','CFBundleExecutable':'CrashVisibilityPrototype',
         'CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1.2','CFBundleVersion':'3',
         'LSMinimumSystemVersion':'12.0','NSHighResolutionCapable':True,
         'NSPrincipalClass':'NSApplication'}
with (APP/'Contents/Info.plist').open('wb') as f: plistlib.dump(plist,f)
