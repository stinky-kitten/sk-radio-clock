#!/usr/bin/env python3
"""Compare the shared consumer pin, public SwiftPM snapshot and retained ZIP."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--distribution", type=Path, required=True)
parser.add_argument("--archive", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
pin = json.loads((root / "Dependencies/SKLSHUB75.json").read_text())
release = json.loads((args.distribution / "release.json").read_text())
for key in ["version", "abi_version", "asset_url", "asset_sha256", "manifest_sha256", "component_sha256"]:
    if pin[key] != release[key]:
        raise SystemExit("Consumer/distribution mismatch: " + key)
resolved = json.loads((root / "Package.resolved").read_text())
hub75 = next(p for p in resolved["pins"] if p["identity"] == "skls-hub75-dist")
if hub75["state"]["version"] != pin["version"]:
    raise SystemExit("SwiftPM lockfile/version mismatch")
if release["tag"] != "v" + pin["version"]:
    raise SystemExit("Tag/version mismatch")
if hashlib.sha256(args.archive.read_bytes()).hexdigest() != pin["asset_sha256"]:
    raise SystemExit("Release ZIP checksum mismatch")
with zipfile.ZipFile(args.archive) as archive:
    prefix = "skls-hub75-" + pin["version"] + "-rp2350-arm-s/"
    if hashlib.sha256(archive.read(prefix + "manifest.json")).hexdigest() != pin["manifest_sha256"]:
        raise SystemExit("Release manifest checksum mismatch")
    for name, expected in pin["component_sha256"].items():
        data = archive.read(prefix + name)
        if hashlib.sha256(data).hexdigest() != expected:
            raise SystemExit("Release component mismatch: " + name)
        if name.startswith("include/") and (args.distribution / name).read_bytes() != data:
            raise SystemExit("SwiftPM snapshot mismatch: " + name)
print("Shared CMake/SwiftPM version, ZIP pin and authentic public interface hashes agree")
