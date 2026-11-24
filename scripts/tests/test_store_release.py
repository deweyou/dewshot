import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("release", Path(__file__).resolve().parents[1] / "store-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(self.temp.name)
        subprocess.run(["git", "init", "--bare", "-q", "origin.git"], check=True)
        subprocess.run(["git", "init", "-q", "-b", "main", "work"], check=True)
        os.chdir("work")
        g = release.git
        g("config", "user.email", "test@example.invalid")
        g("config", "user.name", "Test")
        g("config", "commit.gpgsign", "false")
        g("config", "tag.gpgSign", "false")
        release.VERSION_FILE.parent.mkdir(parents=True)
        release.VERSION_FILE.write_text('static let shortVersion = "0.1.2"\nstatic let build = "3"\n')
        for version in ("1.0.0", "1.0.1"):
            for lang in ("en", "zh-Hans"):
                file = Path("release-notes", version, lang + ".md")
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text("Test notes")
        g("add", ".")
        g("commit", "-m", "baseline")
        g("remote", "add", "origin", "../origin.git")
        g("push", "origin", "main")

    def test_candidate_to_published_tag(self):
        g = release.git
        with self.assertRaisesRegex(ValueError, "Expected branch"):
            release.reserve("1.0.0")
        g("switch", "-c", "release/1.0")
        release.reserve("1.0.0")
        sha = g("rev-parse", "HEAD")
        release.reserve("1.0.0")
        self.assertEqual(g("rev-parse", "HEAD"), sha)
        original = release.run
        with patch.object(release, "run") as cmd:
            def pending_ci(*args):
                return "[]" if args[0] == "gh" else original(*args)
            cmd.side_effect = pending_ci
            with self.assertRaisesRegex(ValueError, "CI must pass"):
                release.preflight()
            def passed_ci(*args):
                if args[0] == "gh":
                    return json.dumps([{"conclusion": "success", "headSha": sha}])
                return original(*args)
            cmd.side_effect = passed_ci
            self.assertEqual(release.preflight(), sha)
        pkg = Path("../dewShot-1.0.0-build.4-AppStore.pkg")
        pkg.write_bytes(b"fixture")
        release.record(pkg, sha)
        with self.assertRaisesRegex(ValueError, "keep the branch open"):
            release.finalize("1.0.0", "PENDING_DEVELOPER_RELEASE", "4")
        with self.assertRaisesRegex(ValueError, "records"):
            release.finalize("1.0.0", "READY_FOR_DISTRIBUTION", "7")
        for _ in range(2):
            release.finalize("1.0.0", "READY_FOR_DISTRIBUTION", "4")
        self.assertEqual(release.remote_tag("v1.0.0"), sha)
        g("switch", "-c", "patch/1.0.1", "v1.0.0")
        release.reserve("1.0.1")
        self.assertEqual(release.read_version(release.VERSION_FILE.read_text()), ("1.0.1", 5))
        g("switch", "-c", "release/2.0", "main")
        for lang in ("en", "zh-Hans"):
            note = Path("release-notes/2.0.0", lang + ".md")
            note.parent.mkdir(exist_ok=True)
            note.write_text("Next release")
        g("add", ".")
        g("commit", "-m", "Next notes")
        release.reserve("2.0.0")
        self.assertEqual(release.read_version(release.VERSION_FILE.read_text()), ("2.0.0", 6))

    def test_review_uses_historical_baseline_without_starting_release(self):
        release.git("tag", "v0.1.2")
        release.git("push", "origin", "refs/tags/v0.1.2")
        with patch("sys.stdout", new_callable=io.StringIO) as output:
            release.review()
        self.assertIn("v0.1.2 (historical Git tag)", output.getvalue())
        self.assertIn("Major: 1.0.0\nMinor: 0.2.0", output.getvalue())
        self.assertEqual(release.git("branch", "--show-current"), "main")
        self.assertEqual(release.git("status", "--porcelain"), "")
        self.assertEqual(release.git("tag", "--list", "store-*"), "")

    def test_apple_status_reads_attached_build(self):
        response = {"data": [{"attributes": {"platform": "MAC_OS", "versionString": "1.0.0",
                    "appVersionState": "READY_FOR_DISTRIBUTION"},
                    "relationships": {"build": {"data": {"id": "attached"}}}}],
                    "included": [{"type": "builds", "id": key, "attributes": {"version": number}}
                                 for key, number in [("another", "6"), ("attached", "4")]]}
        with patch.dict(os.environ, ASC_JWT="fixture"), patch.object(release, "urlopen",
                return_value=io.BytesIO(json.dumps(response).encode())):
            self.assertEqual(release.apple_status("1.0.0"), ("READY_FOR_DISTRIBUTION", "4"))


if __name__ == "__main__":
    unittest.main()
