"""Actual window/button/shortcut acceptance with only owned temporary Apps."""
import json
import os
from pathlib import Path
import plistlib
import resource
import sqlite3
import shutil
import subprocess
import tempfile
import time

ROOT=Path('/private/tmp/OKVideoMac-CrashIntegration')
CAPTURE=json.loads((ROOT/'stage3-capture.json').read_text())
OLD=Path(CAPTURE['app_path'])/'Contents/MacOS/OKVideoMac'
APP=Path(tempfile.mkdtemp(prefix='Stage4-',dir=ROOT))/'OKVideoMac.app'
EXE=APP/'Contents/MacOS/OKVideoMac';UI=ROOT/'owned-ui-probe'
ID='com.okvideomac.OKVideoMac.acceptance8b3b'
cases=[];owned=[]

def wait(predicate,timeout=20):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        result=predicate()
        if result:return result
        time.sleep(.05)
    raise AssertionError('GUI acceptance predicate timed out')

def workspace():return Path(tempfile.mkdtemp(prefix='OKVideoMac-8B3B-crash-shell-',dir='/private/tmp'))
def env(root):
    e=os.environ.copy();e.pop('XCTestBundlePath',None);e.pop('XCTestConfigurationFilePath',None)
    e['OKVIDEOMAC_8B3B_ROOT']=str(root);return e
def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
def make_report(root):
    r=subprocess.run([str(OLD),'--diagnostic-crash-stage','entry','--diagnostic-crash-kind','swift'],env=env(root),capture_output=True,timeout=20,preexec_fn=no_core)
    assert r.returncode<0
def snapshot(p):return json.loads(subprocess.check_output([str(UI),'snapshot',str(p.pid)],text=True))
def continuation_present(p):return any(r.get('AXIdentifier')=='crash-recovery-continue' for r in snapshot(p))
def windows(p):return int(subprocess.check_output([str(ROOT/'window-probe'),str(p.pid)],text=True))
def database(root):return root/'Application Support/Database/OKVideoMac.sqlite3'
def launch(root):
    path=ROOT/f'logs/stage4-ui-{len(owned)}.log';log=path.open('wb')
    p=subprocess.Popen([str(EXE)],env=env(root),stdout=log,stderr=log);owned.append((p,log,path))
    wait(lambda:windows(p)==1);return p
def quit(p):
    subprocess.run([str(ROOT/'instance-probe'),'quit',str(p.pid)],check=True);p.wait(timeout=12)
def assert_waiting(p,root,path):
    assert continuation_present(p) and windows(p)==1 and not database(root).exists()
    assert '[MPV-LIFECYCLE]' not in path.read_text(errors='replace')
    rows=subprocess.check_output(['/bin/ps','-axo','pid=,ppid='],text=True).splitlines()
    assert not any(int(row.split()[1])==p.pid for row in rows)
def press_continue(p):subprocess.run([str(UI),'press',str(p.pid),'crash-recovery-continue'],check=True)
def passed(name,**details):cases.append({'name':name,'status':'PASS',**details});print('PASS:',name,flush=True)

shutil.copytree(ROOT/'DerivedData/Build/Products/Release/OKVideoMac.app',APP,symlinks=True)
path=APP/'Contents/Info.plist';info=plistlib.loads(path.read_bytes());info['CFBundleIdentifier']=ID;path.write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--sign','-','--options','runtime','--entitlements',
    'OKVideoMac/macOS/OKVideoMac/Supporting/OKVideoMac.dev.entitlements',str(APP)],check=True,capture_output=True)
