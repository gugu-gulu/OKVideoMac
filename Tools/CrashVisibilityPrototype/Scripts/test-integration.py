#!/usr/bin/env python3
"""Run real Release crashes and inspect actual SDK requests using a loopback-only sink."""
import gzip, http.server, json, pathlib, plistlib, resource, socket, subprocess, tempfile, threading, time, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
APP=ROOT/'build/CrashVisibilityPrototype.app'
EXE=APP/'Contents/MacOS/CrashVisibilityPrototype'
SYMBOLS=ROOT/'build/symbols'
BUNDLE=plistlib.loads((APP/'Contents/Info.plist').read_bytes())
def no_core_dump(): resource.setrlimit(resource.RLIMIT_CORE,(0,0))

class Sink:
    def __init__(self, status=200, delay=0):
        self.requests=[];self.status=status;self.delay=delay
        parent=self
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                data=self.rfile.read(int(self.headers['Content-Length']))
                if self.headers.get('Content-Encoding')=='gzip':data=gzip.decompress(data)
                parent.requests.append(data)
                time.sleep(parent.delay)
                self.send_response(parent.status);self.end_headers()
                try:self.wfile.write(b'{}')
                except (BrokenPipeError,ConnectionResetError):pass
            def log_message(self,*args):pass
        self.server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.dsn=f'http://public@127.0.0.1:{self.server.server_port}/1'
    def close(self):self.server.shutdown();self.server.server_close()
    def events(self):
        result=[]
        for request in self.requests:
            lines=request.splitlines();index=1
            while index<len(lines):
                header=json.loads(lines[index]);body=json.loads(lines[index+1]);index+=2
                assert header['type']=='event',f'unexpected SDK item: {header}'
                result.append(body)
        return result

