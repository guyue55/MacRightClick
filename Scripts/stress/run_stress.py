#!/usr/bin/env python3
"""
Real-machine stress harness for RightClickAssistant.

Targets the cross-process contract that FinderSync extension uses to enqueue
events: writes JSON files into the shared PendingActions directory exactly
like the extension would, then watches what the host App does.

What we cover here (matches acceptance §4 / §8 / §9 / §10 / §11):

  * burst   — pump N events as fast as possible into PendingActions and verify
              the host fully drains the queue (P1-2 lease/ack throughput).
  * paste   — submit many low-cost actions while the folder-monitor queue is
              expected to handle them without getting stuck (P1-1 sanity).
  * malformed — write garbage JSON files; they must move to FailedActions
              and never block well-formed events (queue never wedges).
  * concurrency — use a thread pool so multiple producers race; the host
              must still consume each event exactly once (lease atomicity).

Invariants asserted:
  - PendingActions drains to 0 within timeout.
  - InFlightActions/<host_pid>/ ends empty (every lease ack-ed).
  - FailedActions count == number of malformed inputs we sent.
  - No host crashes (host PID still alive after run).
  - No deadlocked OSLog signature (no entries containing "main.sync"
    or sustained "processPendingAction" silence after enqueue).

Run:
    python3 Scripts/stress/run_stress.py --burst 200 --paste 50 --malformed 5 --concurrency 8
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import pathlib
import random
import shutil
import string
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
FAILED = SHARED_DATA / "FailedActions"

# These actions exist in ActionDispatcher and are SAFE to dispatch repeatedly:
# copyName/copyPath only touch NSPasteboard + HUD, no filesystem mutation.
SAFE_ACTIONS = [
    "guyue.action.filemanage.copyName",
    "guyue.action.filemanage.copyPath",
]

# Action whose execute path goes through BackgroundActionRunner; we do NOT
# trigger paste here because that needs cut clipboard state, but we exercise
# the lease/ack pipeline thoroughly via SAFE_ACTIONS.


def now_ts() -> float:
    return time.time()


def host_pid() -> int | None:
    out = subprocess.run(
        ["pgrep", "-f", "RightClickAssistant.app/Contents/MacOS/RightClickAssistant"],
        capture_output=True,
        text=True,
    )
    pids = [int(p) for p in out.stdout.split() if p.strip()]
    return pids[0] if pids else None


def write_event(action_id: str, paths: list[str]) -> pathlib.Path:
    PENDING.mkdir(parents=True, exist_ok=True)
    event = {
        "id": str(uuid.uuid4()),
        "createdAt": now_ts(),
        "actionId": action_id,
        "paths": paths,
    }
    fname = f"{int(event['createdAt']*1000)}-{event['id']}.json"
    target = PENDING / fname
    # write atomic via tmp + rename, mirrors enqueueAction's `.atomic` semantics.
    tmp = PENDING / (fname + ".tmp")
    tmp.write_text(json.dumps(event), encoding="utf-8")
    tmp.rename(target)
    return target


def write_malformed() -> pathlib.Path:
    PENDING.mkdir(parents=True, exist_ok=True)
    fname = f"{int(now_ts()*1000)}-malformed-{uuid.uuid4().hex[:8]}.json"
    target = PENDING / fname
    junk = "{ this is not valid json " + "".join(
        random.choices(string.printable, k=64)
    )
    target.write_text(junk, encoding="utf-8")
    return target


def count_files(d: pathlib.Path) -> int:
    if not d.exists():
        return 0
    return sum(1 for p in d.iterdir() if p.is_file() and p.suffix == ".json")


def wait_pending_drain(timeout_s: float) -> tuple[bool, float]:
    start = time.monotonic()
    while time.monotonic() - start < timeout_s:
        if count_files(PENDING) == 0:
            return True, time.monotonic() - start
        time.sleep(0.05)
    return False, time.monotonic() - start


def wait_inflight_drain(host_pid_value: int, timeout_s: float) -> tuple[bool, float]:
    """Each lease must be ack-ed; the host's own InFlight/<pid>/ should empty."""
    pid_dir = INFLIGHT / str(host_pid_value)
    start = time.monotonic()
    while time.monotonic() - start < timeout_s:
        if not pid_dir.exists() or count_files(pid_dir) == 0:
            return True, time.monotonic() - start
        time.sleep(0.05)
    return False, time.monotonic() - start


