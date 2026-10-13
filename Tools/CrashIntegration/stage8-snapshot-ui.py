from pathlib import Path
import subprocess,json,time,sys
base=Path('/private/tmp/OKVideoMac-CrashIntegration');fixture=json.loads((base/'Stage8UI/cycles-fixture.json').read_text());root=Path(fixture['root'])
rows=[x.split(None,2) for x in subprocess.check_output(['/bin/ps','-axo','pid=,ppid=,command='],text=True).splitlines()]
apps=[r for r in rows if len(r)==3 and r[2]==str(Path(fixture['app'])/'Contents/MacOS/OKVideoMac')]
assert len(apps)==1,apps
pid=int(apps[0][0]);rss,cpu=subprocess.check_output(['/bin/ps','-p',str(pid),'-o','rss=,%cpu='],text=True).split()
fds=subprocess.check_output(['/usr/sbin/lsof','-a','-p',str(pid),'-F','f'],text=True).splitlines()
reports=root/'Application Support/Diagnostics/CrashReports';pending=list((reports/'pending').glob('*.json'))
data={'phase':sys.argv[1],'pid':pid,'time':time.time(),'rss_kib':int(rss),'cpu_percent':float(cpu),'threads':len(subprocess.check_output(['/bin/ps','-M','-p',str(pid)],text=True).splitlines())-1,'fds':sum(x.startswith('f') and x[1:].isdigit() for x in fds),'children':[r for r in rows if r[1]==str(pid)],'consent':json.loads((reports/'consent.json').read_text()) if (reports/'consent.json').exists() else False,'pending_ids':[json.loads(p.read_text()).get('id',p.stem) for p in pending],'cache_exists':(reports/'sentry-cache').exists(),'business_database_exists':(root/'Application Support/Database/OKVideoMac.sqlite3').exists(),'receiver_total':len((base/'stage8-loopback.jsonl').read_text().splitlines())}
with (base/'stage8-ui-resources.jsonl').open('a') as f:f.write(json.dumps(data)+'\n')
print(json.dumps(data))
