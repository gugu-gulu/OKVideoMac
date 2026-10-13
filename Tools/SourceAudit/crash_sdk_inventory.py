"""Logical static SDK inventory, separate from the signed Mach-O inventory."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def static_sdk_inventory(app: Path) -> list[dict[str, str]]:
    lock = json.loads((REPO / "ThirdParty/crash-diagnostics-lock.json").read_text())
    result = []
    for role in ("capture", "upload"):
        sdk = lock[role]
        notice = app / sdk["license_resource_path"]
        if not notice.is_file():
            raise SystemExit(f"Missing static SDK license: {sdk['name']}")
        if hashlib.sha256(notice.read_bytes()).hexdigest() != sdk["license_sha256"]:
            raise SystemExit(f"Static SDK license checksum mismatch: {sdk['name']}")
        repository = sdk["repository"].removeprefix("https://github.com/").removesuffix(".git")
        result.append({
            "name": sdk["name"], "version": sdk["version"], "license": sdk["license"],
            "purl": f"pkg:github/{repository}@{sdk['version']}",
            "source_url": f"https://codeload.github.com/{repository}/tar.gz/{sdk['commit']}",
            "source_info": f"Unmodified upstream {sdk['commit']}; source archive SHA-256 {sdk['source_sha256']}",
            "artifact": "Static SDK linked into Contents/MacOS/OKVideoMac; license: " + sdk["license_resource_path"],
        })
    return result


def verify_static_sdk_documents(app: Path, spdx: dict, cdx: dict) -> None:
    expected = {row["name"]: row for row in static_sdk_inventory(app)}
    logical_spdx = [p for p in spdx["packages"] if not p.get("packageFileName")]
    logical_cdx = [c for c in cdx["components"] if not any(
        p["name"] == "okvideomac:bundle-path" for p in c.get("properties", []))]
    for kind, rows in (("SPDX", logical_spdx), ("CycloneDX", logical_cdx)):
        if len(rows) != len(expected) or {r["name"] for r in rows} != set(expected):
            raise SystemExit(f"Static SDK/{kind} inventory mismatch")
    for package in logical_spdx:
        sdk = expected[package["name"]]
        refs = [r["referenceLocator"] for r in package.get("externalRefs", []) if r["referenceType"] == "purl"]
        if (package["versionInfo"] != sdk["version"] or package["licenseDeclared"] != sdk["license"]
                or package["licenseConcluded"] != sdk["license"] or refs != [sdk["purl"]]
                or package.get("sourceInfo") != sdk["source_info"]
                or package["downloadLocation"] != sdk["source_url"] or package.get("checksums")):
            raise SystemExit(f"Static SDK/SPDX metadata mismatch: {sdk['name']}")
    for component in logical_cdx:
        sdk = expected[component["name"]]
        licenses = ([{"expression": sdk["license"]}] if " AND " in sdk["license"]
                    else [{"license": {"id": sdk["license"]}}])
        props = {p["name"]: p["value"] for p in component.get("properties", [])}
        if (component["version"] != sdk["version"] or component.get("purl") != sdk["purl"]
                or component["licenses"] != licenses or component.get("hashes")
                or props.get("okvideomac:source-info") != sdk["source_info"]
                or props.get("okvideomac:source-url") != sdk["source_url"]):
            raise SystemExit(f"Static SDK/CycloneDX metadata mismatch: {sdk['name']}")
