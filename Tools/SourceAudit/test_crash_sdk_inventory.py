"""Release-gate regressions for omitted or inconsistent static SDK metadata."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from crash_sdk_inventory import REPO, static_sdk_inventory, verify_static_sdk_documents
from generate_sbom import spdx, cyclonedx


class CrashSDKInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "OKVideoMac.app"
        lock = json.loads((REPO / "ThirdParty/crash-diagnostics-lock.json").read_text())
        self.notices = []
        source = REPO / "OKVideoMac/macOS/OKVideoMac/Packages/OKCrashDiagnostics/Sources/OKCrashDiagnostics/Resources"
        for role in ("capture", "upload"):
            notice = self.app / lock[role]["license_resource_path"]
            notice.parent.mkdir(parents=True, exist_ok=True)
            notice.write_bytes((source / notice.name).read_bytes())
            self.notices.append(notice)
        self.items = static_sdk_inventory(self.app)
        self.spdx = spdx("test", "1", self.items, "2026-10-13T00:00:00Z", "sdk-test")
        self.cdx = cyclonedx("test", "1", self.items, "2026-10-13T00:00:00Z", "sdk-test")

    def test_complete_static_inventory_keeps_native_hash_boundary(self):
        verify_static_sdk_documents(self.app, self.spdx, self.cdx)
        self.assertEqual({x["name"] for x in self.items}, {"PLCrashReporter", "Sentry"})
        capture = next(x for x in self.items if x["name"] == "PLCrashReporter")
        self.assertEqual(capture["license"], "MIT AND Apache-2.0")
        self.assertFalse(any("packageFileName" in x or "checksums" in x for x in self.spdx["packages"]))

    def test_missing_shipped_notice_fails(self):
        self.notices[0].unlink()
        with self.assertRaisesRegex(SystemExit, "Missing static SDK license"):
            static_sdk_inventory(self.app)

    def test_changed_notice_fails(self):
        self.notices[1].write_bytes(b"truncated license")
        with self.assertRaisesRegex(SystemExit, "license checksum mismatch"):
            verify_static_sdk_documents(self.app, self.spdx, self.cdx)

    def test_spdx_sdk_omission_fails_even_when_cdx_is_complete(self):
        self.spdx["packages"].pop()
        with self.assertRaisesRegex(SystemExit, "SPDX inventory mismatch"):
            verify_static_sdk_documents(self.app, self.spdx, self.cdx)

    def test_cdx_version_mismatch_fails_even_when_spdx_is_correct(self):
        self.cdx["components"][1]["version"] = "0.0.0"
        with self.assertRaisesRegex(SystemExit, "CycloneDX metadata mismatch"):
            verify_static_sdk_documents(self.app, self.spdx, self.cdx)

    def test_duplicate_sdk_cannot_replace_missing_component(self):
        self.spdx["packages"][1] = copy.deepcopy(self.spdx["packages"][0])
        with self.assertRaisesRegex(SystemExit, "SPDX inventory mismatch"):
            verify_static_sdk_documents(self.app, self.spdx, self.cdx)


if __name__ == "__main__":
    unittest.main()
