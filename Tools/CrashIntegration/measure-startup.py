#!/usr/bin/env python3
"""Measure isolated test-host launches; never runs the installed application."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import time

ROOT = Path('/private/tmp/OKVideoMac-CrashIntegration')
SOURCE = ROOT / 'DerivedData/Build/Products/Release/OKVideoMac.app'
APP = ROOT / 'Baseline/OKVideoMac.app'
PROBE = ROOT / 'window-probe'

def run():
    ROOT.chmod(0o700)
    APP.parent.mkdir(exist_ok=True)
    assert SOURCE.is_dir() and not APP.exists()
    shutil.copytree(SOURCE, APP, symlinks=True)
    binary = APP / 'Contents/MacOS/OKVideoMac'
    runs = []
    for iteration in range(5):
        env = os.environ.copy()
        # Existing production test isolation, recognized before any database is opened.
        env['XCTestBundlePath'] = str(ROOT / 'measurement-only.xctest')
        env.pop('XCTestConfigurationFilePath', None)
        env.pop('OKVIDEOMAC_8B3B_ROOT', None)
        start = time.monotonic()
        with (ROOT / f'logs/baseline-launch-{iteration}.log').open('wb') as log:
            process = subprocess.Popen([str(binary)], env=env, stdout=log, stderr=log)
            try:
                visible = 0
                while time.monotonic() - start < 30 and process.poll() is None:
                    visible = int(subprocess.check_output([str(PROBE), str(process.pid)], text=True))
                    if visible: break
                    time.sleep(0.05)
                elapsed = time.monotonic() - start
                assert visible == 1, f'Expected one visible browsing window, got {visible}'
                samples = []
                for _ in range(3):
                    time.sleep(1)
                    rss, cpu = subprocess.check_output(['/bin/ps', '-o', 'rss=,pcpu=', '-p', str(process.pid)], text=True).split()
                    threads = len(subprocess.check_output(['/bin/ps', '-M', '-p', str(process.pid)], text=True).splitlines()) - 1
                    fds = subprocess.run(['/usr/sbin/lsof', '-a', '-p', str(process.pid), '-F', 'f'], capture_output=True, text=True, check=True).stdout.splitlines()
                    samples.append({'rss_kib': int(rss), 'cpu_percent': float(cpu), 'threads': threads, 'file_descriptors': sum(line.startswith('f') and line[1:].isdigit() for line in fds)})
                runs.append({'iteration': iteration, 'first_visible_window_seconds': elapsed, 'samples': samples})
                print(f'Baseline launch {iteration+1}/5: {elapsed:.3f}s, RSS {samples[-1]["rss_kib"]} KiB', flush=True)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try: process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill(); process.wait(timeout=5)
    medians = {name: statistics.median(sample[name] for run in runs for sample in run['samples']) for name in runs[0]['samples'][0]}
    startup = statistics.median(run['first_visible_window_seconds'] for run in runs)
    result = {
        'baseline_commit': 'ca0a169', 'configuration': 'Release test host',
        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'isolation': 'distinct test bundle ID plus existing XCTest runtime-directory policy',
        'measurement_scope': 'first visible window and empty-workspace idle samples; not cold-cache or termination acceptance',
        'runs': runs, 'median_first_window_seconds': startup, 'median_idle': medians,
        'locked_limits': {
            'first_window_seconds': startup + max(0.25, startup*0.25),
            'idle_rss_kib': medians['rss_kib'] + max(25*1024, medians['rss_kib']*0.20),
            'idle_threads': medians['threads']+2,
            'idle_file_descriptors': medians['file_descriptors']+4,
            'idle_cpu_percent': medians['cpu_percent']+2,
            'idle_upload_children': 0,
            'post_retry_resources': 'return to the same idle bounds after worker reaping and cache cleanup',
        },
    }
    (ROOT / 'stage1-startup-baseline.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: result[k] for k in ['median_first_window_seconds','median_idle','locked_limits']}, indent=2))

if __name__ == '__main__': run()
