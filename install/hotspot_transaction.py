#!/usr/bin/env python3
"""Simulation-only Project NOMAD hotspot transaction manager."""

import argparse
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

BASE = Path("/tmp/nomad-hotspot-tests")
SCRIPT_DIR = Path(__file__).resolve().parent
PREVIEW = SCRIPT_DIR / "hotspot-preview"

FILES = [
    ("20-nomad-wlan0.network", "/etc/systemd/network/20-nomad-wlan0.network", 0o644),
    ("hostapd.conf", "/etc/hostapd/hostapd.conf", 0o600),
    ("nomad-hotspot.conf", "/etc/dnsmasq.d/nomad-hotspot.conf", 0o644),
    ("project-nomad.nginx", "/etc/nginx/sites-available/project-nomad", 0o644),
    ("nomad-wifi-isolation.sh", "/usr/local/sbin/nomad-wifi-isolation.sh", 0o700),
    ("nomad-wifi-isolation-remove.sh", "/usr/local/sbin/nomad-wifi-isolation-remove.sh", 0o700),
    ("nomad-wifi-isolation.service", "/etc/systemd/system/nomad-wifi-isolation.service", 0o644),
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def save_journal(path, entries):
    temp = path.with_name(path.name + ".tmp")
    with open(temp, "x", encoding="utf-8") as stream:
        json.dump(entries, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, path)


def validate_root(root):
    base = BASE.resolve(strict=True)
    root = root.resolve(strict=True)

    if root.parent != base:
        raise ValueError("Test root must be a direct child of /tmp/nomad-hotspot-tests")

    if not (root / ".nomad-hotspot-test-root").is_file():
        raise ValueError("Missing test-root marker")

    return root


def install(root, journal):
    if journal.exists():
        raise RuntimeError("Transaction already exists; recover first")

    staged = []
    for source, target, mode in FILES:
        data = (PREVIEW / source).read_bytes()
        destination = root / target.lstrip("/")
        if destination.exists() or destination.is_symlink():
            raise RuntimeError(f"Destination exists: {target}")
        staged.append((destination, data, mode, target))

    entries = []
    save_journal(journal, entries)

    for destination, data, mode, target in staged:
        destination.parent.mkdir(parents=True, exist_ok=True)

        fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
        try:
            os.fchmod(fd, mode)
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
        except BaseException:
            try:
                os.close(fd)
            except OSError:
                pass
            raise

        info = destination.stat()
        entries.append({
            "path": target,
            "device": info.st_dev,
            "inode": info.st_ino,
            "sha256": digest(data),
        })
        save_journal(journal, entries)
        print(f"INSTALLED: {target}")

    print("Transaction installed; journal retained.")


def rollback(root, journal):
    if not journal.exists():
        print("No journal found.")
        return

    entries = json.loads(journal.read_text())
    allowed = {target for _, target, _ in FILES}
    remaining = []

    for entry in reversed(entries):
        target = entry["path"]

        if target not in allowed:
            print(f"REFUSED: Unexpected journal path: {target}")
            remaining.append(entry)
            continue

        destination = root / target.lstrip("/")

        try:
            info = destination.lstat()
        except FileNotFoundError:
            continue

        if not stat.S_ISREG(info.st_mode):
            print(f"REFUSED: Not a regular file: {target}")
            remaining.append(entry)
            continue

        if info.st_dev != entry["device"] or info.st_ino != entry["inode"]:
            print(f"REFUSED: File identity changed: {target}")
            remaining.append(entry)
            continue

        if digest(destination.read_bytes()) != entry["sha256"]:
            print(f"REFUSED: File contents changed: {target}")
            remaining.append(entry)
            continue

        destination.unlink()
        print(f"ROLLED BACK: {target}")

    if remaining:
        save_journal(journal, list(reversed(remaining)))
        raise RuntimeError("Rollback incomplete; inspect refused files")

    journal.unlink()
    print("Rollback completed.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "rollback", "status"))
    parser.add_argument("--root", required=True)
    args = parser.parse_args()

    root = validate_root(Path(args.root))
    journal = root / ".nomad-hotspot-transaction.json"

    if args.action == "install":
        install(root, journal)
    elif args.action == "rollback":
        rollback(root, journal)
    else:
        print(journal.read_text() if journal.exists() else "No journal found.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