try:
    root=workspace();make_report(root);p=launch(root);logpath=owned[-1][2]
    time.sleep(.5)
    rows=snapshot(p)
    (ROOT/'logs/stage4-first-snapshot.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
    print('Initial UI:',json.dumps(rows,ensure_ascii=False)[:6000],flush=True)
    print('Database already exists:',database(root).exists(),flush=True)
    subprocess.run([str(UI),'capture',str(p.pid),str(ROOT/'stage4-first-ui.png')],check=False)
    wait(lambda:continuation_present(p));assert_waiting(p,root,logpath)
    subprocess.run([str(UI),'capture',str(p.pid),str(ROOT/'stage4-recovery.png')],check=True)
    passed('recovery is one actual window; no SQLite, native player or child process before continue')
    subprocess.run([str(UI),'keys',str(p.pid),'43'],check=True) # Cmd-comma
    time.sleep(.4);assert_waiting(p,root,logpath)
    passed('Settings shortcut cannot bypass recovery or create a settings window')
    subprocess.run([str(UI),'keys',str(p.pid),'45'],check=True) # Cmd-N
    time.sleep(.4);assert_waiting(p,root,logpath)
    passed('New Window shortcut cannot create another recovery window')
    press_continue(p);wait(lambda:database(root).exists() and not continuation_present(p))
    assert windows(p)==1
    marker=root/'Application Support/Diagnostics/CrashReports/recovery-prompt.json'
    assert marker.exists()
    consent=root/'Application Support/Diagnostics/CrashReports/consent.json'
    assert not consent.exists() or json.loads(consent.read_text()) is False
    time.sleep(.2)
    assert logpath.read_text(errors='replace').count('create client')==1
    subprocess.run([str(UI),'capture',str(p.pid),str(ROOT/'stage4-business.png')],check=True)
    passed('actual Continue button switches the same window and creates the native player exactly once without consent')
    print('Ready application menu:',subprocess.check_output([str(UI),'menu',str(p.pid)],text=True),flush=True)
    subprocess.run([str(UI),'keys',str(p.pid),'43'],check=True)
    wait(lambda:windows(p)==2)
    subprocess.run([str(UI),'capture',str(p.pid),str(ROOT/'stage4-settings.png'),'front'],check=True)
    assert logpath.read_text(errors='replace').count('create client')==1
    passed('Settings opens only after business is ready and reuses the same business state')
    subprocess.run([str(UI),'press',str(p.pid),'AXCloseButton'],check=True)
    wait(lambda:windows(p)==1)
    subprocess.run([str(UI),'keys',str(p.pid),'45'],check=True)
    wait(lambda:windows(p)==2)
    assert logpath.read_text(errors='replace').count('create client')==1
    passed('New Window works after readiness and shares the existing native player')
    quit(p)
    p=launch(root);wait(lambda:database(root).exists() and not continuation_present(p));assert windows(p)==1;quit(p)
    passed('acknowledged old report does not block the next clean launch')
    root=workspace();make_report(root);p=launch(root);wait(lambda:continuation_present(p))
    subprocess.run([str(UI),'press',str(p.pid),'AXCloseButton'],check=True);p.wait(timeout=12)
    assert not database(root).exists()
    assert not (root/'Application Support/Diagnostics/CrashReports/recovery-prompt.json').exists()
    passed('closing recovery exits without creating business or acknowledging its report')
    p=launch(root);wait(lambda:continuation_present(p));quit(p);assert not database(root).exists()
    passed('reopening unacknowledged recovery reprompts; Quit still starts no business')
    root=workspace();make_report(root);p=launch(root);logpath=owned[-1][2];wait(lambda:continuation_present(p))
    configuration=root/'queued-config.json'
    configuration.write_text(json.dumps({'sites':[{'key':'queued-local','name':'Queued Local','type':1,'api':'http://127.0.0.1:9'}]}))
    subprocess.run(['/usr/bin/open','-a',str(APP),str(configuration)],check=True)
    time.sleep(.5);assert_waiting(p,root,logpath)
    press_continue(p);wait(lambda:database(root).exists())
    def imported_once():
        with sqlite3.connect(f'file:{database(root)}?mode=ro',uri=True) as connection:
            return connection.execute('SELECT count(*) FROM configurations WHERE name=?',('queued-config',)).fetchone()[0]==1
    wait(imported_once,timeout=30)
    with sqlite3.connect(f'file:{database(root)}?mode=ro',uri=True) as connection:
        assert connection.execute('SELECT count(*) FROM configurations').fetchone()[0]==1
    passed('actual file-open event stays deferred during recovery and imports once after Continue')
    # A synthetic unreachable API may show a business alert after import; confirm only the owned App's alert.
    subprocess.run([str(ROOT/'alert-probe'),str(p.pid)],capture_output=True)
    quit(p)
    result={'status':'PASS','cases':cases,'configuration':'copied Release acceptance App, actual UI actions',
        'app_path':str(APP),'screenshots':['stage4-recovery.png','stage4-business.png','stage4-settings.png']}
    (ROOT/'stage4-shell.json').write_text(json.dumps(result,indent=2)+'\n')
finally:
    for p,log,path in owned:
        if p.poll() is None:p.terminate();p.wait(timeout=5)
        log.close()
