"""Real AppKit termination with synthetic diagnostics and isolated business state."""
import json,os,plistlib,resource,shutil,subprocess,tempfile,time
from pathlib import Path
ROOT=Path('/private/tmp/OKVideoMac-CrashIntegration');ID='com.okvideomac.OKVideoMac.acceptance8b3b';UI=ROOT/'owned-ui-probe'
APP=Path(tempfile.mkdtemp(prefix='Stage6-',dir=ROOT))/'OKVideoMac.app';EXE=APP/'Contents/MacOS/OKVideoMac'
OLD=Path(json.loads((ROOT/'stage5-upload.json').read_text())['app_path'])/'Contents/MacOS/OKVideoMac'
cases=[];owned=[]
def wait(f,timeout=20):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        v=f()
        if v:return v
        time.sleep(.03)
    raise AssertionError('Lifecycle fixture timed out')
def env(root):
    e=os.environ.copy();e.pop('XCTestBundlePath',None);e.pop('XCTestConfigurationFilePath',None);e['OKVIDEOMAC_8B3B_ROOT']=str(root);return e
def workspace():return Path(tempfile.mkdtemp(prefix='OKVideoMac-8B3B-termination-',dir='/private/tmp'))
def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
def report(root):
    p=subprocess.run([str(OLD),'--diagnostic-crash-stage','entry'],env=env(root),capture_output=True,timeout=15,preexec_fn=no_core);assert p.returncode<0
    p=subprocess.run([str(OLD),'--diagnostic-export'],env=env(root),capture_output=True,timeout=15);assert p.returncode==0
    return json.loads(p.stdout.splitlines()[-1])['reports'][0]
def database(root):return root/'Application Support/Database/OKVideoMac.sqlite3'
def records(root):return list((root/'Application Support/Diagnostics/CrashReports/pending').glob('*.json'))
def events(root):
    file=root/'crash-lifecycle.jsonl';return [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []
def children(pid):return [int(v) for v in subprocess.run(['pgrep','-P',str(pid)],capture_output=True,text=True).stdout.split()]
def launch(root,*args):
    logpath=ROOT/f'logs/stage6-lifecycle-{len(owned)}.log';log=logpath.open('wb')
    p=subprocess.Popen([str(EXE),*args],env=env(root),stdout=log,stderr=log);owned.append((p,log,logpath));wait(lambda:int(subprocess.check_output([str(ROOT/"window-probe"),str(p.pid)],text=True))==1);return p

def quit(p):subprocess.run([str(ROOT/'instance-probe'),'quit',str(p.pid)],check=True)
def ui_rows(p):return json.loads(subprocess.check_output([str(UI),'snapshot',str(p.pid)],text=True))
def has_continue(p):return any(r.get('AXIdentifier')=='crash-recovery-continue' for r in ui_rows(p))
def assert_terminated(p,root,business,child=[]):
    p.wait(timeout=12);assert p.returncode==0
    rows=events(root);assert sum(r['event']=='termination-replied' for r in rows)==1,rows
    assert sum(r['event']=='shutdown-complete' for r in rows)==1
    requests=[r for r in rows if r['event']=='termination-requested'];assert requests
    if not business:
        assert all(r['updateInitializations']==0 for r in requests)
        assert not database(root).exists() and not any(r['event']=='business-shutdown-started' for r in rows)
    else:
        for name in ['business-shutdown-started','history-flushed','player-stopped','node-stopped','android-stopped']:
            assert sum(r['event']==name for r in rows)==1,(name,rows)
        assert next(r for r in rows if r['event']=='player-stopped')['nativeReleased']
    for pid in child:
        try:os.kill(pid,0)
        except ProcessLookupError:continue
        raise AssertionError('Orphan worker')
    assert not (root/'Application Support/Diagnostics/CrashReports/sentry-cache').exists()
    return rows

def passed(name,**details):cases.append({'name':name,'status':'PASS',**details});print('PASS:',name,flush=True)
shutil.copytree(ROOT/'DerivedData/Build/Products/Release/OKVideoMac.app',APP,symlinks=True)
p=APP/'Contents/Info.plist';d=plistlib.loads(p.read_bytes());d['CFBundleIdentifier']=ID;p.write_bytes(plistlib.dumps(d))
subprocess.run(['codesign','--force','--sign','-','--options','runtime','--entitlements','OKVideoMac/macOS/OKVideoMac/Supporting/OKVideoMac.dev.entitlements',str(APP)],check=True,capture_output=True)
try:
    root=workspace();report(root);p=launch(root);wait(lambda:has_continue(p));quit(p);rows=assert_terminated(p,root,False)
    assert len(records(root))==1;passed('recovery Quit replies once without constructing updater, database or player')
    root=workspace();report(root);p=launch(root);wait(lambda:has_continue(p))
    subprocess.run([str(UI),'press',str(p.pid),'AXCloseButton'],check=True);assert_terminated(p,root,False)
    passed('closing the recovery window awaits diagnostics cleanup and starts no business')
    root=workspace();p=launch(root,'--diagnostic-delay-bootstrap','3');wait(lambda:int(subprocess.check_output([str(ROOT/'window-probe'),str(p.pid)],text=True))==1)
    quit(p);assert_terminated(p,root,False);passed('Quit before delayed initialization cancels business creation')
    root=workspace();report(root);p=launch(root,'--diagnostic-test-dsn','http://public@127.0.0.1:1/1','--diagnostic-worker-fault','noRead')
    wait(lambda:has_continue(p));subprocess.run([str(UI),'press',str(p.pid),'crash-upload-consent'],check=True);child=wait(lambda:children(p.pid));assert len(child)==1
    start=time.monotonic();quit(p);assert_terminated(p,root,False,child);assert len(records(root))==1
    passed('recovery Quit cancels active upload, reaps child and keeps consent/unsent report',seconds=time.monotonic()-start)
    root=workspace();report(root);p=launch(root,'--diagnostic-test-dsn','http://public@127.0.0.1:1/1','--diagnostic-worker-fault','noRead','--diagnostic-delay-shutdown','0.5')
    wait(lambda:has_continue(p));subprocess.run([str(UI),'press',str(p.pid),'crash-upload-consent'],check=True);child=wait(lambda:children(p.pid))
    subprocess.run([str(UI),'press',str(p.pid),'crash-recovery-continue'],check=True);wait(lambda:database(root).exists());time.sleep(.2)
    # Deliver three quit requests in one application event stream; there must be one reply.
    for _ in range(3):quit(p)
    rows=assert_terminated(p,root,True,child);assert len(records(root))==1
    assert sum(r['event']=='termination-requested' for r in rows)>=1 # AppKit may coalesce waiting Quit events.
    passed('business Quit during upload executes existing cleanup once, replies once and leaves no child',quit_requests_sent=3,delegate_requests_observed=sum(r['event']=='termination-requested' for r in rows))
    root=workspace();p=launch(root);wait(lambda:database(root).exists());time.sleep(.3);quit(p);assert_terminated(p,root,True)
    passed('clean idle business shutdown still flushes history, destroys player and stops both runtimes')
    (ROOT/'stage6-lifecycle.json').write_text(json.dumps({'status':'PASS','cases':cases,'app_path':str(APP),'scope':'real AppKit Quit/Close with normal business cleanup; Sparkle installation is a separate fixture'},indent=2)+'\n')
finally:
    for p,log,_ in owned:
        if p.poll() is None:p.terminate();p.wait(timeout=5)
        log.close()
