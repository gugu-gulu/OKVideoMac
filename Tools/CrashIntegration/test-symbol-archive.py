"""Exercise symbol gates using real Mach-O/dSYMs, strip/sign and mismatched builds."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
if not (REPO / '.git').exists():
    REPO = Path.cwd()
SCRIPT = REPO / 'OKVideoMac/macOS/OKVideoMac/Scripts/crash-symbols.py'


def run(*args, ok=True):
    p = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    if ok:
        assert p.returncode == 0, p.stderr
    else:
        assert p.returncode != 0, 'Expected symbol gate rejection'
    return p


with tempfile.TemporaryDirectory(prefix='OKVideoMac-symbol-gate-') as tmp:
    root = Path(tmp)
    app = root / 'OKVideoMac.app'
    symbols = root / 'build'
    symbols.mkdir()
    source = root / 'probe.c'
    source.write_text('int main(void) { return 1; }\n')
    for relative, name in [('Contents/MacOS/OKVideoMac', 'OKVideoMac.app.dSYM'),
                           ('Contents/Helpers/OKVideoMacRelauncher', 'OKVideoMacRelauncher.dSYM')]:
        binary = app / relative
        binary.parent.mkdir(parents=True)
        run('xcrun', 'clang', '-g', '-O2', '-arch', 'arm64', source, '-o', binary)
        run('xcrun', 'dsymutil', binary, '-o', symbols / name)
    info = app / 'Contents/Info.plist'
    info.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.okvideomac.symboltest',
                                    'CFBundleShortVersionString': '0.0.1', 'CFBundleVersion': '1'}))
    archive = root / 'archive'
    base = [sys.executable, SCRIPT]
    archive_args = ['archive', '--app', app, '--symbols', symbols, '--repo', REPO,
                    '--kind', 'acceptance', '--output', archive]
    run(*base, *archive_args)
    run(*base, *archive_args, ok=False)
    for relative in ['Contents/MacOS/OKVideoMac', 'Contents/Helpers/OKVideoMacRelauncher']:
        run('strip', '-S', app / relative)
        run('codesign', '--force', '--sign', '-', app / relative)
    verify_args = ['verify', '--app', app, '--archive', archive, '--output', root / 'verified.json']
    run(*base, *verify_args)
    assert json.loads((root / 'verified.json').read_text())['status'] == 'PASS'
    manifest = json.loads((archive / 'manifest.json').read_text())
    dwarf = archive / manifest['images_before_strip'][0]['symbols'][0]['dwarf']
    original = dwarf.read_bytes()
    dwarf.write_bytes(original + b'changed')
    run(*base, *verify_args, ok=False)
    dwarf.write_bytes(original)
    info_bytes = info.read_bytes()
    altered = plistlib.loads(info_bytes)
    altered['CFBundleVersion'] = '2'
    info.write_bytes(plistlib.dumps(altered))
    run(*base, *verify_args, ok=False)
    info.write_bytes(info_bytes)
    source.write_text('int main(void) { return 2; }\n')
    run('xcrun', 'clang', '-g', '-O2', '-arch', 'arm64', source, '-o', app / 'Contents/MacOS/OKVideoMac')
    run(*base, *verify_args, ok=False)
    run(*base, 'archive', '--app', app, '--symbols', symbols, '--repo', REPO,
        '--kind', 'acceptance', '--output', root / 'mismatch', ok=False)
    result = {'status': 'PASS', 'cases': [
        'matching App/helper archive', 'immutable archive refuses overwrite',
        'UUID match survives strip and ad-hoc sign', 'modified dSYM hash rejected',
        'version mismatch rejected', 'different binary UUID rejected',
        'stale dSYM cannot satisfy required image']}
    print(json.dumps(result, indent=2))
