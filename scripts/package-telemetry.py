"""Validate the three Apple app registrations and package the selected routes."""
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlparse


def package(root, output, variant):
    prod_bundle = "dev.deweyou.dewshot"
    projects = {}
    app_ids = set()
    endpoints = {}
    for channel in ("development", "testflight", "production"):
        config = root / f"GoogleService-{channel}.plist"
        with config.open("rb") as f:
            options = plistlib.load(f)
        expected = prod_bundle + ".dev" if channel == "development" else prod_bundle
        expected_project = "dewshot-58af1" if channel == "production" else "dewshot-dev"
        if options["BUNDLE_ID"] != expected or options["PROJECT_ID"] != expected_project:
            raise ValueError(f"Invalid Analytics registration for {channel}")
        app_ids.add(options["GOOGLE_APP_ID"])
        projects[channel] = options["PROJECT_ID"]
    if len(app_ids) != 3 or projects["development"] != projects["testflight"] or projects["production"] == projects["development"]:
        raise ValueError("Expected separate development and production Firebase projects and three app IDs")
    for env in ("development", "production"):
        endpoint = urlparse((root / f"sentry-{env}.txt").read_text().strip())
        if endpoint.scheme != "https" or not endpoint.hostname or not endpoint.username or not endpoint.path.strip("/").isdigit():
            raise ValueError(f"Invalid Sentry DSN for {env}")
        expected_id = "4512484791615488" if env == "production" else "4512484812324864"
        if endpoint.path != f"/{expected_id}":
            raise ValueError(f"Wrong DewShot Sentry project for {env}")
        endpoints[env] = (endpoint.hostname, endpoint.path)
    if endpoints["development"] == endpoints["production"]:
        raise ValueError("Development and production must use distinct Sentry projects")
    for channel in (("development",) if variant == "development" else ("testflight", "production")):
        env = "development" if channel == "testflight" else channel
        name = f"GoogleService-{channel}.plist"
        # Copy the file contents without importing browser quarantine attributes.
        (output / name).write_bytes((root / name).read_bytes())
        (output / f"sentry-{channel}.txt").write_bytes((root / f"sentry-{env}.txt").read_bytes())


if __name__ == "__main__":
    package(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
