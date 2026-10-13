from pathlib import Path
import subprocess,json,os,resource,sys
base=Path('/private/tmp/OKVideoMac-CrashIntegration');fixture=json.loads((base/'Stage8UI/cycles-fixture.json').read_text());exe=str(Path(fixture['app'])/'Contents/MacOS/OKVideoMac');cycle=int(sys.argv[1])
rows=subprocess.check_output(['/bin/ps','-axo','command='],text=True).splitlines();assert exe not in rows
root=Path(fixture['root']);reports=root/'Application Support/Diagnostics/CrashReports'
assert json.loads((reports/'consent.json').read_text()) is False and not list((reports/'pending').glob('*.json'))
def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
env=os.environ.copy();env['OKVIDEOMAC_8B3B_ROOT']=str(root)
r=subprocess.run([exe,'--diagnostic-crash-stage','entry'],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,preexec_fn=no_core,timeout=15)
assert r.returncode<0,r.returncode
(base/f'stage8-cycle-crash-{cycle}.log').write_bytes(r.stdout);print(json.dumps({'new_recovery_cycle':cycle,'fault_returncode':r.returncode,'previous_app_exited':True}))
