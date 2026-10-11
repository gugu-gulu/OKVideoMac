#!/usr/bin/env python3
"""Compile the exact public App lease class into the isolated rehearsal, with error/localization shims."""
import hashlib,json,pathlib
root=pathlib.Path(__file__).resolve().parents[1]
source=root.parents[1]/'OKVideoMac/macOS/OKVideoMac/App/AppEnvironment.swift'
text=source.read_text();marker='final class ApplicationInstanceLease {'
assert text.count(marker)==1
lease=text[text.index(marker):]
# Current public file ends with this class. Fail if the source shape changes.
assert lease.rstrip().endswith('}') and lease.count('{')==lease.count('}')
header='''// Generated from the public AppEnvironment.swift; never edit the production file here.
import Foundation
import Darwin
private enum AppError: Error { case database(String), filesystem(String) }
private enum L10n { static func string(_ key: String, fallback: String) -> String { fallback } }
'''
(root/'Sources/CrashVisibilityApp/RehearsalLease.generated.swift').write_text(header+lease)
out=root/'build/phase2-20261011';out.mkdir(parents=True,exist_ok=True)
(out/'source-provenance.json').write_text(json.dumps({'source':'OKVideoMac/macOS/OKVideoMac/App/AppEnvironment.swift','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'lease_sha256':hashlib.sha256(lease.encode()).hexdigest(),'changes':'Only imports and test-local error/localization shims; original lease class verbatim'},indent=2))
