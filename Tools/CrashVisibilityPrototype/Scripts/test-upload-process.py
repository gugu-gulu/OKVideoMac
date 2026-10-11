#!/usr/bin/env python3
"""Real signed worker faults. Main-runloop heartbeat is checked, not simulated UI clicks."""
import importlib.util,json,pathlib,subprocess,tempfile,time,unittest,os
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('integration',ROOT/'Scripts/test-integration.py')
i=importlib.util.module_from_spec(spec);spec.loader.exec_module(i)
EVIDENCE=ROOT/'build/phase3-20261011';EVIDENCE.mkdir(exist_ok=True)
class Worker(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='cvp-worker-',dir=ROOT/'build');self.state=pathlib.Path(self.tmp.name)/'state'
        p=subprocess.run([str(i.EXE),'--state-root',str(self.state),'--crash','c-pre'],capture_output=True,timeout=10,preexec_fn=i.no_core_dump)
        self.assertLess(p.returncode,0)
        p=subprocess.run([str(i.EXE),'--state-root',str(self.state),'--status'],capture_output=True,timeout=10);self.assertEqual(p.returncode,0)
        self.evidence=[]
    def tearDown(self):
        (EVIDENCE/(self.id().split('.')[-1]+'.json')).write_text(json.dumps(self.evidence,indent=2));self.tmp.cleanup()
    def command(self,*args):return [str(i.EXE),'--state-root',str(self.state),'--worker-probe',*args]
    def probe(self,fault,*args):
        p=subprocess.run(self.command('--worker-fault',fault,*args),capture_output=True,text=True,timeout=14,preexec_fn=i.no_core_dump)
        self.assertEqual(p.returncode,0,p.stdout+p.stderr);r=json.loads(p.stdout);self.evidence.append(r)
        self.assertNotIn('HANDLERS_CHANGED',r['outcomes']);self.assertFalse(r['cacheExists']);self.assertLess(r['maxMainGap'],.5,r)
        return r
    def large_report(self):
        path=next((self.state/'pending').glob('*.json'));r=json.loads(path.read_text())
        frame={'pc':18446744073709550000,'imageBase':18446744073709500000}
        def encode(count):
            r['threads']=[{'number':n,'crashed':n==0,'frames':[frame]*min(256,count-n*256)} for n in range((count+255)//256)]
            return json.dumps(r,separators=(',',':')).encode()
        low,high=1,128*256
        while low<high:
            mid=(low+high+1)//2
            if len(encode(mid))<=1_048_576-2048:low=mid
            else:high=mid-1
        data=encode(low)
        path.write_bytes(data);self.assertGreater(len(data),1_000_000)
        self.evidence.append({'recordBytes':len(data)})
    def test_01_spawn_failure(self):
        r=self.probe('spawnFailure');self.assertEqual(r['outcomes'],['pending']);self.assertEqual(r['pending'],1)
    def test_02_full_pipe_no_read_deadline_main_responsive(self):
        self.large_report();r=self.probe('noRead')
        self.assertEqual(r['outcomes'],['pending']);self.assertEqual(r['callbacks'],1)
        self.assertGreater(r['ticks'],100);self.assertGreaterEqual(r['seconds'],8);self.assertLess(r['seconds'],9.5)
    def test_03_early_exit_does_not_sigpipe_parent(self):
        self.large_report()
        for fault in ['exitBeforeRead','exitAfterRead']:
            r=self.probe(fault);self.assertEqual(r['outcomes'],['pending']);self.assertEqual(r['pending'],1)
    def test_04_no_reply_deadline(self):
        r=self.probe('noReply');self.assertEqual(r['outcomes'],['pending']);self.assertGreater(r['ticks'],100);self.assertLess(r['seconds'],9.5)
    def test_05_invalid_and_unbounded_reply(self):
        for fault in ['invalidReply','oversizedReply']:
            r=self.probe(fault);self.assertEqual(r['outcomes'],['pending']);self.assertEqual(r['pending'],1)
    def test_06_cancel_full_pipe(self):
        self.large_report();r=self.probe('noRead','--revoke-after','0.15')
        self.assertEqual(r['outcomes'],['revoked']);self.assertEqual(r['pending'],0);self.assertFalse(r['consent']);self.assertLess(r['seconds'],1)
    def test_07_cancel_then_immediate_regrant(self):
        sink=i.Sink();self.addCleanup(sink.close)
        r=self.probe('noRead','--rapid-regrant','--test-dsn',sink.dsn)
        self.assertEqual(r['outcomes'],['regranted']);self.assertTrue(r['consent']);self.assertEqual(r['pending'],0);self.assertEqual(sink.requests,[])
    def children(self,pid):
        p=subprocess.run(['pgrep','-P',str(pid)],capture_output=True,text=True)
        return [int(v) for v in p.stdout.split()]
    def alive(self,pid):
        try:os.kill(pid,0);return True
        except ProcessLookupError:return False
    def test_08_parent_exit_reaps_worker_reading_and_before_read(self):
        sink=i.Sink(delay=3);self.addCleanup(sink.close)
        for fault in ['noRead','none']:
            p=subprocess.Popen(self.command('--worker-fault',fault,'--test-dsn',sink.dsn),stdout=subprocess.PIPE,stderr=subprocess.PIPE,preexec_fn=i.no_core_dump)
            self.addCleanup(lambda p=p:p.kill() if p.poll() is None else None)
            end=time.monotonic()+3;children=[]
            while time.monotonic()<end and not children:children=self.children(p.pid);time.sleep(.02)
            self.assertEqual(len(children),1);time.sleep(.15)
            p.kill();p.communicate(timeout=3)
            end=time.monotonic()+2
            while time.monotonic()<end and any(self.alive(c) for c in children):time.sleep(.02)
            self.assertFalse(any(self.alive(c) for c in children))
            # Next launch owns cleanup of any cache left by a killed parent.
            q=subprocess.run([str(i.EXE),'--state-root',str(self.state),'--status'],capture_output=True,timeout=5)
            self.assertEqual(q.returncode,0);self.assertFalse((self.state/'sentry-cache').exists())
            self.evidence.append({'fault':fault,'childExited':True})
    def test_09_twenty_workers_no_descriptor_growth(self):
        r=self.probe('exitAfterRead','--attempts','20')
        self.assertEqual(r['callbacks'],20);self.assertEqual(r['outcomes'],['pending']*20)
        self.assertLessEqual(r['fds'][-1],r['fds'][0]+1)
    def test_10_large_report_actual_sdk_transport(self):
        self.large_report();sink=i.Sink();self.addCleanup(sink.close)
        r=self.probe('none','--test-dsn',sink.dsn)
        self.assertEqual(r['outcomes'],['http-accepted']);self.assertEqual(len(sink.events()),1);self.assertEqual(r['pending'],0)
if __name__=='__main__':unittest.main(verbosity=2)