class Integration(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='cvp-integration-',dir=ROOT/'build')
        self.state=pathlib.Path(self.temp.name)/'state'
    def tearDown(self):self.temp.cleanup()
    def run_app(self,*args,check=True):
        # Original single-attempt bound stays 20s; only the new 21-attempt stress case gets a cumulative bound.
        timeout=20+(int(args[args.index('--retry-count')+1])*8 if '--retry-count' in args else 0)
        r=subprocess.run([str(EXE),'--state-root',str(self.state),*args],capture_output=True,text=True,timeout=timeout,preexec_fn=no_core_dump)
        if check:self.assertEqual(r.returncode,0,r.stdout+'\n'+r.stderr)
        return r
    def status(self,*args):
        r=self.run_app(*args)
        return json.loads([line for line in r.stdout.splitlines() if line.startswith('{')][-1])
    def crash(self,kind='swift-pre',*extra):
        r=self.run_app('--crash',kind,*extra,check=False)
        self.assertLess(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual('mock-bootstrap-complete' in r.stdout,kind.endswith('post'))
    def recover(self):
        status=self.status('--status');self.assertTrue(status['recovered']);self.assertFalse(status['recoveryFailed'])
        return json.loads(self.run_app('--export').stdout)
    def assert_exception_grouping_stack(self,event,original):
        crashed=next(t for t in event['threads']['values'] if t['crashed'])
        exception=event['exception']['values'][0]
        self.assertEqual(exception['thread_id'],crashed['id'])
        self.assertIn('stacktrace',exception,'Sentry grouping needs the crashed stack on the exception itself')
        self.assertEqual(exception['stacktrace'],crashed['stacktrace'])
        names={image['base']:image['name'] for image in original['images']}
        own_names={'CrashVisibilityPrototype','libCVPCrashFixture.dylib'}
        frames=exception['stacktrace']['frames'];self.assertTrue(frames)
        for frame in frames:
            expected=names.get(int(frame.get('image_addr','0'),16)) in own_names
            self.assertEqual(frame['in_app'],expected)
        self.assertTrue(any(frame['in_app'] for frame in frames))
    def test_01_first_run_swift_before_bootstrap(self):
        self.crash();records=self.recover();self.assertEqual(len(records),1)
        self.assertEqual(records[0]['signal'],'SIGTRAP');self.assertEqual(records[0]['version'],BUNDLE['CFBundleShortVersionString'])
    def test_02_swift_after_bootstrap(self):
        self.crash('swift-post');self.assertEqual(len(self.recover()),1)
    def test_03_c_before_and_after_bootstrap(self):
        for phase in ['c-pre','c-post']:
            self.crash(phase);records=self.recover();self.assertIn(records[-1]['signal'],('SIGBUS','SIGSEGV'))
            names=[i['name'] for i in records[-1]['images']];self.assertIn('libCVPCrashFixture.dylib',names)
    def test_04_default_denies_all_requests(self):
        sink=Sink();self.addCleanup(sink.close);self.crash()
        for _ in range(3):
            status=self.status('--send','--test-dsn',sink.dsn);self.assertFalse(status['consent']);self.assertFalse(status['sdkStarted'])
        self.assertEqual(sink.requests,[])
    def test_05_consent_actual_sdk_event_privacy_and_single_send(self):
        sink=Sink();self.addCleanup(sink.close);self.crash();original=self.recover()[0]
        result=self.status('--grant','--send','--contaminate','--test-dsn',sink.dsn)
        self.assertEqual(result['result'],'http-accepted');self.assertTrue(result['handlersUnchanged'])
        self.status('--send','--test-dsn',sink.dsn);self.assertEqual(len(sink.requests),1)
        event=sink.events()[0]
        self.assert_exception_grouping_stack(event,original)
        self.assertEqual(set(event),{'contexts','debug_meta','dist','environment','event_id','exception','level','platform','release','threads','timestamp'})
        self.assertEqual(event['event_id'],original['id']);self.assertEqual(event['dist'],BUNDLE['CFBundleVersion'])
        self.assertEqual(set(event['contexts']),{'os','device'})
        self.assertEqual(event['contexts']['device'],{'arch':'arm64'})
        data=sink.requests[0]
        for forbidden in [b'DO_NOT_SEND',b'/Users/',b'token=secret',b'video-title',b'"user"',b'"request"',b'"breadcrumbs"',b'"registers":{']:
            self.assertNotIn(forbidden,data)
        self.assertFalse((self.state/'sentry-cache').exists())
    def test_06_failure_retains_same_event_for_retry(self):
        sink=Sink(503);self.addCleanup(sink.close);self.crash();original=self.recover()[0]
        result=self.status('--grant','--send','--test-dsn',sink.dsn);self.assertEqual(result['result'],'pending')
        self.assertEqual(self.status('--status')['pending'],1)
        sink.status=200
        self.assertEqual(self.status('--send','--test-dsn',sink.dsn)['result'],'http-accepted')
        self.assertEqual([e['event_id'] for e in sink.events()],[original['id'],original['id']])
    def test_07_revoke_clears_pending_and_stale_sdk_cache(self):
        sink=Sink(503);self.addCleanup(sink.close);self.crash()
        self.status('--grant','--send','--test-dsn',sink.dsn)
        cache=self.state/'sentry-cache';cache.mkdir(exist_ok=True);(cache/'stale-envelope').write_text('DO_NOT_SEND')
        result=self.status('--revoke');self.assertFalse(result['consent']);self.assertEqual(result['pending'],0)
        count=len(sink.requests);self.status('--send','--test-dsn',sink.dsn)
        self.assertEqual(len(sink.requests),count);self.assertFalse(cache.exists())
    def test_08_revoke_inflight_no_retry_or_residual_cache(self):
        sink=Sink(delay=2);self.addCleanup(sink.close);self.crash()
        result=self.status('--grant','--send','--test-dsn',sink.dsn,'--revoke-after','0.15')
        self.assertEqual(result['result'],'revoked');self.assertTrue(result['handlersUnchanged'])
        count=len(sink.requests);time.sleep(2.1)
        state=self.status('--send','--test-dsn',sink.dsn)
        self.assertFalse(state['consent']);self.assertEqual(state['pending'],0)
        self.assertEqual(len(sink.requests),count);self.assertFalse((self.state/'sentry-cache').exists())
    def test_09_original_metadata_survives_simulated_upgrade(self):
        self.crash('swift-pre','--test-version','0.0.9','--test-build','9');self.recover()
        sink=Sink();self.addCleanup(sink.close)
        self.status('--grant','--send','--test-dsn',sink.dsn,'--test-version','0.2.0','--test-build','20')
        event=sink.events()[0];self.assertEqual(event['dist'],'9');self.assertTrue(event['release'].endswith('@0.0.9+9'))
    def test_10_twelve_lifecycles_and_bounded_storage(self):
        for i in range(12):
            self.crash('swift-pre' if i%2==0 else 'c-post');records=self.recover()
            self.assertEqual(len(records),min(i+1,3))
        self.assertFalse((self.state/'sentry-cache').exists())
    def test_11_malformed_pending_report_does_not_loop(self):
        self.crash();raw=[p for p in (self.state/'raw').rglob('*') if p.is_file() and p.stat().st_size>0]
        self.assertEqual(len(raw),1);raw[0].write_bytes(b'corrupt synthetic report')
        status=self.status('--status');self.assertTrue(status['recoveryFailed']);self.assertEqual(status['pending'],0)
        status=self.status('--status');self.assertFalse(status['recoveryFailed'])
        self.crash();self.assertEqual(len(self.recover()),1)
    def test_12_unwritable_store_fails_open(self):
        self.state.parent.mkdir(exist_ok=True);self.state.write_text('a file cannot be a report directory')
        r=self.run_app('--status');self.assertIn('mock-bootstrap-complete',r.stdout)
        self.assertEqual(json.loads(r.stdout.splitlines()[-1])['businessBootstrap'],'continued')
    def test_13_local_dsym_symbolication_swift_and_c(self):
        evidence=[]
        for kind,module,function,source in [('swift-pre','CrashVisibilityPrototype','swiftCrashFixture','Entry.swift'),('c-pre','libCVPCrashFixture.dylib','cvp_faulting_write','CrashFixture.c')]:
            # PLCrashReporter timestamps have second precision. Isolate fixtures so a tied
            # timestamp cannot select the preceding Swift report as the C report.
            self.state=pathlib.Path(self.temp.name)/kind
            self.crash(kind);records=self.recover();self.assertEqual(len(records),1);record=records[0]
            image=next(i for i in record['images'] if i['name']==module)
            self.assertIn('vmaddr',image)
            thread=next(t for t in record['threads'] if t['crashed'])
            pcs=[f['pc'] for f in reversed(thread['frames']) if f.get('imageBase')==image['base']]
            self.assertTrue(pcs)
            dwarf=SYMBOLS/(module+'.dSYM')/'Contents/Resources/DWARF'/module
            output=subprocess.check_output(['atos','-arch','arm64','-o',str(dwarf),'-l',hex(image['base']),*[hex(pc) for pc in pcs]],text=True)
            self.assertIn(function,output);self.assertIn(source+':',output)
            evidence.append({'kind':kind,'module':module,'uuid':image['uuid'],'symbolication':output.strip()})
        (ROOT/'build/local-symbolication.json').write_text(json.dumps(evidence,indent=2))
    def test_14_missing_configuration_never_sends(self):
        self.crash();result=self.status('--grant','--send')
        self.assertTrue(result['consent']);self.assertEqual(result['pending'],1);self.assertFalse(result['sdkStarted'])

    def test_15_capture_still_works_after_sdk_close(self):
        sink=Sink();self.addCleanup(sink.close);self.crash();self.recover()
        r=self.run_app('--grant','--send','--test-dsn',sink.dsn,'--crash-after-sdk-close',check=False)
        self.assertLess(r.returncode,0,r.stdout+r.stderr)
        outcome=json.loads(r.stdout.splitlines()[0]);self.assertTrue(outcome['handlersUnchanged'])
        self.assertIn(self.recover()[-1]['signal'],('SIGBUS','SIGSEGV'))
    def test_16_capture_while_sdk_is_active(self):
        sink=Sink(delay=1);self.addCleanup(sink.close);self.crash();previous={r['id'] for r in self.recover()}
        r=self.run_app('--grant','--send','--test-dsn',sink.dsn,'--crash-while-sdk-active',check=False)
        self.assertLess(r.returncode,0,r.stdout+r.stderr)
        records=self.recover();self.assertEqual(len(records),2)
        new=[r for r in records if r['id'] not in previous];self.assertEqual(len(new),1)
        self.assertIn(new[0]['signal'],('SIGBUS','SIGSEGV'))
        self.assertFalse((self.state/'sentry-cache').exists())

    def test_17_c_exception_carries_grouping_stack(self):
        sink=Sink();self.addCleanup(sink.close);self.crash('c-pre');original=self.recover()[0]
        result=self.status('--grant','--send','--test-dsn',sink.dsn)
        self.assertEqual(result['result'],'http-accepted')
        self.assert_exception_grouping_stack(sink.events()[0],original)

    def test_18_recovery_prompt_ack_survives_clean_restart(self):
        self.crash()
        first=self.status('--recovery-probe');self.assertTrue(first['waitingForDecision']);self.assertEqual(first['bootstrapCount'],0)
        continued=self.status('--recovery-probe','--continue-recovery')
        self.assertFalse(continued['consent']);self.assertEqual(continued['bootstrapCount'],1)
        clean=self.status('--recovery-probe');self.assertFalse(clean['waitingForDecision']);self.assertEqual(clean['bootstrapCount'],1)
        self.assertEqual(clean['pending'],1)
        self.crash('c-pre');new=self.status('--recovery-probe');self.assertTrue(new['waitingForDecision']);self.assertEqual(new['pending'],2)
    def test_19_existing_consent_auto_sends_and_copy_changes(self):
        sink=Sink();self.addCleanup(sink.close)
        self.status('--grant');self.crash()
        state=self.status('--recovery-probe','--test-dsn',sink.dsn)
        self.assertTrue(state['consent']);self.assertEqual(state['pending'],0)
        self.assertIn('接收端已确认',state['status']);self.assertNotIn('报告仅保存在本机',state['explanation'])
        clean=self.status('--recovery-probe','--test-dsn',sink.dsn)
        self.assertFalse(clean['waitingForDecision']);self.assertEqual(clean['bootstrapCount'],1)
        self.assertEqual(len(sink.requests),1)
    def test_20_offline_recovery_continues_then_online_retries_same_id(self):
        # Bind without listening, reserving the endpoint while forcing connection refused.
        offline=socket.socket();offline.bind(('127.0.0.1',0));self.addCleanup(offline.close)
        self.crash();original=self.recover()[0]
        dsn=f'http://public@127.0.0.1:{offline.getsockname()[1]}/1'
        start=time.monotonic();state=self.status('--recovery-probe','--grant','--continue-recovery','--test-dsn',dsn)
        self.assertLess(time.monotonic()-start,12);self.assertEqual(state['bootstrapCount'],1)
        self.assertEqual(state['pending'],1);self.assertIn('保留待重试',state['status'])
        self.assertFalse((self.state/'sentry-cache').exists())
        sink=Sink();self.addCleanup(sink.close)
        state=self.status('--recovery-probe','--test-dsn',sink.dsn)
        self.assertEqual(state['pending'],0);self.assertEqual(sink.events()[0]['event_id'],original['id'])
    def test_21_recovery_model_inflight_revoke(self):
        sink=Sink(delay=2);self.addCleanup(sink.close);self.crash()
        state=self.status('--recovery-probe','--grant','--test-dsn',sink.dsn,'--revoke-after','0.15')
        self.assertFalse(state['consent']);self.assertEqual(state['pending'],0);self.assertIn('授权已关闭',state['status'])
        count=len(sink.requests);time.sleep(2.1)
        state=self.status('--recovery-probe','--test-dsn',sink.dsn)
        self.assertEqual(len(sink.requests),count);self.assertFalse(state['consent']);self.assertFalse((self.state/'sentry-cache').exists())
    def test_22_recovery_model_preserves_old_metadata_after_upgrade(self):
        sink=Sink();self.addCleanup(sink.close)
        self.crash('swift-pre','--test-version','0.0.9','--test-build','9')
        self.status('--recovery-probe','--grant','--test-dsn',sink.dsn,'--test-version','0.2.0','--test-build','20')
        event=sink.events()[0];self.assertEqual(event['dist'],'9');self.assertTrue(event['release'].endswith('@0.0.9+9'))
    def test_23_malformed_report_recovery_model_continues(self):
        self.crash();raw=next((self.state/'raw').rglob('*.plcrash'));raw.write_bytes(b'broken')
        state=self.status('--recovery-probe');self.assertFalse(state['waitingForDecision']);self.assertEqual(state['bootstrapCount'],1)
        self.assertFalse(state['consent']);self.assertEqual(state['pending'],0)
    def test_24_revoke_restart_crash_stays_local(self):
        sink=Sink();self.addCleanup(sink.close);self.status('--grant')
        state=self.status('--recovery-probe','--revoke','--test-dsn',sink.dsn);self.assertFalse(state['consent'])
        self.crash('c-post');state=self.status('--recovery-probe','--test-dsn',sink.dsn)
        self.assertFalse(state['consent']);self.assertTrue(state['waitingForDecision']);self.assertEqual(state['pending'],1)
        self.assertEqual(sink.requests,[])

    def test_25_twenty_offline_retries_in_one_process(self):
        offline=socket.socket();offline.bind(('127.0.0.1',0));self.addCleanup(offline.close)
        self.crash();original=self.recover()[0]
        dsn=f'http://public@127.0.0.1:{offline.getsockname()[1]}/1'
        state=self.status('--recovery-probe','--grant','--continue-recovery','--retry-count','20','--test-dsn',dsn)
        self.assertEqual(state['bootstrapCount'],1);self.assertEqual(state['pending'],1)
        self.assertEqual(json.loads(self.run_app('--export').stdout)[0]['id'],original['id'])
        self.assertFalse((self.state/'sentry-cache').exists())
        sink=Sink();self.addCleanup(sink.close)
        self.status('--recovery-probe','--test-dsn',sink.dsn)
        self.assertEqual([event['event_id'] for event in sink.events()],[original['id']])
    def test_26_slow_response_does_not_block_startup_or_erase_report(self):
        sink=Sink(delay=6);self.addCleanup(sink.close);self.crash();original=self.recover()[0]
        start=time.monotonic()
        state=self.status('--recovery-probe','--grant','--continue-recovery','--test-dsn',sink.dsn)
        self.assertLess(time.monotonic()-start,12);self.assertEqual(state['bootstrapCount'],1)
        self.assertEqual(state['pending'],1);self.assertFalse((self.state/'sentry-cache').exists())
        self.assertEqual(json.loads(self.run_app('--export').stdout)[0]['id'],original['id'])
    def test_27_no_upload_worker_remains_after_revoke(self):
        sink=Sink(delay=2);self.addCleanup(sink.close);self.crash()
        process=subprocess.Popen([str(EXE),'--state-root',str(self.state),'--recovery-probe','--grant',
            '--test-dsn',sink.dsn,'--revoke-after','0.7'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,preexec_fn=no_core_dump)
        children=set();deadline=time.monotonic()+10
        while process.poll() is None and time.monotonic()<deadline:
            result=subprocess.run(['pgrep','-P',str(process.pid)],capture_output=True,text=True)
            children.update(int(pid) for pid in result.stdout.split())
            time.sleep(0.03)
        stdout,stderr=process.communicate(timeout=5)
        self.assertEqual(process.returncode,0,stdout+stderr);self.assertTrue(children,'must observe the actual upload worker')
        for pid in children:
            result=subprocess.run(['ps','-p',str(pid),'-o','pid='],capture_output=True,text=True)
            self.assertEqual(result.stdout.strip(),'','upload worker leaked after revocation')
        self.assertFalse((self.state/'sentry-cache').exists())

if __name__=='__main__':
    unittest.main(verbosity=2)
