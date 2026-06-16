#!/usr/bin/env python3
"""
Reclaim stress: simulate "host crashed mid-dispatch" by seeding orphan files
in InFlightActions/<bogus_pid>/, then restart the host and verify every
orphan is reclaimed back to PendingActions and consumed exactly once.

Covers acceptance §10 P1-2 invariant under high orphan count.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time
import uuid


EXT_BUNDLE_ID = "guyue.RightClickAssistant.Extension"
SHARED_DATA = pathlib.Path(
    f"~/Library/Containers/{EXT_BUNDLE_ID}/Data"
).expanduser()

PENDING = SHARED_DATA / "PendingActions"
INFLIGHT = SHARED_DATA / "InFlightActions"
APP_PATH = "/Applications/RightClickAssistant.app"
APP_BIN_FRAGMENT = "RightClickAssistant.app/Contents/MacOS/RightClickAssistant"


def host_pid() -> int | None:
    out = subprocess.run(
        ["pgrep", "-f", APP_BIN_FRAGMENT], capture_output=True, text=True
    )
    pids = [int(p) for p in out.stdout.split() if p.strip()]
    return pids[0] if pids else None


def kill_host():
    subprocess.run(["pkill", "-9", "-f", APP_BIN_FRAGMENT], check=False)
    subprocess.run(["pkill", "-9", "-f", "RightClickAssistantExtension"], check=False)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and host_pid() is not None:
        time.sleep(0.2)


def open_host():
    subprocess.run(["open", APP_PATH], check=True)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline and host_pid() is None:
        time.sleep(0.2)


def seed_orphans(bogus_pid: int, count: int, target: str) -> list[pathlib.Path]:
    pid_dir = INFLIGHT / str(bogus_pid)
    pid_dir.mkdir(parents=True, exist_ok=True)
    paths: list[pathlib.Path] = []
    for _ in range(count):
        ts_ms = int(time.time() * 1000)
        eid = str(uuid.uuid4())
        event = {
            "id": eid,
            "createdAt": time.time(),
            "actionId": "guyue.action.filemanage.copyName",
            "paths": [target],
        }
        f = pid_dir / f"{ts_ms}-{eid}.json"
        f.write_text(json.dumps(event), encoding="utf-8")
        paths.append(f)
    return paths


def count_files(d: pathlib.Path) -> int:
    if not d.exists():
        return 0
    return sum(1 for p in d.iterdir() if p.is_file() and p.suffix == ".json")


def wait_until(predicate, timeout_s: float, poll: float = 0.1) -> tuple[bool, float]:
    start = time.monotonic()
    while time.monotonic() - start < timeout_s:
        if predicate():
            return True, time.monotonic() - start
        time.sleep(poll)
    return False, time.monotonic() - start


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--orphans", type=int, default=50)
    p.add_argument("--bogus-pid", type=int, default=99999)
    p.add_argument("--target", default="/tmp")
    args = p.parse_args(argv)

    print(f"[setup] kill host (if alive) ...")
    kill_host()
    if host_pid() is not None:
        print("ERROR: host did not die within timeout", file=sys.stderr)
        return 2

    bogus_dir = INFLIGHT / str(args.bogus_pid)
    if bogus_dir.exists():
        shutil.rmtree(bogus_dir)

    print(f"[seed] writing {args.orphans} orphan events into {bogus_dir} ...")
    seeded = seed_orphans(args.bogus_pid, args.orphans, args.target)
    assert count_files(bogus_dir) == args.orphans

    print(f"[start] open {APP_PATH}")
    open_host()
    pid = host_pid()
    if pid is None:
        print("ERROR: host did not come up", file=sys.stderr)
        return 3
    print(f"[start] host_pid={pid}")

    # 1. bogus_pid dir must be cleaned by reclaim.
    cleaned, dt_clean = wait_until(lambda: not bogus_dir.exists(), 20.0)
    # 2. Pending must drain (reclaim moved them in, processPendingAction consumed them).
    drained, dt_drain = wait_until(lambda: count_files(PENDING) == 0, 20.0)
    # 3. Current host's InFlight subdir must end empty.
    pid_dir = INFLIGHT / str(pid)
    inflight_clean, dt_inf = wait_until(
        lambda: not pid_dir.exists() or count_files(pid_dir) == 0, 20.0
    )

    report = {
        "orphans_seeded": args.orphans,
        "host_pid_after_restart": pid,
        "bogus_dir_cleaned": cleaned,
        "bogus_dir_clean_seconds": round(dt_clean, 3),
        "pending_drained": drained,
        "pending_drain_seconds": round(dt_drain, 3),
        "inflight_current_pid_clean": inflight_clean,
        "inflight_current_pid_clean_seconds": round(dt_inf, 3),
    }
    print("\n=== RECLAIM STRESS REPORT ===")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    ok = cleaned and drained and inflight_clean
    print(f"\n>>> overall: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
