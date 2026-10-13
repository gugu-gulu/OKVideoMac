"""Create isolated symbol-verification artifacts from the tested Release products."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

p = argparse.ArgumentParser()
p.add_argument('--products', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--kind', choices=['acceptance', 'normal-release'], required=True)
a = p.parse_args()
repo = Path.cwd()
scripts = repo / 'OKVideoMac/macOS/OKVideoMac/Scripts'
app = a.output / 'OKVideoMac.app'
a.output.mkdir(parents=True, exist_ok=False)
shutil.copytree(a.products / 'OKVideoMac.app', app, symlinks=True)
# XCTest adds these only to a test host; neither artifact is a delivery package.
shutil.rmtree(app / 'Contents/PlugIns', ignore_errors=True)
for name in ['Testing.framework', 'XCTAutomationSupport.framework', 'XCTest.framework',
             'XCTestCore.framework', 'XCTestSupport.framework', 'XCUIAutomation.framework',
             'XCUnit.framework', 'libXCTestBundleInject.dylib', 'libXCTestSwiftSupport.dylib']:
    path = app / 'Contents/Frameworks' / name
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()


def run(*args):
    subprocess.run([str(v) for v in args], check=True)


extra = []
if a.kind == 'acceptance':
    info = app / 'Contents/Info.plist'
    data = plistlib.loads(info.read_bytes())
    data.update(CFBundleIdentifier='com.okvideomac.OKVideoMac.acceptance8b3b',
                CFBundleShortVersionString='0.8.4', CFBundleVersion='1377001')
    info.write_bytes(plistlib.dumps(data))
    fixture = app / 'Contents/Frameworks/libCrashAcceptanceFixture.dylib'
    obj = a.output / 'CrashFixture.o'
    run('xcrun', 'clang', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-O2', '-g',
        '-fno-omit-frame-pointer', '-c', repo / 'Tools/CrashIntegration/CrashFixture.c', '-o', obj)
    run('xcrun', 'clang', '-arch', 'arm64', '-mmacosx-version-min=12.0', '-dynamiclib', obj,
        '-install_name', '@rpath/libCrashAcceptanceFixture.dylib', '-o', fixture)
    run('xcrun', 'dsymutil', fixture, '-o', a.output / 'libCrashAcceptanceFixture.dylib.dSYM')
    extra = ['--symbols', a.output, '--require', 'Contents/Frameworks/libCrashAcceptanceFixture.dylib']
run(sys.executable, scripts / 'crash-image-metadata.py', app)
run(sys.executable, scripts / 'crash-symbols.py', 'archive', '--app', app,
    '--symbols', a.products, '--repo', repo, '--kind', a.kind,
    '--output', a.output / 'archive', *extra)
for relative in ['Contents/MacOS/OKVideoMac', 'Contents/Helpers/OKVideoMacRelauncher'] + (
        ['Contents/Frameworks/libCrashAcceptanceFixture.dylib'] if a.kind == 'acceptance' else []):
    run('strip', '-S', app / relative)
for path in app.rglob('*'):
    if path.is_file() and not path.is_symlink() and 'Mach-O' in subprocess.check_output(['file', '-b', str(path)], text=True):
        # Match package-app.sh: V8 requires JIT only on the bundled Node helper.
        entitlements = (['--entitlements', repo / 'OKVideoMac/macOS/OKVideoMac/Supporting/NodeHelper.entitlements']
                        if path == app / 'Contents/Resources/NodeRuntime/node' else [])
        run('codesign', '--force', '--sign', '-', '--options', 'runtime', *entitlements, path)
containers = [x for x in app.rglob('*') if x.is_dir() and not x.is_symlink()
              and x.suffix in ['.framework', '.app', '.xpc']]
for path in sorted(containers, key=lambda x: len(x.parts), reverse=True):
    run('codesign', '--force', '--sign', '-', '--options', 'runtime', path)
run('codesign', '--force', '--sign', '-', '--options', 'runtime', '--entitlements',
    repo / 'OKVideoMac/macOS/OKVideoMac/Supporting/OKVideoMac.dev.entitlements', app)
run('codesign', '--verify', '--deep', '--strict', app)
run(sys.executable, scripts / 'crash-symbols.py', 'verify', '--app', app,
    '--archive', a.output / 'archive', '--output', a.output / 'verified.json')
print(f'Prepared {a.kind} symbol artifact: {a.output}')
