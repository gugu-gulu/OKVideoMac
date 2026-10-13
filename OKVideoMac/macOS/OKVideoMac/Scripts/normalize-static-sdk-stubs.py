#!/usr/bin/env python3
"""Normalize Xcode's resource-only static SDK stubs, retaining privacy manifests."""
from pathlib import Path
import argparse,json,re,subprocess


def normalize(app: Path) -> list[dict]:
    main = app / "Contents/MacOS/OKVideoMac"
    loads = subprocess.check_output(["otool", "-L", str(main)], text=True)
    records = []
    for name in ("CrashReporter", "Sentry"):
        framework = app / "Contents/Frameworks" / (name + ".framework")
        binary = framework / "Versions/A" / name
        privacy = framework / "Versions/A/Resources/PrivacyInfo.xcprivacy"
        if not binary.is_file() or not privacy.is_file():
            raise SystemExit("Missing static SDK resource container: " + name)
        if name + ".framework/" in loads:
            raise SystemExit("SDK unexpectedly dynamically linked: " + name)
        symbols = subprocess.check_output(["nm", "-gU", str(binary)], text=True).strip()
        sections = subprocess.check_output(["size", "-m", str(binary)], text=True)
        text_sizes = re.findall(r"Section __text: (\d+)", sections)
        dependencies = subprocess.check_output(["otool", "-L", str(binary)], text=True)
        external = [line.split()[0] for line in dependencies.splitlines()[2:] if line.strip()]
        if symbols or not text_sizes or any(int(x) for x in text_sizes) or external != ["/usr/lib/libSystem.B.dylib"]:
            raise SystemExit("Static SDK stub contains unexpected executable code/dependencies: " + name)
        before = privacy.read_bytes()
        identity = "@rpath/" + name + ".framework/Versions/A/" + name
        subprocess.run(["install_name_tool", "-id", identity, str(binary)], check=True)
        after = subprocess.check_output(["otool", "-D", str(binary)], text=True)
        if identity not in after or privacy.read_bytes() != before:
            raise SystemExit("Static SDK stub normalization failed: " + name)
        records.append({"name": name, "install_name": identity, "code_bytes": 0, "privacy_unchanged": True})
    return records


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    print(json.dumps(normalize(args.app)))
