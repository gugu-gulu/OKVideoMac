#!/usr/bin/env python3
"""Real SwiftUI shell launches; decisions injected into its model, NOT visual UI automation."""
import json, pathlib, resource, subprocess, tempfile, time, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
EXE=ROOT/'build/CrashVisibilityPrototype.app/Contents/MacOS/CrashVisibilityPrototype'
EVIDENCE=ROOT/'build/phase3-20261011/shell-tests'
EVIDENCE.mkdir(parents=True,exist_ok=True)
def no_core(): resource.setrlimit(resource.RLIMIT_CORE,(0,0))
class Shell(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='cvp-shell-',dir=ROOT/'build')
        self.root=pathlib.Path(self.tmp.name)/'runtime'
    def tearDown(self):
        evidence=[{'file':p.name,'events':p.read_text().splitlines()} for p in self.root.rglob('startup-*.trace')] if self.root.exists() else []
        (EVIDENCE/(self.id().split('.')[-1]+'.json')).write_text(json.dumps(evidence,indent=2))
        self.tmp.cleanup()
    def command(self,*args):
        return [str(EXE),'--state-root',str(self.root),'--startup-rehearsal','--recovery-shell-ui',*args]
    def run_shell(self,action='quit',*args):
        p=subprocess.run(self.command('--shell-test-action',action,*args),capture_output=True,text=True,timeout=18,preexec_fn=no_core)
        traces=sorted(self.root.glob('startup-*.trace'),key=lambda x:x.stat().st_mtime_ns)
        return p,traces[-1].read_text().splitlines()
    def seed(self):
        p=subprocess.run([str(EXE),'--state-root',str(self.root/'crash'),'--crash','swift-pre'],capture_output=True,timeout=10,preexec_fn=no_core)
        self.assertLess(p.returncode,0)
    def ordered(self,events,expected):
        indexes=[events.index(e) for e in expected];self.assertEqual(indexes,sorted(indexes),events)
    def once(self,events):
        self.ordered(events,['capture-installed','swiftui-main-enter','app-init-enter','shell-state-created-without-business','shell-business-start','bootstrap-enter','state-created','same-lease-transferred','mock-database-open','mock-player-created','bootstrap-return','shell-business-ready'])
        for e in ['app-init-enter','shell-business-start','bootstrap-enter','state-created','mock-database-open','mock-player-created','shell-business-ready']:
            self.assertEqual(events.count(e),1,(e,events))
    def status(self):
        p=subprocess.run([str(EXE),'--state-root',str(self.root/'crash'),'--status'],capture_output=True,text=True,timeout=10,check=True)
        return json.loads(p.stdout.splitlines()[-1])
    def test_01_recovery_shell_exists_without_business(self):
        self.seed();p,e=self.run_shell();self.assertEqual(p.returncode,0,p.stderr)
        self.ordered(e,['capture-installed','swiftui-main-enter','app-init-enter','shell-state-created-without-business','shell-recovery-required','shell-ui-ready','shell-model-decision-injected:quit','delegate-will-terminate'])
        self.assertNotIn('bootstrap-enter',e);self.assertNotIn('mock-player-created',e)
        s=self.status();self.assertFalse(s['consent']);self.assertEqual(s['pending'],1)
        p,e=self.run_shell();self.assertEqual(p.returncode,0,p.stderr);self.assertIn('shell-recovery-required',e)
    def test_02_continue_once_and_ack_without_consent(self):
        self.seed();p,e=self.run_shell('continue-twice');self.assertEqual(p.returncode,0,p.stderr);self.once(e)
        self.ordered(e,['shell-recovery-required','shell-ui-ready','shell-model-decision-injected:continue-twice','shell-business-start'])
        self.assertEqual(e.count('shell-continue-action'),2)
        s=self.status();self.assertFalse(s['consent']);self.assertEqual(s['pending'],1)
        p,e=self.run_shell();self.assertEqual(p.returncode,0,p.stderr);self.once(e);self.assertIn('shell-recovery-not-required',e)
    def test_03_new_crash_prompts_again(self):
        self.seed();p,e=self.run_shell('continue');self.assertEqual(p.returncode,0,p.stderr);self.once(e)
        self.seed();p,e=self.run_shell();self.assertEqual(p.returncode,0,p.stderr)
        self.assertIn('shell-recovery-required',e);self.assertNotIn('bootstrap-enter',e);self.assertEqual(self.status()['pending'],2)
    def test_04_five_early_faults_are_recovered(self):
        base=self.root
        for point in ['before-app-main','app-init','delegate-init','bootstrap-before','bootstrap-after']:
            with self.subTest(point=point):
                self.root=base/point
                p,e=self.run_shell('quit','--fault',point);self.assertLess(p.returncode,0)
                self.ordered(e,['capture-installed','fault:'+point])
                p,e=self.run_shell();self.assertEqual(p.returncode,0,p.stderr)
                self.assertIn('shell-recovery-required',e);self.assertNotIn('bootstrap-enter',e);self.assertEqual(self.status()['pending'],1)
        self.root=base
    def test_05_capture_storage_failure_allows_business(self):
        self.root.mkdir(parents=True);(self.root/'crash').write_text('not a directory')
        p,e=self.run_shell();self.assertEqual(p.returncode,0,p.stderr)
        self.assertIn('capture-unavailable',e);self.assertIn('shell-business-ready',e);self.assertEqual(e.count('bootstrap-enter'),1)
    def test_06_live_recovery_holds_original_single_instance_lease(self):
        self.seed()
        p=subprocess.Popen(self.command(),stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,preexec_fn=no_core)
        try:
            trace=self.root/f'startup-{p.pid}.trace';deadline=time.monotonic()+10
            while time.monotonic()<deadline and (not trace.exists() or 'shell-ui-ready' not in trace.read_text()):time.sleep(.02)
            self.assertIsNone(p.poll());self.assertIn('shell-ui-ready',trace.read_text());self.assertNotIn('bootstrap-enter',trace.read_text())
            second,e=self.run_shell();self.assertEqual(second.returncode,3);self.assertEqual(e,['entry','lease-rejected'])
        finally:
            if p.poll() is None:p.terminate()
            p.wait(timeout=5)
        next_app,e=self.run_shell();self.assertEqual(next_app.returncode,0,next_app.stderr);self.assertIn('shell-recovery-required',e)
    def test_07_ten_clean_launches_initialize_once_each(self):
        for _ in range(10):
            p,e=self.run_shell();self.assertEqual(p.returncode,0,p.stderr);self.once(e)
        self.assertEqual(len(list(self.root.glob('startup-*.trace'))),10)
    def test_08_one_swiftui_scene_no_native_handoff_code(self):
        shell=(ROOT/'Sources/CrashVisibilityApp/RecoveryShellApp.swift').read_text()
        self.assertEqual(shell.count('WindowGroup('),1)
        for token in ['NSWindow(', 'runModal(', 'makeKeyAndOrderFront(', 'activate(', 'asyncAfter(']:self.assertNotIn(token,shell)
        self.assertFalse((ROOT/'Sources/CrashVisibilityApp/NativeRecoveryGate.swift').exists())
if __name__=='__main__':unittest.main(verbosity=2)