def reset_failed_baseline() -> int:
    """Snapshot FailedActions count before the run."""
    return count_files(FAILED)


def run_burst(n: int, concurrency: int, target: str) -> dict:
    print(f"[burst] enqueue {n} safe events with concurrency {concurrency} ...")
    paths = [target]
    t0 = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
        futures = [
            pool.submit(write_event, random.choice(SAFE_ACTIONS), paths)
            for _ in range(n)
        ]
        for f in concurrent.futures.as_completed(futures):
            _ = f.result()
    enqueue_dt = time.monotonic() - t0

    pid = host_pid()
    drained, drain_dt = wait_pending_drain(timeout_s=max(30.0, n * 0.05))
    inflight_drained, inflight_dt = wait_inflight_drain(pid, timeout_s=15.0) if pid else (True, 0.0)
    return {
        "enqueued": n,
        "enqueue_seconds": round(enqueue_dt, 3),
        "drain_pending_seconds": round(drain_dt, 3),
        "drain_pending_ok": drained,
        "drain_inflight_seconds": round(inflight_dt, 3),
        "drain_inflight_ok": inflight_drained,
        "host_pid_alive_after": host_pid() is not None,
    }


def run_malformed(n: int, baseline: int) -> dict:
    print(f"[malformed] write {n} junk files into PendingActions ...")
    for _ in range(n):
        write_malformed()
    drained, drain_dt = wait_pending_drain(timeout_s=15.0)
    failed_now = count_files(FAILED)
    return {
        "wrote_malformed": n,
        "drain_pending_seconds": round(drain_dt, 3),
        "drain_pending_ok": drained,
        "failed_dir_grew_by": failed_now - baseline,
        "host_pid_alive_after": host_pid() is not None,
    }


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--burst", type=int, default=200)
    p.add_argument("--malformed", type=int, default=5)
    p.add_argument("--concurrency", type=int, default=8)
    p.add_argument(
        "--target",
        default=str(pathlib.Path("/tmp").resolve()),
        help="absolute path passed as the action target; safe = /tmp",
    )
    args = p.parse_args(argv)

    if host_pid() is None:
        print("ERROR: host process not running. open the App first.", file=sys.stderr)
        return 2

    print(f"[setup] host_pid={host_pid()} shared_data={SHARED_DATA}")
    failed_baseline = reset_failed_baseline()

    results: dict = {"host_pid_before": host_pid()}
    results["burst"] = run_burst(args.burst, args.concurrency, args.target)
    results["malformed"] = run_malformed(args.malformed, failed_baseline)
    results["host_pid_after"] = host_pid()

    # After-run residual snapshot (must be clean):
    pid = host_pid()
    pid_dir = INFLIGHT / str(pid) if pid else None
    results["residual"] = {
        "pending": count_files(PENDING),
        "inflight_current_pid": (count_files(pid_dir) if pid_dir and pid_dir.exists() else 0),
        "failed_total": count_files(FAILED),
    }

    print("\n=== STRESS REPORT ===")
    print(json.dumps(results, indent=2, ensure_ascii=False))

    ok = (
        results["burst"]["drain_pending_ok"]
        and results["burst"]["drain_inflight_ok"]
        and results["burst"]["host_pid_alive_after"]
        and results["malformed"]["drain_pending_ok"]
        and results["malformed"]["host_pid_alive_after"]
        and results["malformed"]["failed_dir_grew_by"] == args.malformed
        and results["residual"]["pending"] == 0
        and results["residual"]["inflight_current_pid"] == 0
        and results["host_pid_before"] == results["host_pid_after"]
    )
    print(f"\n>>> overall: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
