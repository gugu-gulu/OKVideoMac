from pathlib import Path
import json,subprocess,sys
base=Path('/private/tmp/OKVideoMac-CrashIntegration');f=json.loads((base/'Stage8SDKAcceptance/fixture.json').read_text());root=Path(f['root']);pid=int(sys.argv[2]);cycle=int(sys.argv[1])
rows=subprocess.run(['/bin/ps','-p',str(pid),'-o','pid=,command='],capture_output=True,text=True).stdout.strip();assert not rows,rows
traces=[json.loads(l) for l in (root/'crash-lifecycle.jsonl').read_text().splitlines()];r=[x for x in traces if x['pid']==pid];assert r[-1]['event']=='termination-replied'
out={'cycle':cycle,'pid':pid,'normal_exit':True,'termination_trace':r,'duration_seconds':r[-1]['uptime']-r[0]['uptime']}
with (base/'stage8-sdk-ui-exits.jsonl').open('a') as h:h.write(json.dumps(out)+'\n')
print({k:v for k,v in out.items() if k!='termination_trace'})
