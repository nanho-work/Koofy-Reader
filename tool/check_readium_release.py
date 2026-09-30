#!/usr/bin/env python3
"""Fail a release whose Readium service identities were merged or renamed by R8.

Usage: python3 tool/check_readium_release.py <release.aab | mapping.txt>
Checks the mapping embedded in an AAB; for APK builds pass its matching mapping.
"""
import re
import sys
import zipfile
from pathlib import Path

CONTRACTS = [
    "CacheService", "ContentProtectionService", "CoverService", "LocatorService",
    "PositionsService", "content.ContentService", "search.SearchService",
]


def check(path):
    if path.suffix == ".aab":
        with zipfile.ZipFile(path) as archive:
            mapping = archive.read("BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map").decode()
    else:
        mapping = path.read_text()
    names = dict(re.findall(r"^([^ #\s][^\s]*) -> ([^\s]+):$", mapping, re.MULTILINE))
    failures = []
    for contract in CONTRACTS:
        original = "org.readium.r2.shared.publication.services." + contract
        actual = names.get(original)
        if actual != original:
            failures.append(f"{contract}: {actual or 'missing/merged'}")
    if failures:
        print("FAIL: Readium service identities are unsafe for simpleName keys:")
        print("\n".join(failures))
        return 1
    print("PASS: all 7 Readium service identities preserved; no service-key collisions.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    raise SystemExit(check(Path(sys.argv[1])))
