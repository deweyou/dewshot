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
        response = {"data": {"attributes": {"platform": "MAC_OS", "versionString": "1.0.0",
                    "appVersionState": "READY_FOR_DISTRIBUTION"},
                    "relationships": {"build": {"data": {"id": "attached"}}}},
                    "included": [{"type": "builds", "id": key, "attributes": {"version": number}}
                                 for key, number in [("another", "6"), ("attached", "4")]]}
        with patch.object(release, "asc", return_value=json.dumps(response)) as command:
            self.assertEqual(release.apple_status("1.0.0"), ("READY_FOR_DISTRIBUTION", "4"))
        command.assert_called_once_with("versions", "view", "--app", release.APP_ID, "--platform", "MAC_OS",
                                        "--version", "1.0.0", "--include-build", "--output", "json")

    def test_upload_checks_receipt_and_looks_up_existing_upload(self):
        release.git("switch", "-c", "release/1.0")
        release.reserve("1.0.0")
        release.git("fetch", "--tags", "origin")
        pkg = Path("../dewShot-1.0.0-build.4-AppStore.pkg")
        pkg.write_bytes(b"fixture")
        release.record(pkg, release.git("rev-parse", "HEAD"))
        empty = json.dumps({"data": []})
        existing = json.dumps({"data": [{"id": "already-uploaded"}]})
        with patch.object(release, "asc", side_effect=[empty, existing]) as command:
            with self.assertRaisesRegex(ValueError, "already has an upload"):
                release.upload_package(pkg)
        self.assertEqual(command.call_count, 2)
        with patch.object(release, "asc", side_effect=[empty, empty, "{}"]) as command:
            with patch("sys.stdout"):
                release.upload_package(pkg)
        command.assert_called_with("builds", "upload", "--app", release.APP_ID, "--platform", "MAC_OS",
                                   "--output", "json", "--pkg", str(pkg), "--version", "1.0.0", "--build-number", "4")
        pkg.write_bytes(b"modified")
        with patch.object(release, "asc") as command:
            with self.assertRaisesRegex(ValueError, "differs from its registered receipt"):
                release.upload_package(pkg)
        command.assert_not_called()

    def test_metadata_uses_launch_copy_and_only_adds_update_notes_on_updates(self):
        for locale in ("en-US", "zh-Hans"):
            source = Path("store-listing", locale)
            source.mkdir(parents=True)
            (source / "description.txt").write_text(f"Description for {locale}\n")
            (source / "metadata.json").write_text(json.dumps({"appInfo": {"name": "DewShot"}, "version": {}}))
        output = Path("metadata")
        release.prepare_metadata("1.0.0", output)
        release.prepare_metadata("1.0.1", output)
        for locale in ("en-US", "zh-Hans"):
            launch = json.loads((output / "version" / "1.0.0" / f"{locale}.json").read_text())
            update = json.loads((output / "version" / "1.0.1" / f"{locale}.json").read_text())
            self.assertEqual(launch, {"description": f"Description for {locale}"})
            self.assertEqual(update, {**launch, "whatsNew": "Test notes"})


if __name__ == "__main__":
    unittest.main()
