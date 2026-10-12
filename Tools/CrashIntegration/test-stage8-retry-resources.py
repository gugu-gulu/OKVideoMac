from pathlib import Path
import json,os,subprocess,tempfile,time,resource,statistics
base=Path('/private/tmp/OKVideoMac-CrashIntegration');app=base/'Stage7Acceptance/OKVideoMac.app/Contents/MacOS/OKVideoMac';root=Path(tempfile.mkdtemp(prefix='OKVideoMac-8B3B-stage8-retries-',dir='/private/tmp'))
env=os.environ.copy();env['OKVIDEOMAC_8B3B_ROOT']=str(root)
def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
p=subprocess.run([str(app),'--diagnostic-crash-stage','entry'],env=env,capture_output=True,preexec_fn=no_core,timeout=20);assert p.returncode<0
recovered=subprocess.run([str(app),'--diagnostic-export'],env=env,capture_output=True,text=True,check=True,timeout=20)
assert json.loads(recovered.stdout.splitlines()[-1])['reports'], 'Require actual recovered record before stress test'
log=base/'logs/stage8-retries.log';samples=[]
with log.open('wb') as out:
 p=subprocess.Popen([str(app),'--diagnostic-upload-probe','--attempts','30','--test-dsn','http://public@127.0.0.1:9482/1'],env=env,stdout=out,stderr=out)
 start=time.monotonic()
 while p.poll() is None:
  if time.monotonic()-start>300:p.kill();raise AssertionError('bounded retry test exceeded 300s')
  v=subprocess.run(['ps','-p',str(p.pid),'-o','rss=,pcpu='],capture_output=True,text=True).stdout.split()
  if len(v)==2:
   threads=len(subprocess.run(['ps','-M','-p',str(p.pid)],capture_output=True,text=True).stdout.splitlines())-1
   fds=subprocess.run(['lsof','-a','-p',str(p.pid),'-F','f'],capture_output=True,text=True).stdout.splitlines()
   kids=subprocess.run(['pgrep','-P',str(p.pid)],capture_output=True,text=True).stdout.split()
   samples.append(dict(seconds=round(time.monotonic()-start,3),rss_kib=int(v[0]),cpu_percent=float(v[1]),threads=threads,file_descriptors=sum(x.startswith('f') and x[1:].isdigit() for x in fds),children=len(kids)))
  time.sleep(.25)
 assert p.returncode==0
line=next(x for x in reversed(log.read_text().splitlines()) if x.startswith('{'))
result=json.loads(line)
assert result['callbacks']==30 and len(result['outcomes'])==30 and all(x=='pending' for x in result['outcomes']),result
assert result['fds'][0]==result['fds'][-1] and not result['cacheExists']
assert result['pending']==1 and result['maxMainGap']<.25
r=subprocess.run([str(app),'--diagnostic-upload-model','--diagnostic-revoke'],env=env,capture_output=True,text=True,check=True)
revoked=json.loads(r.stdout.splitlines()[-1]);assert revoked['consent']==False and revoked['pending']==0
output={'status':'PASS','scope':'30 actual adapter failures in same Release process; no SwiftUI business initialization; real UI loop separate','probe':result,'revoked':revoked,'samples':samples,'root':str(root),'binary':str(app)}
(base/'stage8-retry-resources.json').write_text(json.dumps(output,indent=2)+'\n')
print(json.dumps({'status':output['status'],'probe':result,'samples':len(samples),'rss_first_last':[samples[0]['rss_kib'],samples[-1]['rss_kib']]},indent=2))
