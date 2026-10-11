#!/usr/bin/env python3
"""Replay the original Chromium commits from the bundled patch series."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def main():
    patch_dir = Path(__file__).resolve().parents[1] / "patches/chromium"
    series = json.loads((patch_dir / "series.json").read_text())
    commits = series["commits"]
    heads = [series["base"], *(entry["commit"] for entry in commits)]
    head = git("rev-parse", "HEAD")
    if head not in heads:
        sys.exit("Chromium HEAD is outside the pinned base and patch series")
    if git("status", "--porcelain", "--untracked-files=no", "--ignore-submodules=all"):
        sys.exit(
            "Chromium has tracked changes; preserve them before applying the series"
        )

    for entry in commits:
        patch = patch_dir / entry["patch"]
        if hashlib.sha256(patch.read_bytes()).hexdigest() != entry["sha256"]:
            sys.exit(f"Patch checksum mismatch: {patch.name}")

    for entry in commits[heads.index(head) :]:
        env = os.environ.copy()
        env.update(
            GIT_COMMITTER_NAME=entry["committer_name"],
            GIT_COMMITTER_EMAIL=entry["committer_email"],
            GIT_COMMITTER_DATE=entry["committer_date"],
        )
        subprocess.run(
            [
                "git",
                "-c",
                "commit.gpgsign=false",
                "am",
                "--3way",
                str(patch_dir / entry["patch"]),
            ],
            env=env,
            check=True,
        )
        if git("rev-parse", "HEAD") != entry["commit"]:
            sys.exit(f"Replayed commit differs from its original: {entry['commit']}")
    print(f"Original Chromium series restored: {git('rev-parse', 'HEAD')}")


if __name__ == "__main__":
    main()
