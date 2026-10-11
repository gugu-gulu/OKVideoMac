#!/usr/bin/env python3
"""Optional G0 upload only; never called by the formal OKVideoMac release pipeline."""
import argparse,os,pathlib,shutil,stat,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]

def configuration(path):
    p=pathlib.Path(path);s=p.lstat()
    if not stat.S_ISREG(s.st_mode) or s.st_uid!=os.getuid() or s.st_mode&0o077 or s.st_size>16384:
        raise ValueError('Private configuration must be an owner-only regular file (chmod 600).')
    allowed={'SENTRY_ORG','SENTRY_PROJECT','SENTRY_AUTH_TOKEN'};values={}
    for line in p.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('#'):continue
        key,sep,value=line.partition('=');key=key.strip();value=value.strip()
        if not sep or key not in allowed or key in values:raise ValueError('Unexpected or duplicate configuration key.')
        values[key]=value
    if set(values)!=allowed or not all(values.values()) or values['SENTRY_PROJECT']!='okvideomac-macos':
        raise ValueError('Require org, nonempty auth token, and project okvideomac-macos.')
    return values

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-only',action='store_true',help='Validate local App/dSYMs without network or credentials')
    parser.add_argument('--config',type=pathlib.Path,help='Owner-only private symbols.env outside the checkout')
    args=parser.parse_args();os.umask(0o077)
    subprocess.run([sys.executable,str(ROOT/'Scripts/verify-package.py')],check=True)
    if args.check_only:
        print('PASS: local symbol gate; remote upload NOT_TESTED');return
    if args.config is None:parser.error('--config is required for upload; use --check-only for local verification')
    config=configuration(args.config)
    cli=shutil.which('sentry-cli')
    if cli is None:raise ValueError('Install official sentry-cli before remote symbol validation.')
    env={k:v for k,v in os.environ.items() if not k.startswith('SENTRY_')}
    env.update(config);env['SENTRY_LOG_LEVEL']='warn';env['SENTRY_DISABLE_UPDATE_CHECK']='1'
    # Only debug information; --include-sources is deliberately absent.
    result=subprocess.run([cli,'debug-files','upload','--wait',str(ROOT/'build/symbols')],env=env,capture_output=True,text=True)
    redacted=(result.stdout+'\n'+result.stderr).replace(config['SENTRY_AUTH_TOKEN'],'[REDACTED]')
    (ROOT/'build/symbol-upload.log').write_text(redacted)
    if result.returncode:raise ValueError('Symbol upload failed. Inspect the redacted local build/symbol-upload.log; do not count remote validation as passed.')
    print('Debug file upload/processing completed. Verify both UUIDs and actual event frames in the private Sentry project.')

if __name__=='__main__':
    try:main()
    except (ValueError,OSError,subprocess.CalledProcessError) as error:
        print(str(error),file=sys.stderr);sys.exit(1)
