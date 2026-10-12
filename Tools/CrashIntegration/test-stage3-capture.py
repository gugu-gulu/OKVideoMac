"""Synthetic capture gate for the actual formal App entry, with isolated data."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import resource
import shutil
import stat
import subprocess
import tempfile
import time

ROOT=Path('/private/tmp/OKVideoMac-CrashIntegration')
ID='com.okvideomac.OKVideoMac.acceptance8b3b'
APP=Path(tempfile.mkdtemp(prefix='Stage3-',dir=ROOT))/'OKVideoMac.app'
EXE=APP/'Contents/MacOS/OKVideoMac'
cases=[]
owned=[]

def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))

def workspace():return Path(tempfile.mkdtemp(prefix='OKVideoMac-8B3B-crash-stage3-',dir='/private/tmp'))

def environment(root):
    env=os.environ.copy();env.pop('XCTestBundlePath',None);env.pop('XCTestConfigurationFilePath',None)
    env['OKVIDEOMAC_8B3B_ROOT']=str(root);return env

def call(root,*args):
    result=subprocess.run([str(EXE),*args],env=environment(root),capture_output=True,text=True,timeout=20,preexec_fn=no_core)
    name=f'stage3-process-{len(list((ROOT/"logs").glob("stage3-process-*.log")))}.log'
    (ROOT/'logs'/name).write_text(result.stdout+result.stderr)
    return result

def export(root):
    result=call(root,'--diagnostic-export');assert result.returncode==0,result.stderr[-500:]
    data=json.loads(result.stdout.strip().splitlines()[-1]);assert data['businessInitialized'] is False
    assert data['consent'] is False
    return data

def slot(root):
    return root/'Application Support/Diagnostics/CrashReports/raw/com.plausiblelabs.crashreporter.data'/ID/'live_report.plcrash'

def passed(name,**details):
    cases.append({'name':name,'status':'PASS',**details});print('PASS:',name,flush=True)

def crash(root,stage,kind='swift',*extra):
    result=call(root,'--diagnostic-crash-stage',stage,'--diagnostic-crash-kind',kind,*extra)
    assert result.returncode<0,(stage,kind,result.returncode,result.stderr[-500:])
    raw=slot(root)
    assert 0<raw.stat().st_size<=1_048_576
    assert stat.S_IMODE(raw.stat().st_mode)==0o600
    for directory in (root/'Application Support/Diagnostics/CrashReports').rglob('*'):
        if directory.is_dir():assert stat.S_IMODE(directory.stat().st_mode)==0o700,directory
    data=export(root)
    assert data['captureAvailable'] is True and data['recovered'] is True and data['recoveryFailed'] is False
    assert len(data['reports'])==1
    assert raw.stat().st_size==0,'Only the empty private capture slot may remain after recovery'
    record=data['reports'][0]
    assert set(record)=={'id','timestamp','version','build','osVersion','architecture','signal','signalCode','threads','images'}
    serialized=json.dumps(record)
    for forbidden in ['/Users/','token=secret','DO_NOT_SEND','example.invalid','Application Support']:
        assert forbidden not in serialized,forbidden
    assert record['architecture']=='arm64'
    crashed=[t for t in record['threads'] if t['crashed']]
    assert len(crashed)==1 and crashed[0]['frames']
    assert any(i['uuid']==main_uuid and i.get('vmaddr')==0x100000000 for i in record['images'])
    pending=root/'Application Support/Diagnostics/CrashReports/pending'
    for file in pending.glob('*.json'):assert stat.S_IMODE(file.stat().st_mode)==0o600
    again=export(root)
    assert again['reports'][0]['id']==record['id']
    assert again['recovered'] is False and again['recoveryFailed'] is False
    return record,crashed[0]

def ready_with_unavailable_capture(root):
    log=(ROOT/'logs/stage3-unavailable-business.log').open('wb')
    p=subprocess.Popen([str(EXE)],env=environment(root),stdout=log,stderr=log)
    owned.append((p,log));deadline=time.monotonic()+20
    database=root/'Application Support/Database/OKVideoMac.sqlite3'
    while time.monotonic()<deadline and p.poll() is None:
        if database.exists() and int(subprocess.check_output([str(ROOT/'window-probe'),str(p.pid)],text=True))==1:break
        time.sleep(.05)
    assert database.exists() and p.poll() is None
    subprocess.run([str(ROOT/'instance-probe'),'quit',str(p.pid)],check=True)
    p.wait(timeout=12)

shutil.copytree(ROOT/'DerivedData/Build/Products/Release/OKVideoMac.app',APP,symlinks=True)
info_path=APP/'Contents/Info.plist';info=plistlib.loads(info_path.read_bytes());info['CFBundleIdentifier']=ID
info_path.write_bytes(plistlib.dumps(info))
fixture=APP/'Contents/Frameworks/libCrashAcceptanceFixture.dylib'
subprocess.run(['xcrun','clang','-arch','arm64','-mmacosx-version-min=12.0','-dynamiclib','-O2','-g',
    '-fno-omit-frame-pointer','-install_name','@rpath/libCrashAcceptanceFixture.dylib',
    'Tools/CrashIntegration/CrashFixture.c','-o',str(fixture)],check=True)
subprocess.run(['python3','OKVideoMac/macOS/OKVideoMac/Scripts/crash-image-metadata.py',str(APP)],check=True)
subprocess.run(['codesign','--force','--sign','-','--options','runtime',str(fixture)],check=True,capture_output=True)
subprocess.run(['codesign','--force','--sign','-','--options','runtime','--entitlements',
    'OKVideoMac/macOS/OKVideoMac/Supporting/OKVideoMac.dev.entitlements',str(APP)],check=True,capture_output=True)
subprocess.run(['codesign','--verify','--strict',str(APP)],check=True,capture_output=True)
import re
main_uuid=re.search(r'UUID: ([A-Fa-f0-9-]+)',subprocess.check_output(['xcrun','dwarfdump','--uuid',str(EXE)],text=True)).group(1).upper()
try:
    root=workspace();fresh=export(root)
    assert fresh['captureAvailable'] and not fresh['recovered'] and not fresh['recoveryFailed'] and not fresh['reports']
    assert slot(root).stat().st_size==0 and stat.S_IMODE(slot(root).stat().st_mode)==0o600
    assert not (root/'Application Support/Database/OKVideoMac.sqlite3').exists()
    passed('fresh capture installs without opening SQLite or granting upload')
    clean=export(root);assert not clean['recoveryFailed'] and not clean['reports']
    passed('empty prepared slot does not become a recovery report on clean restart')
    for stage,kind in [('entry','swift'),('app-init','swift'),('business-bootstrap','swift'),('entry','c'),('business-ready','c'),('native-thread','c')]:
        root=workspace();record,thread=crash(root,stage,kind)
        database=root/'Application Support/Database/OKVideoMac.sqlite3'
        assert database.exists()==(stage in ['business-ready','native-thread'])
        assert record['version']=='0.8.4' and record['build']=='137'
        if stage=='native-thread':assert thread['number']!=0
        passed(f'{kind} crash at {stage}: capture, filtering, UUID/VM address and local persistence',crashed_thread=thread['number'])
    root=workspace();record,_=crash(root,'entry','swift','--diagnostic-test-version','0.8.3','--diagnostic-test-build','136')
    assert record['version']=='0.8.3' and record['build']=='136'
    passed('original crash-time metadata survives a newer-version recovery launch',scope='test metadata override, not a historical-binary upgrade')
    for payload,label in [(b'malformed','malformed'),(b'x'*1_048_577,'oversized')]:
        root=workspace();export(root);slot(root).write_bytes(payload)
        data=export(root)
        assert data['captureAvailable'] and data['recoveryFailed'] and not data['recovered'] and not data['reports']
        assert slot(root).stat().st_size==0
        passed(f'{label} raw report is purged without a startup loop')
    root=workspace();diagnostics=root/'Application Support/Diagnostics';diagnostics.mkdir(parents=True,mode=0o700)
    (diagnostics/'CrashReports').write_bytes(b'not-a-directory')
    data=export(root);assert not data['captureAvailable'] and not data['reports']
    ready_with_unavailable_capture(root)
    passed('unavailable diagnostics continue into real SQLite/player startup and normal quit')
    root=workspace();worker=call(root,'--diagnostics-upload-worker')
    assert worker.returncode==64 and not (root/'Application Support').exists()
    passed('reserved worker dispatch bypasses context, capture and business initialization')
    result={'status':'PASS','cases':cases,'configuration':'isolated Release acceptance, not a delivery bundle',
        'app_path':str(APP),'binary_sha256':hashlib.sha256(EXE.read_bytes()).hexdigest(),
        'main_uuid':main_uuid,'upstream_capture_version':'1.12.2','sentry_sdk_linked':False,
        'faults_compile_guard':'OKVIDEO_CRASH_ACCEPTANCE plus explicit acceptance identity/data capability'}
    (ROOT/'stage3-capture.json').write_text(json.dumps(result,indent=2)+'\n')
finally:
    for p,log in owned:
        if p.poll() is None:p.terminate();p.wait(timeout=5)
        log.close()
