"""Apply unchanged baseline limits to a genuinely enabled capture process."""
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

ROOT=Path('/private/tmp/OKVideoMac-CrashIntegration')
capture=json.loads((ROOT/'stage5-upload.json').read_text())
APP=Path(capture['app_path']);EXE=APP/'Contents/MacOS/OKVideoMac'
ID='com.okvideomac.OKVideoMac.acceptance8b3b'
baseline=json.loads((ROOT/'stage1-startup-baseline.json').read_text())
limits=baseline['locked_limits'];runs=[]
for index in range(5):
    workspace=Path(tempfile.mkdtemp(prefix='OKVideoMac-8B3B-crash-resources-',dir='/private/tmp'))
    env=os.environ.copy();env.pop('XCTestBundlePath',None);env.pop('XCTestConfigurationFilePath',None)
    env['OKVIDEOMAC_8B3B_ROOT']=str(workspace)
    log=(ROOT/f'logs/stage5-resources-{index}.log').open('wb')
    start=time.monotonic();p=subprocess.Popen([str(EXE)],env=env,stdout=log,stderr=log)
    try:
        visible=0
        while time.monotonic()-start<30 and p.poll() is None:
            visible=int(subprocess.check_output([str(ROOT/'window-probe'),str(p.pid)],text=True))
            if visible:break
            time.sleep(.05)
        elapsed=time.monotonic()-start
        assert visible==1
        slot=workspace/'Application Support/Diagnostics/CrashReports/raw/com.plausiblelabs.crashreporter.data'/ID/'live_report.plcrash'
        assert slot.exists(),'The enabled capture slot must exist; do not measure a disabled XCTest host'
        samples=[]
        for _ in range(3):
            time.sleep(1)
            rss,cpu=subprocess.check_output(['/bin/ps','-o','rss=,pcpu=','-p',str(p.pid)],text=True).split()
            threads=len(subprocess.check_output(['/bin/ps','-M','-p',str(p.pid)],text=True).splitlines())-1
            lines=subprocess.check_output(['/usr/sbin/lsof','-a','-p',str(p.pid),'-F','f'],text=True).splitlines()
            process_rows=subprocess.check_output(['/bin/ps','-axo','pid=,ppid='],text=True).splitlines()
            children=sum(int(row.split()[1])==p.pid for row in process_rows)
            assert children==0
            samples.append({'rss_kib':int(rss),'cpu_percent':float(cpu),'threads':threads,
                'file_descriptors':sum(line.startswith('f') and line[1:].isdigit() for line in lines),'children':children})
        runs.append({'iteration':index,'first_visible_window_seconds':elapsed,'samples':samples})
        print(f'Enabled capture launch {index+1}/5: {elapsed:.3f}s, RSS {samples[-1]["rss_kib"]} KiB',flush=True)
        subprocess.run([str(ROOT/'instance-probe'),'quit',str(p.pid)],check=True);p.wait(timeout=12)
    finally:
        if p.poll() is None:p.terminate();p.wait(timeout=5)
        log.close()
medians={key:statistics.median(s[key] for run in runs for s in run['samples']) for key in runs[0]['samples'][0]}
startup=statistics.median(r['first_visible_window_seconds'] for r in runs)
checks={'first_window':startup<=limits['first_window_seconds'],'children':medians['children']==0}
for key in ['rss_kib','cpu_percent','threads','file_descriptors']:checks[key]=medians[key]<=limits['idle_'+key]
result={'status':'PASS' if all(checks.values()) else 'FAIL','runs':runs,'median_first_window_seconds':startup,
    'median_idle':medians,'checks':checks,'locked_limits':limits,
    'measurement_scope':'capture enabled in isolated acceptance ID/data; compared against unchanged absolute stage 1 bounds; database admission includes acceptance policy'}
(ROOT/'stage5-resources.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['status','median_first_window_seconds','median_idle','checks']},indent=2))
assert result['status']=='PASS',checks
