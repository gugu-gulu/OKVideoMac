#!/usr/bin/env python3
"""Actual SwiftUI App.main/StateObject, exact production lease, synthetic bootstrap sentinels.
Recovery decisions are injected; no UI clicking, real database/player or production startup.
"""
import hashlib,json,pathlib,resource,subprocess,tempfile,time,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
EXE=ROOT/'build/CrashVisibilityPrototype.app/Contents/MacOS/CrashVisibilityPrototype'
EVIDENCE=ROOT/'build/phase2-20261011'
def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
class Startup(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='cvp-startup-',dir=ROOT/'build')
        self.root=pathlib.Path(self.tmp.name)/'runtime';self.evidence=[]
    def tearDown(self):
        if self.root.exists():
            for path in sorted(self.root.glob('startup-*.trace')):
                self.evidence.append({'file':path.name,'events':path.read_text().splitlines()})
        (EVIDENCE/(self.id().split('.')[-1]+'.json')).write_text(json.dumps(self.evidence,indent=2))
        self.tmp.cleanup()
    def run_app(self,*args):
        process=subprocess.run([str(EXE),'--state-root',str(self.root),'--startup-rehearsal',*args],capture_output=True,text=True,timeout=18,preexec_fn=no_core)
        traces=sorted(self.root.glob('startup-*.trace'),key=lambda p:p.stat().st_mtime_ns)
        return process,traces[-1].read_text().splitlines()
    def ordered(self,events,expected):
        positions=[events.index(item) for item in expected];self.assertEqual(positions,sorted(positions),events)
    def clean(self,events):
        self.ordered(events,['entry','lease-acquired','swiftui-main-enter','app-init-enter','bootstrap-enter','state-created','same-lease-transferred','mock-database-open','mock-player-created','bootstrap-return','swiftui-task','normal-exit'])
        for event in ['bootstrap-enter','state-created','mock-database-open','mock-player-created','normal-exit']:self.assertEqual(events.count(event),1)
    def crash_pending(self):
        self.root.mkdir(parents=True)
        p=subprocess.run([str(EXE),'--state-root',str(self.root/'crash'),'--crash','swift-pre'],capture_output=True,timeout=10,preexec_fn=no_core)
        self.assertLess(p.returncode,0)
    def test_01_real_swiftui_order(self):
        p,events=self.run_app();self.assertEqual(p.returncode,0,p.stderr);self.clean(events)
        self.ordered(events,['capture-installed','swiftui-main-enter','app-init-enter','app-init-return','bootstrap-enter'])
        # SwiftUI controls adaptor creation; on this runtime it is AFTER bootstrap.
        # The safety contract is early capture for both, not an assumed adaptor ordering.
        self.ordered(events,['capture-installed','delegate-init','swiftui-task'])
    def test_02_gate_precedes_app_and_state(self):
        self.crash_pending()
        p,events=self.run_app('--gate','defer');self.assertEqual(p.returncode,0,p.stderr)
        self.assertIn('recovery-gate-deferred',events);self.assertNotIn('swiftui-main-enter',events);self.assertNotIn('mock-database-open',events)
        p,events=self.run_app('--gate','continue');self.assertEqual(p.returncode,0,p.stderr);self.clean(events)
        self.ordered(events,['capture-installed','recovery-gate-required','recovery-decision-injected','swiftui-main-enter'])
        p,events=self.run_app();self.assertEqual(p.returncode,0,p.stderr);self.clean(events)
        self.assertNotIn('recovery-gate-required',events)
    def test_03_five_early_faults_recover_without_loop(self):
        base=self.root
        for point in ['before-app-main','delegate-init','app-init','bootstrap-before','bootstrap-after']:
            with self.subTest(point=point):
                self.root=base/point
                p,events=self.run_app('--fault',point);self.assertLess(p.returncode,0,p.stdout+p.stderr)
                self.ordered(events,['lease-acquired','capture-installed','fault:'+point])
                self.assertEqual(len(list((self.root/'crash/raw').rglob('*.plcrash'))),1)
                p,events=self.run_app('--gate','defer');self.assertEqual(p.returncode,0,p.stderr)
                self.assertIn('recovery-gate-required',events);self.assertNotIn('bootstrap-enter',events)
                files=list((self.root/'crash/pending').glob('*.json'));self.assertEqual(len(files),1)
                record=json.loads(files[0].read_text());self.assertEqual(record['signal'],'SIGTRAP')
                self.assertTrue(any(t['crashed'] and t['frames'] for t in record['threads']))
                image=next(i for i in record['images'] if i['name']=='CrashVisibilityPrototype')
                self.assertEqual(image.get('vmaddr'),4294967296,'early startup reports need the original image address metadata for symbolication')
                p,events=self.run_app('--gate','continue');self.assertEqual(p.returncode,0,p.stderr);self.clean(events)
                self.evidence.append({'point':point,'record_id':record['id'],'recovered':True,'events':events})
        self.root=base
    def test_04_duplicate_while_recovery_pending_cannot_reach_capture_or_database(self):
        self.crash_pending()
        first=subprocess.Popen([str(EXE),'--state-root',str(self.root),'--startup-rehearsal','--gate','hold'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,preexec_fn=no_core)
        self.addCleanup(lambda:first.kill() if first.poll() is None else None)
        deadline=time.monotonic()+8
        trace=self.root/f'startup-{first.pid}.trace'
        while time.monotonic()<deadline:
            if trace.exists() and 'recovery-gate-held' in trace.read_text():break
            time.sleep(.02)
        self.assertIn('recovery-gate-held',trace.read_text())
        second,events=self.run_app();self.assertEqual(second.returncode,3)
        self.assertEqual(events,['entry','lease-rejected'])
        (self.root/'continue.signal').touch()
        out,err=first.communicate(timeout=10);self.assertEqual(first.returncode,0,err)
        self.clean(trace.read_text().splitlines())
        third,events=self.run_app();self.assertEqual(third.returncode,0,third.stderr);self.clean(events)
    def test_05_capture_storage_failure_continues(self):
        self.root.mkdir(parents=True);(self.root/'crash').write_text('not a directory')
        p,events=self.run_app();self.assertEqual(p.returncode,0,p.stderr)
        self.assertIn('capture-unavailable',events);self.clean(events)
    def test_06_lease_failure_must_not_continue(self):
        (self.root/'.instance.lock').mkdir(parents=True)
        p,events=self.run_app();self.assertEqual(p.returncode,3);self.assertEqual(events,['entry','lease-rejected'])
        self.assertFalse((self.root/'crash').exists())
    def test_07_ten_real_swiftui_launches_release_lease(self):
        for _ in range(10):
            p,events=self.run_app();self.assertEqual(p.returncode,0,p.stderr);self.clean(events)
        self.assertEqual(len(list(self.root.glob('startup-*.trace'))),10)
    def test_08_source_projection_is_exact(self):
        source=ROOT.parents[1]/'OKVideoMac/macOS/OKVideoMac/App/AppEnvironment.swift'
        manifest=json.loads((EVIDENCE/'source-provenance.json').read_text())
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),manifest['source_sha256'])
        lease=source.read_text().split('final class ApplicationInstanceLease {',1)[1]
        projected=(ROOT/'Sources/CrashVisibilityApp/RehearsalLease.generated.swift').read_text().split('final class ApplicationInstanceLease {',1)[1]
        self.assertEqual(lease,projected)
    def test_09_simultaneous_launches_only_one_owns_recovery(self):
        self.crash_pending();processes=[]
        for _ in range(2):
            p=subprocess.Popen([str(EXE),'--state-root',str(self.root),'--startup-rehearsal','--gate','hold'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,preexec_fn=no_core)
            processes.append(p);self.addCleanup(lambda p=p:p.kill() if p.poll() is None else None)
        deadline=time.monotonic()+8
        while time.monotonic()<deadline and not any(p.poll()==3 for p in processes):time.sleep(.02)
        self.assertEqual([p.poll() for p in processes].count(3),1)
        (self.root/'continue.signal').touch()
        for p in processes:p.communicate(timeout=10)
        self.assertEqual(sorted(p.returncode for p in processes),[0,3])
        traces=[(self.root/f'startup-{p.pid}.trace').read_text().splitlines() for p in processes]
        self.assertEqual(sum(events.count('mock-database-open') for events in traces),1)
        self.assertEqual(sum(events.count('capture-installed') for events in traces),1)
if __name__=='__main__':unittest.main(verbosity=2)
