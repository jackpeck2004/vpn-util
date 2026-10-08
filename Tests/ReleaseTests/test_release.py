"""Offline release tests: fake GitHub CLI, synthetic assets, no publishing."""
import hashlib
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
TAG = "v0.1.0"
ARCHIVE = f"VPN-Utility-{TAG}-universal.zip"
CHECKSUMS = f"SHA256SUMS-{TAG}.txt"


class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for directory in ["scripts", "Resources", "dist", "bin"]:
            (self.root / directory).mkdir()
        for name in ["check-release-tag.sh", "publish-release.sh"]:
            shutil.copy2(ROOT / "scripts" / name, self.root / "scripts" / name)
        (self.root / "Resources" / "Info.plist").write_bytes(
            plistlib.dumps({"CFBundleShortVersionString": "0.1.0"}))
        payload = b"synthetic archive; never uploaded"
        (self.root / "dist" / ARCHIVE).write_bytes(payload)
        (self.root / "dist" / CHECKSUMS).write_text(f"{hashlib.sha256(payload).hexdigest()}  {ARCHIVE}\n")
        (self.root / "dist" / f"release-notes-{TAG}.md").write_text("Synthetic preview notes\n")
        self.log = self.root / "commands.log"
        mock = self.root / "bin" / "gh"
        mock.write_text('''#!/bin/bash
set -eu
printf '%s\\n' "$*" >> "$MOCK_LOG"
case "$2" in
  view)
    if [[ "$*" == *"--json assets"* ]]; then
      printf '%s\\n' "VPN-Utility-v0.1.0-universal.zip"
      if [ "$MOCK_SCENARIO" != "missing" ]; then printf '%s\\n' "SHA256SUMS-v0.1.0.txt"; fi
    elif [ "$MOCK_SCENARIO" = "new" ] && [ ! -f "$MOCK_CREATED" ]; then
      exit 1
    elif [ "$MOCK_SCENARIO" = "published" ] || [ "$MOCK_SCENARIO" = "missing" ]; then
      printf 'false\\n'
    else
      printf 'true\\n'
    fi
    ;;
  create) touch "$MOCK_CREATED" ;;
  upload) [ "$MOCK_SCENARIO" != "upload-fails" ] ;;
  edit) exit 0 ;;
  *) exit 2 ;;
esac
''')
        mock.chmod(0o755)
        self.environment = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
                                GH_TOKEN="test-only", GITHUB_REPOSITORY="example/vpn-utility",
                                MOCK_LOG=str(self.log), MOCK_CREATED=str(self.root / "created"))

    def publish(self, scenario):
        environment = dict(self.environment, MOCK_SCENARIO=scenario)
        result = subprocess.run(["bash", str(self.root / "scripts" / "publish-release.sh"), TAG],
                                env=environment, capture_output=True, text=True, timeout=10)
        commands = self.log.read_text().splitlines() if self.log.exists() else []
        return result, commands

    def test_tag_validation(self):
        for tag, valid in [(TAG, True), (TAG + "-rc.1", True), ("v9.9.9", False),
                           ("../escape", False), ("v00.1.0", False), (TAG + "; echo nope", False)]:
            with self.subTest(tag=tag):
                result = subprocess.run(["bash", str(self.root / "scripts" / "check-release-tag.sh"), tag],
                                        capture_output=True, timeout=5)
                self.assertEqual(result.returncode == 0, valid)

    def test_new_release_publishes_only_after_upload(self):
        result, commands = self.publish("new")
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(i for i, command in enumerate(commands) if command.startswith("release create"))
        upload = next(i for i, command in enumerate(commands) if command.startswith("release upload"))
        publish = next(i for i, command in enumerate(commands) if command.startswith("release edit"))
        self.assertLess(create, upload)
        self.assertLess(upload, publish)
        self.assertIn("--draft", commands[create])
        self.assertIn("--verify-tag", commands[create])
        self.assertIn("--prerelease", commands[publish])
        self.assertIn("--draft=false", commands[publish])
        self.assertIn("--latest=false", commands[publish])

    def test_existing_draft_resumes(self):
        result, commands = self.publish("draft")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(command.startswith("release create") for command in commands))
        self.assertTrue(any(command.startswith("release edit") for command in commands))

    def test_published_release_is_not_overwritten(self):
        result, commands = self.publish("published")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(command.startswith("release view") for command in commands))

    def test_failed_upload_leaves_draft(self):
        result, commands = self.publish("upload-fails")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(command.startswith("release edit") for command in commands))

    def test_incomplete_published_release_fails_without_changes(self):
        result, commands = self.publish("missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(all(command.startswith("release view") for command in commands))

    def test_corrupt_archive_is_rejected_before_network(self):
        (self.root / "dist" / ARCHIVE).write_bytes(b"corrupt")
        result, commands = self.publish("new")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(commands, [])


if __name__ == "__main__":
    unittest.main()
