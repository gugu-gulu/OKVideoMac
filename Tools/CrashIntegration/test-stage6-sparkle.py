"""Signed local Sparkle updates of the actual App, including concurrent diagnostic shutdown."""
import sys,functools,hashlib,http.server,json,os,plistlib,resource,shutil,subprocess,tempfile,threading,time,wave,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path('/private/tmp/OKVideoMac-CrashIntegration');TOOLS=ROOT/'SparkleFixtures/bin';KEY=ROOT/'sparkle-fixture-private-key.txt';PUBLIC=ROOT/'sparkle-fixture-public-key.txt'
IDENTITY='D604D626E220F2290C35D94AA025D30C3B9E0EB9';ID='com.okvideomac.OKVideoMac.acceptance8b3b';UI=ROOT/'owned-ui-probe';cases=[]
OLD=Path(json.loads((ROOT/'stage5-upload.json').read_text())['app_path'])/'Contents/MacOS/OKVideoMac'
def run(args,**kwargs):return subprocess.run([str(a) for a in args],check=True,**kwargs)
def wait(f,timeout=120):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        v=f()
        if v:return v
        time.sleep(.05)
    raise AssertionError('Signed Sparkle update timed out')
def events(path):
    if not path.exists():return []
    return [json.loads(line) for line in path.read_text().splitlines() if line]
def alive(pid):
    try:os.kill(pid,0);return True
    except ProcessLookupError:return False

def sign(path,entitlements=None):
    args=['codesign','--force','--sign',IDENTITY,'--options','runtime','--timestamp=none']
    if entitlements:args+=['--entitlements',entitlements]
    run(args+[path],capture_output=True)
def sign_app(app):
    for path in app.rglob('*'):
        if path.is_symlink() or not path.is_file():continue
        if 'Mach-O' in subprocess.check_output(['file','-b',str(path)],text=True):sign(path)
    nested=[p for p in app.rglob('*') if p.is_dir() and not p.is_symlink() and p.suffix in ['.app','.xpc','.framework']]
    for path in sorted(nested,key=lambda p:len(p.parts),reverse=True):sign(path)
    sign(app,'OKVideoMac/macOS/OKVideoMac/Supporting/OKVideoMac.dev.entitlements')
    run(['codesign','--verify','--deep','--strict',app],capture_output=True)

