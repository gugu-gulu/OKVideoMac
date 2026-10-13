from pathlib import Path
import json,subprocess,time,sys,hashlib
base=Path('/private/tmp/OKVideoMac-CrashIntegration');f=json.loads((base/'Stage8SDKAcceptance/fixture.json').read_text());root=Path(f['root']);exe=str(Path(f['app'])/'Contents/MacOS/OKVideoMac')
rows=[r.split(None,2) for r in subprocess.check_output(['/bin/ps','-axo','pid=,ppid=,command='],text=True).splitlines()]
apps=[r for r in rows if len(r)==3 and r[2]==exe];assert len(apps)==1,apps
pid=int(apps[0][0]);rss,cpu=subprocess.check_output(['/bin/ps','-p',str(pid),'-o','rss=,%cpu='],text=True).split();fds=subprocess.check_output(['/usr/sbin/lsof','-a','-p',str(pid),'-F','f'],text=True).splitlines()
record=root/'Application Support/AndroidRuntime/runtime-selection.json';reports=root/'Application Support/Diagnostics/CrashReports'
data={'phase':sys.argv[1],'pid':pid,'time':time.time(),'rss_kib':int(rss),'cpu_percent':float(cpu),'threads':len(subprocess.check_output(['/bin/ps','-M','-p',str(pid)],text=True).splitlines())-1,'fds':sum(x.startswith('f') and x[1:].isdigit() for x in fds),'children':[r for r in rows if r[1]==str(pid)],'selection_sha256':hashlib.sha256(record.read_bytes()).hexdigest(),'mode':json.loads(record.read_text())['mode'],'pending_reports':len(list((reports/'pending').glob('*.json'))),'upload_cache_exists':(reports/'sentry-cache').exists(),'avd_created':(root/'Application Support/AndroidRuntime/avd/OKVideoMac_Runtime.avd').exists()}
with (base/'stage8-sdk-ui-resources.jsonl').open('a') as h:h.write(json.dumps(data)+'\n')
print(json.dumps(data))
