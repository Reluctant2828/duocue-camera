import os
import plistlib
import stat
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from package_ipa import package_app


class IPAPackagingTests(unittest.TestCase):
    def test_keeps_payload_root_and_executable_permission(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "DuoCue.app"
            app.mkdir()
            with (app / "Info.plist").open("wb") as stream:
                plistlib.dump({"CFBundleExecutable": "DuoCue", "CFBundleIdentifier": "test.duocue"}, stream)
            executable = app / "DuoCue"
            executable.write_bytes(b"placeholder executable")
            executable.chmod(0o755)
            output = root / "out.ipa"
            package_app(app, output)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.read("Payload/DuoCue.app/DuoCue"), b"placeholder executable")
                self.assertIsNone(archive.testzip())
                if os.name != "nt":
                    self.assertTrue((archive.getinfo("Payload/DuoCue.app/DuoCue").external_attr >> 16) & stat.S_IXUSR)

    def test_rejects_missing_executable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "DuoCue.app"
            app.mkdir()
            with (app / "Info.plist").open("wb") as stream:
                plistlib.dump({"CFBundleExecutable": "DuoCue"}, stream)
            with self.assertRaisesRegex(ValueError, "executable"):
                package_app(app, root / "out.ipa")

    @unittest.skipIf(os.name == "nt", "Creating symlinks requires Windows privileges; covered by macOS CI")
    def test_keeps_framework_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "DuoCue.app"
            app.mkdir()
            with (app / "Info.plist").open("wb") as stream:
                plistlib.dump({"CFBundleExecutable": "DuoCue", "CFBundleIdentifier": "test.duocue"}, stream)
            (app / "DuoCue").write_bytes(b"executable")
            (app / "current").symlink_to("DuoCue")
            output = root / "out.ipa"
            package_app(app, output)
            with zipfile.ZipFile(output) as archive:
                item = archive.getinfo("Payload/DuoCue.app/current")
                self.assertTrue(stat.S_ISLNK(item.external_attr >> 16))
                self.assertEqual(archive.read(item), b"DuoCue")


if __name__ == "__main__":
    unittest.main()
