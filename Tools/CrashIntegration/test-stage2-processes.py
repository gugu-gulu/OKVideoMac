"""Real process admission tests, using only copied Release acceptance bundles."""
import fcntl
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time

ROOT=Path('/private/tmp/OKVideoMac-CrashIntegration')
APP=ROOT/'Stage2Retry3/OKVideoMac.app'
PROBE=ROOT/'instance-probe'
ID='com.okvideomac.OKVideoMac.acceptance8b3b'
owned=[]
cases=[]
extra_pids=[]

def running():
    return set(json.loads(subprocess.check_output([str(PROBE),'list',ID],text=True)))

def wait_until(predicate, timeout=15):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        value=predicate()
        if value:return value
        time.sleep(.05)
    raise AssertionError('Acceptance predicate timed out')

def workspace():
    return Path(tempfile.mkdtemp(prefix='OKVideoMac-8B3B-crash-stage2-',dir='/private/tmp'))

def launch(root, name):
    env=os.environ.copy()
    env.pop('XCTestBundlePath',None);env.pop('XCTestConfigurationFilePath',None)
    env['OKVIDEOMAC_8B3B_ROOT']=str(root)
    log=(ROOT/f'logs/stage2-{name}.log').open('wb')
    p=subprocess.Popen([str(APP/'Contents/MacOS/OKVideoMac')],env=env,stdout=log,stderr=log)
    owned.append((p,log))
    wait_until(lambda:p.pid in running())
    wait_until(lambda:int(subprocess.check_output([str(ROOT/'window-probe'),str(p.pid)],text=True))>=1)
    return p

def quit_process(p, error_dialog=False):
    if error_dialog:
        wait_until(lambda:subprocess.run([str(ROOT/'alert-probe'),str(p.pid)],capture_output=True).returncode==0)
    subprocess.run([str(PROBE),'quit',str(p.pid)],check=True)
    p.wait(timeout=12)
    wait_until(lambda:p.pid not in running())

def assert_no_database_descriptor(pid, root):
    r=subprocess.run(['/usr/sbin/lsof','-a','-p',str(pid),'-Fn'],text=True,capture_output=True)
    assert str(root/'Application Support/Database/OKVideoMac.sqlite3') not in r.stdout

def passed(name):
    cases.append({'name':name,'status':'PASS'}); print('PASS:',name,flush=True)

def run():
    assert not running(), 'A pre-existing acceptance instance is running; do not alter it'
    assert not APP.exists()
    APP.parent.mkdir(parents=True,exist_ok=True)
    shutil.copytree(ROOT/'DerivedData/Build/Products/Release/OKVideoMac.app',APP,symlinks=True)
    plist=APP/'Contents/Info.plist'
    info=plistlib.loads(plist.read_bytes());info['CFBundleIdentifier']=ID
    info['CFBundleDisplayName']='OKVideoMac Crash Integration Acceptance'
    plist.write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign','--force','--sign','-','--options','runtime','--entitlements',
        str(Path.cwd()/'OKVideoMac/macOS/OKVideoMac/Supporting/OKVideoMac.dev.entitlements'),str(APP)],check=True,capture_output=True)
    subprocess.run(['codesign','--verify','--strict',str(APP)],check=True,capture_output=True)
    try:
        root=workspace(); primary=launch(root,'primary')
        database=root/'Application Support/Database/OKVideoMac.sqlite3'
        wait_until(database.exists)
        passed('ordinary isolated startup opens its own database')
        subprocess.run(['/usr/bin/open','-a',str(APP),'--env',f'OKVIDEOMAC_8B3B_ROOT={root}'],check=True)
        time.sleep(.5);assert running()=={primary.pid}
        passed('ordinary LaunchServices reopen keeps the same process')
        duplicate=launch(root,'direct-duplicate')
        assert_no_database_descriptor(duplicate.pid,root)
        quit_process(duplicate,error_dialog=True)
        passed('direct duplicate is rejected before database access')
        before=running()
        subprocess.run(['/usr/bin/open','-n','-a',str(APP),'--env',f'OKVIDEOMAC_8B3B_ROOT={root}'],check=True)
        deadline=time.monotonic()+3
        extra=set()
        while time.monotonic()<deadline:
            extra=running()-before
            if extra:break
            time.sleep(.05)
        if extra:
            assert len(extra)==1
            pid=extra.pop();extra_pids.append(pid)
            wait_until(lambda:int(subprocess.check_output([str(ROOT/'window-probe'),str(pid)],text=True))>=1)
            assert_no_database_descriptor(pid,root)
            wait_until(lambda:subprocess.run([str(ROOT/'alert-probe'),str(pid)],capture_output=True).returncode==0)
            subprocess.run([str(PROBE),'quit',str(pid)],check=True)
            wait_until(lambda:pid not in running())
            passed('forced LaunchServices duplicate is rejected before database access')
        else:
            assert running()==before=={primary.pid}
            passed('LaunchServices enforces LSMultipleInstancesProhibited even for open -n')
        quit_process(primary)
        lock_root=workspace()
        support=lock_root/'Application Support';support.mkdir(mode=0o700)
        with (support/'.instance.lock').open('w') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            blocked=launch(lock_root,'lease-conflict')
            assert not (support/'Database/OKVideoMac.sqlite3').exists()
            assert_no_database_descriptor(blocked.pid,lock_root)
            quit_process(blocked,error_dialog=True)
        passed('independent process lease blocks initialization before SQLite')
        replacement=launch(lock_root,'after-release')
        wait_until(lambda:(support/'Database/OKVideoMac.sqlite3').exists())
        quit_process(replacement)
        passed('process exit releases the lease for the next launch')
        stub=ROOT/'Stage2Retry3/OlderInstanceStub.app'
        (stub/'Contents/MacOS').mkdir(parents=True)
        shutil.copy2(PROBE,stub/'Contents/MacOS/OlderInstanceStub')
        (stub/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':ID,
            'CFBundleExecutable':'OlderInstanceStub','CFBundlePackageType':'APPL',
            'CFBundleVersion':'1','CFBundleShortVersionString':'0.0.1','LSUIElement':True}))
        subprocess.run(['codesign','--force','--sign','-',str(stub)],check=True,capture_output=True)
        log=(ROOT/'logs/stage2-older-instance.log').open('wb')
        old=subprocess.Popen([str(stub/'Contents/MacOS/OlderInstanceStub'),'serve'],stdout=log,stderr=log)
        owned.append((old,log));wait_until(lambda:old.pid in running())
        old_root=workspace(); blocked=launch(old_root,'older-process-conflict')
        assert not (old_root/'Application Support/.instance.lock').exists()
        assert not (old_root/'Application Support/Database/OKVideoMac.sqlite3').exists()
        quit_process(blocked,error_dialog=True);quit_process(old)
        passed('simulated older same-ID application without a lease blocks new database access')
        assert not running()
        (ROOT/'stage2-processes.json').write_text(json.dumps({'status':'PASS','cases':cases,
            'scope':'copied Release test host with isolated acceptance ID and private temporary data; not a delivery bundle',
            'older_process':'minimal AppKit stub, not an actual historical application binary'},indent=2)+'\n')
    finally:
        for pid in extra_pids:
            if pid in running():
                subprocess.run([str(PROBE),'quit',str(pid)],check=False)
        for p,log in owned:
            if p.poll() is None:
                p.terminate()
                try:p.wait(timeout=5)
                except subprocess.TimeoutExpired:p.kill();p.wait(timeout=5)
            log.close()

if __name__=='__main__':run()
