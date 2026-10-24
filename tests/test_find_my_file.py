#!/usr/bin/env python3
# Find my file search rules, run against a throwaway home folder.
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from embedded import extract  # noqa: E402


def load(home):
    """Import the embedded where-is-my-file with HOME pointed at a test folder."""
    src = Path(home) / "where_is_my_file.py"
    src.write_text(extract("where-is-my-file"))
    old = os.environ.get("HOME")
    os.environ["HOME"] = home
    try:
        spec = importlib.util.spec_from_file_location("where_is_my_file", src)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    finally:
        os.environ["HOME"] = old
    return mod


class FindMyFile(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.home = root / "home"
        self.disk = root / "usbdisk"
        for d in ("Documents/taxes", "Downloads", "Pictures", ".cache", "Media/Disks"):
            (self.home / d).mkdir(parents=True)
        self.disk.mkdir()
        (self.home / "Documents/taxes/Tax Report [2025].pdf").touch()
        (self.home / "Downloads/report.txt").touch()
        (self.home / "Pictures/report-photo.jpg").touch()
        (self.home / ".cache/report-cache").touch()
        (self.disk / "report-on-usb.odt").touch()
        (self.home / "Media/Disks/usbdisk").symlink_to(self.disk)
        # A link back up the tree must not loop or list things twice.
        (self.home / "Documents/taxes/loop").symlink_to(self.home / "Documents")
        self.mod = load(str(self.home))

    def tearDown(self):
        self.tmp.cleanup()

    def names(self, query, *scopes):
        return sorted(os.path.basename(p) for p in self.mod.search(query, set(scopes)))

    def test_plain_text_not_glob(self):
        self.assertEqual(self.names("report [2025", "documents"), ["Tax Report [2025].pdf"])
        self.assertEqual(self.names("*", "home"), [])

    def test_case_insensitive(self):
        self.assertIn("report.txt", self.names("REPORT", "downloads"))

    def test_scopes(self):
        self.assertEqual(self.names("report", "documents"), ["Tax Report [2025].pdf"])
        self.assertEqual(self.names("report", "documents", "downloads"),
                         ["Tax Report [2025].pdf", "report.txt"])
        self.assertEqual(self.names("report", "home"),
                         ["Tax Report [2025].pdf", "report-photo.jpg", "report.txt"])

    def test_hidden_skipped(self):
        self.assertNotIn("report-cache", self.names("report", "all"))

    def test_disks_only_under_all(self):
        self.assertNotIn("report-on-usb.odt", self.names("report", "home"))
        self.assertIn("report-on-usb.odt", self.names("report", "all"))

    def test_no_duplicates_through_links(self):
        hits = list(self.mod.search("Tax Report", {"all"}))
        self.assertEqual(len(hits), 1, hits)

    def test_stop(self):
        import threading
        stop = threading.Event()
        stop.set()
        self.assertEqual(list(self.mod.search("report", {"all"}, stop)), [])

    def test_cli(self):
        self.assertEqual(self.mod.cli(["--bogus", "x"]), 1)
        self.assertEqual(self.mod.cli([]), 1)


if __name__ == "__main__":
    unittest.main()
