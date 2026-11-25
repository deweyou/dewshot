#!/usr/bin/env python3
"""DewShot Store candidate preparation, verification, and publication records."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = Path("Sources/FrameCore/FrameVersion.swift")
SEMVER = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
APP_ID = "6838558686"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def git(*args):
    return run("git", *args)


def asc(*args):
    env = os.environ.copy()
    if env.get("ASC_JWT"):
        env.setdefault("ASC_BEARER_TOKEN", env["ASC_JWT"])
    try:
        return subprocess.check_output(["asc", *args], text=True, env=env).strip()
    except FileNotFoundError:
        raise ValueError("Install App Store Connect CLI: brew install asc") from None


def read_version(text):
    version = re.search(r'static let shortVersion = "(' + SEMVER + r')"', text)
    build = re.search(r'static let build = "([1-9][0-9]*)"', text)
    require(version and build, "Invalid FrameVersion.swift")
    return version[1], int(build[1])


def candidate_branch(version):
    require(re.fullmatch(SEMVER, version), "Expected numeric X.Y.Z")
    major, minor, patch = version.split(".")
    return f"release/{major}.{minor}" if patch == "0" else f"patch/{version}"


def clean_branch(version):
    branch = candidate_branch(version)
    require(git("branch", "--show-current") == branch, f"Expected branch {branch}")
    require(not git("status", "--porcelain"), "Commit candidate changes first")
    git("fetch", "--tags", "origin")
    for lang in ("en", "zh-Hans"):
        note = Path("release-notes", version, lang + ".md")
        require(git("show", f"HEAD:{note}").strip(), f"Empty release notes: {note}")
    return branch


def remote_tag(name):
    ref = "refs/tags/" + name
    rows = git("ls-remote", "--refs", "origin", ref)
    if not rows:
        return None
    require(rows.split()[0] == git("rev-parse", ref), f"Local/remote tag mismatch: {name}")
    return git("rev-parse", ref + "^{commit}")


def review(base=None):
    git("fetch", "--tags", "origin")
    head = git("rev-parse", "origin/main")
    tags = [tag for tag in git("tag", "--merged", head, "--list", "v*").splitlines()
            if re.fullmatch("v" + SEMVER, tag)]
    tags.sort(key=lambda tag: tuple(map(int, tag[1:].split("."))), reverse=True)
    published = []
    for tag in tags:
        sha = git("rev-parse", tag + "^{commit}")
        if git("tag", "--points-at", sha, "--list", "store-package/*"):
            published.append(tag)
    if base:
        require(base in tags, "Choose a version tag reachable from origin/main")
    else:
        base = next(iter(published or tags), None)
    if not base:
        raise ValueError("No version tag; review the complete history of origin/main for the first release")
    major, minor, _ = map(int, base[1:].split("."))
    history = f"{base}..{head}"
    print(f"Baseline: {base} ({'Store' if base in published else 'historical Git tag'})")
    print(f"Candidate: {head}\nMajor: {major + 1}.0.0\nMinor: {major}.{minor + 1}.0")
    print(git("log", "--oneline", history))
    print(git("diff", "--stat", history))


def reserve(version, replacement=False):
    branch = clean_branch(version)
    old = VERSION_FILE.read_text()
    old_version, current = read_version(old)
    if not replacement and old_version == version and remote_tag(f"store-build/{current}") == git("rev-parse", "HEAD"):
        print(f"Already reserved {version} ({current}) at HEAD")
        return
    require(not git("tag", "--list", "v" + version), f"Version {version} already tagged")
    main_build = read_version(git("show", f"origin/main:{VERSION_FILE}"))[1]
    numbers = [current, main_build]
    for ref in git("ls-remote", "--tags", "--refs", "origin", "refs/tags/store-build/*").splitlines():
        numbers.append(int(ref.rsplit("/", 1)[1]))
    build = max(numbers) + 1
    new = re.sub(r'static let shortVersion = "[^"]+"', f'static let shortVersion = "{version}"', old)
    new = re.sub(r'static let build = "[0-9]+"', f'static let build = "{build}"', new)
    VERSION_FILE.write_text(new)
    git("commit", "-m", f"Prepare DewShot {version} ({build})", "--", str(VERSION_FILE))
    # The tag and branch advance together; a competing candidate cannot claim the same number.
    git("push", "--atomic", "origin", f"HEAD:refs/heads/{branch}", f"HEAD:refs/tags/store-build/{build}")
    print(f"{version} ({build}) {git('rev-parse', 'HEAD')}")


def preflight():
    version, build = read_version(VERSION_FILE.read_text())
    branch = clean_branch(version)
    sha = git("rev-parse", "HEAD")
    require(git("rev-parse", "origin/" + branch) == sha, "Push the candidate before packaging")
    require(remote_tag(f"store-build/{build}") == sha, "Build reservation does not match HEAD")
    require(not remote_tag(f"store-package/{build}"), "Build already packaged; reuse its recorded artifact")
    runs = json.loads(run("gh", "run", "list", "--workflow", "ci.yml", "--branch", branch,
                          "--event", "push", "--commit", sha, "--limit", "1",
                          "--json", "conclusion,headSha"))
    require(runs and runs[0] == {"conclusion": "success", "headSha": sha}, "Candidate push CI must pass")
    return sha


def record(package, sha):
    version, build = read_version(VERSION_FILE.read_text())
    require(package.name == f"dewShot-{version}-build.{build}-AppStore.pkg", "Unexpected package name")
    require(git("rev-parse", "HEAD") == sha and not git("status", "--porcelain"),
            "Source changed while packaging")
    require(remote_tag(f"store-build/{build}") == sha, "Build reservation mismatch")
    receipt = dict(version=version, build=build, commit=sha, sha256=package_digest(package))
    tag = f"store-package/{build}"
    existing = git("tag", "--list", tag)
    if existing:
        require(git("rev-parse", tag + "^{commit}") == sha and read_receipt(tag) == receipt,
                "Package differs from its existing receipt")
    else:
        git("tag", "-a", tag, sha, "-m", json.dumps(receipt, sort_keys=True))
    git("push", "origin", "refs/tags/" + tag)
    print(json.dumps(receipt))


def package_digest(package):
    digest = hashlib.sha256()
    with package.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_receipt(tag):
    return json.loads(git("for-each-ref", "--format=%(contents)", "refs/tags/" + tag))


def upload_package(package):
    name = re.fullmatch(r"dewShot-(" + SEMVER + r")-build\.([1-9][0-9]*)-AppStore\.pkg", package.name)
    require(name, "Expected a registered DewShot App Store package")
    version, build = name.groups()
    git("fetch", "--tags", "origin")
    tag = f"store-package/{build}"
    sha = remote_tag(tag)
    require(sha and remote_tag(f"store-build/{build}") == sha, "Missing or inconsistent candidate records")
    require(read_receipt(tag) == dict(version=version, build=int(build), commit=sha,
                                      sha256=package_digest(package)), "Package differs from its registered receipt")
    target = ("--app", APP_ID, "--platform", "MAC_OS", "--output", "json")
    builds = json.loads(asc("builds", "list", *target, "--version", version, "--build-number", build))
    if builds["data"]:
        print(f"{version} ({build}) already exists in App Store Connect; check build status")
        return
    uploads = json.loads(asc("builds", "uploads", "list", *target,
                             "--cf-bundle-short-version", version, "--cf-bundle-version", build))
    require(not uploads["data"], f"Apple already has an upload for {version} ({build}); inspect it before retrying")
    print(asc("builds", "upload", *target, "--pkg", str(package), "--version", version,
              "--build-number", build))


def prepare_metadata(version, directory):
    require(re.fullmatch(SEMVER, version), "Expected numeric X.Y.Z")
    for locale, language in (("en-US", "en"), ("zh-Hans", "zh-Hans")):
        source = Path("store-listing", locale)
        fields = json.loads((source / "metadata.json").read_text())
        listing = fields["version"]
        listing["description"] = (source / "description.txt").read_text().strip()
        if version != "1.0.0":
            listing["whatsNew"] = Path("release-notes", version, language + ".md").read_text().strip()
        for folder, values in ((directory / "app-info", fields["appInfo"]),
                               (directory / "version" / version, listing)):
            folder.mkdir(parents=True, exist_ok=True)
            (folder / (locale + ".json")).write_text(json.dumps(values, ensure_ascii=False, indent=2) + "\n")


def sync_metadata(version, apply=False):
    with tempfile.TemporaryDirectory(prefix="dewshot-store-metadata-") as directory:
        prepare_metadata(version, Path(directory))
        print(asc("metadata", "apply", "--app", APP_ID, "--platform", "MAC_OS", "--version", version,
                  "--dir", directory, "--confirm" if apply else "--dry-run"))


def apple_status(version):
    require(re.fullmatch(SEMVER, version), "Expected numeric X.Y.Z")
    payload = json.loads(asc("versions", "view", "--app", APP_ID, "--platform", "MAC_OS", "--version", version,
                             "--include-build", "--output", "json"))
    entry = payload["data"]
    attrs = entry["attributes"]
    require(attrs["versionString"] == version and attrs["platform"] == "MAC_OS", "Unexpected Apple version")
    linked = entry["relationships"]["build"]["data"]
    build = next((item["attributes"]["version"] for item in payload.get("included", [])
                  if linked and item["type"] == "builds" and item["id"] == linked["id"]), None)
    return attrs["appVersionState"], build


def finalize(version, state, build):
    require(state == "READY_FOR_DISTRIBUTION", f"Apple state is {state}; keep the branch open")
    require(build and re.fullmatch(r"[1-9][0-9]*", build), "Apple version has no confirmed build")
    git("fetch", "--tags", "origin")
    tag = f"store-package/{build}"
    sha = remote_tag(tag)
    require(sha and remote_tag(f"store-build/{build}") == sha, "Missing or inconsistent candidate records")
    receipt = read_receipt(tag)
    require(receipt["version"] == version and receipt["build"] == int(build) and receipt["commit"] == sha
            and re.fullmatch(r"[0-9a-f]{64}", receipt["sha256"]), "Receipt does not match Apple build")
    require(read_version(git("show", f"{sha}:{VERSION_FILE}")) == (version, int(build)), "Version mismatch")
    public = "v" + version
    if git("tag", "--list", public):
        require(git("rev-parse", public + "^{commit}") == sha, f"Conflicting tag {public}")
    else:
        git("tag", "-a", public, sha, "-m", f"DewShot {version} ({build})\n\nSHA256 {receipt['sha256']}")
    git("push", "origin", "refs/tags/" + public)
    print(f"{public} -> {sha}; open the merge-back PR from this commit")


def main():
    os.chdir(ROOT)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("review").add_argument("--base", help="Override the comparison tag")
    for name in ("reserve", "status", "finalize"):
        commands.add_parser(name).add_argument("version")
    commands.choices["reserve"].add_argument("--replacement", action="store_true",
                                              help="Allocate a fresh build for unchanged sources")
    commands.add_parser("preflight")
    receipt = commands.add_parser("record")
    receipt.add_argument("package", type=Path)
    receipt.add_argument("sha")
    commands.add_parser("upload").add_argument("package", type=Path)
    metadata = commands.add_parser("metadata")
    metadata.add_argument("version")
    metadata.add_argument("--apply", action="store_true", help="Write metadata to Apple instead of previewing")
    args = parser.parse_args()
    if args.command == "review":
        review(args.base)
    elif args.command == "reserve":
        reserve(args.version, args.replacement)
    elif args.command == "preflight":
        print(preflight())
    elif args.command == "record":
        record(args.package, args.sha)
    elif args.command == "upload":
        upload_package(args.package)
    elif args.command == "metadata":
        sync_metadata(args.version, args.apply)
    else:
        state, build = apple_status(args.version)
        print(f"macOS {args.version}: {state}, build {build or 'unassigned'}")
        if args.command == "finalize":
            finalize(args.version, state, build)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as exc:
        sys.exit(str(exc))