def make_bundle(dest,version,root,url,scenario,delay=0):
    shutil.copytree(ROOT/'DerivedData/Build/Products/Release/OKVideoMac.app',dest,symlinks=True)
    p=dest/'Contents/Info.plist';d=plistlib.loads(p.read_bytes())
    d.update({'CFBundleIdentifier':ID,'CFBundleVersion':str(version),'CFBundleShortVersionString':f'0.0.{version}',
        'OKCrashAcceptanceRoot':str(root),'OKCrashSparkleFixture':True,'OKUpdateProbeScenario':scenario,
        'OKCrashAcceptanceShutdownDelay':delay if version==1 else 0,
        'SUPublicEDKey':PUBLIC.read_text().strip(),'SUFeedURL':url+'/appcast.xml','OKUpdateChannel':'unconfigured',
        'SUAutomaticallyUpdate':False,'SUAllowsAutomaticUpdates':False,'SUVerifyUpdateBeforeExtraction':True,
        'SURequireSignedFeed':True,'SUSignedFeedFailureExpirationInterval':0,
        'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True,'NSAllowsArbitraryLoads':True}})
    p.write_bytes(plistlib.dumps(d));sign_app(dest)

def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
def root_environment(root):
    e=os.environ.copy();e.pop('XCTestBundlePath',None);e.pop('XCTestConfigurationFilePath',None);e['OKVIDEOMAC_8B3B_ROOT']=str(root);return e

def make_report(root):
    p=subprocess.run([str(OLD),'--diagnostic-crash-stage','entry'],env=root_environment(root),capture_output=True,timeout=15,preexec_fn=no_core);assert p.returncode<0
    run([OLD,'--diagnostic-export'],env=root_environment(root),capture_output=True,timeout=15)

if not KEY.exists():
    run(['xcrun','swiftc','-O','Tools/SourceAudit/UpdatesStage2/TestKey.swift','-o',ROOT/'make-sparkle-test-key'],capture_output=True)
    r=run([ROOT/'make-sparkle-test-key',KEY],capture_output=True,text=True);PUBLIC.write_text(r.stdout.strip()+'\n')

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*a):pass

for scenario,delay in ([('idle',0)] if '--idle-only' in sys.argv else [('idle',0),('playing',0),('paused',0),('playing',12)]):
    area=Path(tempfile.mkdtemp(prefix='Stage6Sparkle-',dir=ROOT));root=Path(tempfile.mkdtemp(prefix='OKVideoMac-8B3B-sparkle-',dir='/private/tmp'))
    label=scenario+('-slow-cleanup' if delay else '')
    if scenario!='idle':
        with wave.open(str(root/'silent.wav'),'wb') as w:
            w.setnchannels(1);w.setsampwidth(2);w.setframerate(48000);w.writeframes(b'\0\0'*48000*120)
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Handler,directory=str(area)))
    threading.Thread(target=server.serve_forever,daemon=True).start();url=f'http://127.0.0.1:{server.server_port}'
    installed=area/'Installed/OKVideoMac.app';next_app=area/'Next/OKVideoMac.app';p=None;log=None
    try:
        installed.parent.mkdir();next_app.parent.mkdir()
        make_bundle(installed,1,root,url,scenario,delay);make_bundle(next_app,2,root,url,scenario,delay)
        archive=area/'update.zip';run(['ditto','-c','-k','--keepParent',next_app,archive],capture_output=True)
        attributes=run([TOOLS/'sign_update','--ed-key-file',KEY,archive],capture_output=True,text=True).stdout.strip()
        enclosure=ET.fromstring('<enclosure xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" '+attributes+'/>')
        signature=enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature']
        feed=f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Crash Lifecycle Acceptance</title><item><title>Isolated Test Build 2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.0.2</sparkle:shortVersionString><sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion><enclosure url="{url}/update.zip" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature}"/></item></channel></rss>'''
        (area/'appcast.xml').write_text(feed)
        run([TOOLS/'sign_update','--ed-key-file',KEY,area/'appcast.xml'],capture_output=True)
        run([TOOLS/'sign_update','--verify','--ed-key-file',KEY,area/'appcast.xml'],capture_output=True)
        make_report(root)
        # Grant locally with no transport configuration, leaving one synthetic record queued.
        run([OLD,'--diagnostic-upload-model','--diagnostic-grant'],env=root_environment(root),capture_output=True,timeout=15)
        log=(ROOT/f'logs/stage6-sparkle-{label}.log').open('wb')
        p=subprocess.Popen([str(installed/'Contents/MacOS/OKVideoMac'),'--diagnostic-test-dsn','http://public@127.0.0.1:1/1','--diagnostic-worker-fault','noRead'],env=root_environment(root),stdout=log,stderr=log)
        def recovering():
            if p.poll() is not None:raise AssertionError('Fixture exited before recovery')
            if int(subprocess.check_output([str(ROOT/'window-probe'),str(p.pid)],text=True))!=1:return False
            return any(r.get('AXIdentifier')=='crash-recovery-continue' for r in json.loads(subprocess.check_output([str(UI),'snapshot',str(p.pid)],text=True)))
        wait(recovering,20)
        initial_worker=wait(lambda:subprocess.run(['pgrep','-P',str(p.pid)],capture_output=True,text=True).stdout.split(),5)
        assert len(initial_worker)==1
        run([UI,'press',p.pid,'crash-recovery-continue'])
        def completed():
            rows=events(root/'crash-lifecycle.jsonl');updates=events(root/'events.jsonl')
            failure=next((r for r in rows if r['event']=='fixture-failed'),None)
            if failure:raise AssertionError(failure)
            errors=[r for r in updates if r['event'] in ['update_error','aborted']]
            if errors:raise AssertionError(errors)
            if p.poll() is not None:
                candidates=json.loads(subprocess.check_output([str(ROOT/'instance-probe'),'list',ID],text=True))
                for candidate in candidates:
                    if int(subprocess.check_output([str(ROOT/'window-probe'),str(candidate)],text=True))>0:
                        snapshot=json.loads(subprocess.check_output([str(UI),'snapshot',str(candidate)],text=True))
                        if any(r.get('AXValue') in ['无法初始化应用','Unable to Initialize App'] for r in snapshot):
                            raise AssertionError({'relaunch_preflight_failed':snapshot,'entry_probe':json.loads((ROOT/'fixture-entry.json').read_text())})
            return next((r for r in rows if r['event']=='updated-history'),None)
        updated=wait(completed,120);p.wait(timeout=15)
        rows=events(root/'crash-lifecycle.jsonl');old=[r for r in rows if r['version']=='1'];new=[r for r in rows if r['version']=='2']
        assert len([r for r in old if r['event']=='termination-replied'])==1
        for name in ['history-flushed','player-stopped','node-stopped','android-stopped','diagnostics-stopped','shutdown-complete']:
            assert len([r for r in old if r['event']==name])==1,(name,old)
        assert next(r for r in old if r['event']=='player-stopped')['nativeReleased']
        diag=next(r for r in old if r['event']=='diagnostics-stopped');assert not diag['sending'] and not diag['cacheExists']
        assert next(r for r in old if r['event']=='install-upload-active')['sending']
        assert plistlib.loads((installed/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='2'
        if scenario=='idle':assert updated['historyCount']==0
        else:
            playback=next(r for r in events(root/'events.jsonl') if r['event']=='real_playback_verified')
            assert updated['historyCount']==1 and updated['savedPosition']>=playback['position']-.2
        if delay:
            assert any(r['event']=='update-cleanup-wait' for r in old)
            request=next(r for r in old if r['event']=='termination-requested');reply=next(r for r in old if r['event']=='termination-replied')
            assert reply['uptime']-request['uptime']>=12
        new_pid=updated['pid'];wait(lambda:not alive(new_pid),15)
        run(['codesign','--verify','--deep','--strict',installed],capture_output=True)
        result={'scenario':label,'status':'PASS','root':str(root),'app_path':str(installed),'history_count':updated['historyCount'],'saved_position':updated['savedPosition'],'installer':'unmodified Sparkle 2.10.0','archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'termination_replies':1}
        cases.append(result);(ROOT/'stage6-sparkle.json').write_text(json.dumps({'status':'IN_PROGRESS','cases':cases},indent=2)+'\n');print('PASS: actual signed Sparkle installation:',label,flush=True)
    finally:
        if p and p.poll() is None:p.terminate();p.wait(timeout=5)
        # Find only processes executing this exact fixture, including preflight failures without trace rows.
        candidates=json.loads(subprocess.check_output([str(ROOT/'instance-probe'),'list',ID],text=True))
        expected=(installed/'Contents/MacOS/OKVideoMac').resolve()
        for candidate in candidates:
            command=subprocess.run(['ps','-p',str(candidate),'-o','comm='],capture_output=True,text=True).stdout.strip()
            if command and Path(command).resolve()==expected:
                subprocess.run([str(ROOT/'instance-probe'),'quit',str(candidate)],capture_output=True)
                wait(lambda:not alive(candidate),20)
        if log:log.close()
        server.shutdown();server.server_close()
(ROOT/'stage6-sparkle.json').write_text(json.dumps({'status':'PASS','cases':cases,'scope':'signed local updates of actual App with muted WAV, no notarization or public feed; active Node/emulator workloads excluded'},indent=2)+'\n')
