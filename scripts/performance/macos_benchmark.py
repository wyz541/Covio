#!/usr/bin/env python3
"""Reproducible macOS performance comparison for baseline and candidate apps."""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import pathlib
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

SCHEMA_VERSION = 1
DEFAULT_RUNS = 10
DEFAULT_SETTLE_SECONDS = 30.0
DEFAULT_SAMPLE_SECONDS = 5
DEFAULT_LAUNCH_TIMEOUT_SECONDS = 30.0
COMPARISON_METRICS = (
    "launchMs",
    "rssKb",
    "footprintBytes",
    "cpuPercent",
    "threads",
    "fdCount",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def run_command(
    command: Sequence[str],
    timeout: float = 30.0,
    check: bool = False,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        list(command),
        capture_output=True,
        text=True,
        timeout=timeout,
        check=check,
    )


def command_text(command: Sequence[str], default: str = "") -> str:
    try:
        result = run_command(command)
    except (OSError, subprocess.TimeoutExpired):
        return default
    if result.returncode != 0:
        return default
    return result.stdout.strip()


def sanitize_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-") or "app"


def executable_for(app_path: pathlib.Path) -> pathlib.Path:
    path = app_path.expanduser().resolve()
    if path.is_dir() and path.suffix == ".app":
        path = path / "Contents" / "MacOS" / "Covio"
    if not path.is_file():
        raise ValueError("app executable does not exist: %s" % path)
    if not os.access(path, os.X_OK):
        raise ValueError("app executable is not executable: %s" % path)
    return path


def app_identity(app_path: pathlib.Path) -> Dict[str, Optional[str]]:
    app = app_path.expanduser().resolve()
    if app.is_file() and app.parent.name == "MacOS" and app.parent.parent.parent.suffix == ".app":
        app = app.parent.parent.parent
    info = app / "Contents" / "Info.plist"
    version = None
    build = None
    if info.is_file():
        version = command_text(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", str(info)])
        build = command_text(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleVersion", str(info)])
    manifest = app / "Contents" / "Resources" / "release-manifest.json"
    commit = None
    if manifest.is_file():
        try:
            data = json.loads(manifest.read_text())
            commit = data.get("commit") or data.get("gitCommit")
        except (OSError, ValueError):
            pass
    return {
        "version": version or None,
        "build": build or None,
        "commit": str(commit) if commit else None,
    }


def app_disk_size(path: pathlib.Path) -> Dict[str, int]:
    root = path.expanduser().resolve()
    if root.is_file():
        stat = root.stat()
        return {"logicalBytes": stat.st_size, "allocatedBytes": stat.st_blocks * 512, "files": 1}
    logical = 0
    allocated = 0
    files = 0
    for item in root.rglob("*"):
        if item.is_symlink() or not item.is_file():
            continue
        try:
            stat = item.stat()
        except OSError:
            continue
        logical += stat.st_size
        allocated += stat.st_blocks * 512
        files += 1
    return {"logicalBytes": logical, "allocatedBytes": allocated, "files": files}


def parse_artifact(spec: str) -> Dict[str, Any]:
    if "=" not in spec:
        raise ValueError("artifact must use LABEL=PATH")
    label, raw_path = spec.split("=", 1)
    path = pathlib.Path(raw_path).expanduser().resolve()
    if not path.exists():
        raise ValueError("artifact does not exist: %s" % path)
    stat = path.stat()
    return {"label": label, "path": str(path), "bytes": stat.st_size, "isDirectory": path.is_dir()}


def environment_report(source_root: pathlib.Path) -> Dict[str, Any]:
    xcode = command_text(["xcodebuild", "-version"])
    power = command_text(["pmset", "-g", "batt"])
    thermal = command_text(["pmset", "-g", "therm"])
    top_processes = []
    try:
        result = run_command(["ps", "-axo", "%cpu=,comm="])
        for line in result.stdout.splitlines():
            pieces = line.strip().split(None, 1)
            if len(pieces) != 2:
                continue
            try:
                cpu = float(pieces[0])
            except ValueError:
                continue
            top_processes.append({"cpuPercent": cpu, "command": pieces[1]})
        top_processes = sorted(top_processes, key=lambda item: item["cpuPercent"], reverse=True)[:5]
    except (OSError, subprocess.TimeoutExpired):
        pass
    load1, load5, load15 = os.getloadavg()
    mem_bytes = command_text(["sysctl", "-n", "hw.memsize"])
    return {
        "timestamp": utc_now(),
        "platform": platform.platform(),
        "machine": command_text(["sysctl", "-n", "hw.model"]),
        "architecture": platform.machine(),
        "memoryBytes": int(mem_bytes) if mem_bytes.isdigit() else None,
        "osVersion": command_text(["sw_vers", "-productVersion"]),
        "osBuild": command_text(["sw_vers", "-buildVersion"]),
        "xcode": xcode,
        "power": power,
        "thermal": thermal,
        "loadAverage": [load1, load5, load15],
        "topProcesses": top_processes,
        "sourceCommit": command_text(["git", "-C", str(source_root), "rev-parse", "HEAD"], default=""),
    }


def parse_cpu_time(value: str) -> float:
    pieces = value.strip().split(":")
    if not 1 <= len(pieces) <= 3:
        return 0.0
    try:
        numbers = [float(piece) for piece in pieces]
    except ValueError:
        return 0.0
    seconds = 0.0
    for number in numbers:
        seconds = seconds * 60.0 + number
    return seconds


def parse_ps_rows(text: str) -> Dict[int, Dict[str, Any]]:
    rows: Dict[int, Dict[str, Any]] = {}
    for line in text.splitlines():
        pieces = line.strip().split(None, 5)
        if len(pieces) < 6:
            continue
        try:
            pid = int(pieces[0])
            ppid = int(pieces[1])
            rss = int(pieces[2])
            cpu = float(pieces[3])
        except ValueError:
            continue
        rows[pid] = {
            "pid": pid,
            "ppid": ppid,
            "rssKb": rss,
            "cpuPercent": cpu,
            "cpuSeconds": parse_cpu_time(pieces[4]),
            "command": pieces[5],
        }
    return rows


def process_tree_rows(root_pid: int, rows: Dict[int, Dict[str, Any]]) -> List[Dict[str, Any]]:
    children: Dict[int, List[int]] = {}
    for pid, row in rows.items():
        children.setdefault(int(row["ppid"]), []).append(pid)
    selected: List[Dict[str, Any]] = []
    todo = [root_pid]
    seen = set()
    while todo:
        pid = todo.pop(0)
        if pid in seen or pid not in rows:
            continue
        seen.add(pid)
        selected.append(rows[pid])
        todo.extend(children.get(pid, []))
    return selected


def process_tree_metrics(root_pid: int) -> Dict[str, Any]:
    result = run_command(["ps", "-axo", "pid=,ppid=,rss=,%cpu=,time=,command="], timeout=15)
    rows = parse_ps_rows(result.stdout)
    selected = process_tree_rows(root_pid, rows)
    return {
        "rssKb": sum(int(item["rssKb"]) for item in selected),
        "cpuPercent": sum(float(item["cpuPercent"]) for item in selected),
        "cpuSeconds": sum(float(item["cpuSeconds"]) for item in selected),
        "processCount": len(selected),
        "processes": selected,
    }


def thread_count(processes: Iterable[Dict[str, Any]]) -> int:
    total = 0
    for item in processes:
        try:
            result = run_command(["ps", "-M", "-p", str(item["pid"]), "-o", "pid="], timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            continue
        total += sum(1 for line in result.stdout.splitlines() if re.match(r"^\s*\d+\s", line))
    return total


def fd_count(processes: Iterable[Dict[str, Any]]) -> int:
    total = 0
    for item in processes:
        try:
            result = run_command(["/usr/sbin/lsof", "-p", str(item["pid"]), "-F", "f"], timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            continue
        total += sum(1 for line in result.stdout.splitlines() if line.startswith("f"))
    return total


def parse_footprint_text(text: str) -> Dict[str, int]:
    footprint = re.search(r"phys_footprint:\s*(\d+)\s*B", text)
    peak = re.search(r"phys_footprint_peak:\s*(\d+)\s*B", text)
    malloc_large = None
    for line in text.splitlines():
        if "Malloc Large" in line:
            match = re.search(r"(\d+)\s*B", line)
            if match:
                malloc_large = int(match.group(1))
            break
    return {
        "footprintBytes": int(footprint.group(1)) if footprint else 0,
        "footprintPeakBytes": int(peak.group(1)) if peak else 0,
        "mallocLargeBytes": malloc_large or 0,
    }


def footprint_metrics(pid: int) -> Dict[str, int]:
    try:
        result = run_command(["/usr/bin/footprint", "-p", str(pid), "--format", "bytes"], timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return {"footprintBytes": 0, "footprintPeakBytes": 0, "mallocLargeBytes": 0}
    return parse_footprint_text(result.stdout + result.stderr)


def compile_window_ready(source: pathlib.Path, output: pathlib.Path) -> pathlib.Path:
    compiler = shutil.which("swiftc")
    if compiler is None:
        raise RuntimeError("swiftc is required to measure launch latency")
    output.parent.mkdir(parents=True, exist_ok=True)
    result = run_command([compiler, str(source), "-o", str(output)], timeout=60)
    if result.returncode != 0:
        raise RuntimeError("cannot compile window readiness helper: %s" % result.stderr.strip())
    return output


def wait_for_no_existing_app(stop_existing: bool) -> None:
    result = run_command(["/usr/bin/pgrep", "-x", "Covio"])
    pids = [int(value) for value in result.stdout.split() if value.isdigit()]
    if not pids:
        return
    if not stop_existing:
        raise RuntimeError("Covio is already running; rerun with --stop-running")
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if not run_command(["/usr/bin/pgrep", "-x", "Covio"]).stdout.strip():
            return
        time.sleep(0.1)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def parse_exact_process_pids(text: str, command: str) -> List[int]:
    pids: List[int] = []
    for line in text.splitlines():
        pieces = line.strip().split(None, 1)
        if len(pieces) != 2:
            continue
        if pieces[1].strip() == command and pieces[0].isdigit():
            pids.append(int(pieces[0]))
    return pids


def pmset_log_pids() -> List[int]:
    try:
        result = run_command(["ps", "-axo", "pid=,command="], timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return []
    return parse_exact_process_pids(result.stdout, "/usr/bin/pmset -g log")


def terminate_pids(pids: Iterable[int]) -> None:
    live = []
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
            live.append(pid)
        except ProcessLookupError:
            pass
    if not live:
        return
    time.sleep(0.5)
    for pid in live:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def terminate_group(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            pass


def copy_app_log(home: pathlib.Path, destination: pathlib.Path) -> None:
    log = home / "Library" / "Application Support" / "com.wyz.covio" / "logs" / "Covio.log"
    if not log.is_file():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(log, destination)


def launch_once(
    app: Dict[str, Any],
    run_index: int,
    warm_measured: bool,
    output: pathlib.Path,
    window_ready: pathlib.Path,
    settle_seconds: float,
    sample_seconds: int,
    launch_timeout_seconds: float,
    keep_homes: bool,
) -> Dict[str, Any]:
    label = app["label"]
    safe_label = sanitize_name(label)
    run_name = "%s-%02d" % (safe_label, run_index)
    home = output / "homes" / run_name
    tmp = home / "tmp"
    tmp.mkdir(parents=True, exist_ok=True)
    log_dir = output / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    stdout_path = log_dir / (run_name + ".stdout.log")
    stderr_path = log_dir / (run_name + ".stderr.log")
    env = os.environ.copy()
    env.update({"HOME": str(home), "CFFIXED_USER_HOME": str(home), "TMPDIR": str(tmp)})
    row: Dict[str, Any] = {
        "label": label,
        "run": run_index,
        "warmMeasured": warm_measured,
        "status": "error",
        "error": None,
        "launchMs": None,
        "rssKb": None,
        "footprintBytes": None,
        "footprintPeakBytes": None,
        "mallocLargeBytes": None,
        "cpuPercent": None,
        "threads": None,
        "fdCount": None,
        "processCount": None,
        "pid": None,
    }
    process = None
    pmset_before = set(pmset_log_pids())
    stdout_file = stdout_path.open("wb")
    stderr_file = stderr_path.open("wb")
    try:
        started = time.monotonic()
        process = subprocess.Popen(
            [app["executable"]],
            env=env,
            stdout=stdout_file,
            stderr=stderr_file,
            start_new_session=True,
        )
        row["pid"] = process.pid
        ready = run_command(
            [str(window_ready), str(process.pid), str(launch_timeout_seconds)],
            timeout=launch_timeout_seconds + 5,
        )
        row["launchMs"] = (time.monotonic() - started) * 1000
        if ready.returncode != 0:
            row["status"] = "timeout"
            row["error"] = "menu bar item did not appear"
            return row
        if process.poll() is not None:
            row["status"] = "exited"
            row["error"] = "app exited before steady-state sampling"
            return row
        if warm_measured:
            time.sleep(settle_seconds)
            samples = []
            previous = process_tree_metrics(process.pid)
            previous_at = time.monotonic()
            for _ in range(max(1, sample_seconds)):
                time.sleep(1)
                current = process_tree_metrics(process.pid)
                current_at = time.monotonic()
                elapsed = max(0.001, current_at - previous_at)
                interval_cpu = max(
                    0.0,
                    (current["cpuSeconds"] - previous["cpuSeconds"]) / elapsed * 100.0,
                )
                current["intervalCpuPercent"] = interval_cpu
                samples.append(current)
                previous = current
                previous_at = current_at
            last = samples[-1]
            footprint = footprint_metrics(process.pid)
            row.update(
                {
                    "status": "ok",
                    "rssKb": int(statistics.median(item["rssKb"] for item in samples)),
                    "cpuPercent": statistics.mean(float(item["intervalCpuPercent"]) for item in samples),
                    "threads": thread_count(last["processes"]),
                    "fdCount": fd_count(last["processes"]),
                    "processCount": last["processCount"],
                }
            )
            row.update(footprint)
        else:
            row["status"] = "ok"
        return row
    except (OSError, subprocess.TimeoutExpired, ValueError) as error:
        row["error"] = str(error)
        return row
    finally:
        if process is not None:
            terminate_group(process)
        terminate_pids(set(pmset_log_pids()) - pmset_before)
        stdout_file.close()
        stderr_file.close()
        copy_app_log(home, log_dir / (run_name + ".app.log"))
        if not keep_homes:
            shutil.rmtree(home, ignore_errors=True)


def nearest_rank_percentile(values: Sequence[float], percentile: float) -> Optional[float]:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = max(1, int(math.ceil(percentile / 100.0 * len(ordered))))
    return ordered[min(rank - 1, len(ordered) - 1)]


def metric_summary(rows: Sequence[Dict[str, Any]], metric: str) -> Dict[str, Any]:
    values = [float(row[metric]) for row in rows if row.get("status") == "ok" and row.get(metric) is not None]
    if not values:
        return {"count": 0, "median": None, "p95": None, "min": None, "max": None}
    return {
        "count": len(values),
        "median": statistics.median(values),
        "p95": nearest_rank_percentile(values, 95),
        "min": min(values),
        "max": max(values),
    }


def summarize_app(rows: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    ok = [row for row in rows if row.get("status") == "ok"]
    result = {"okRuns": len(ok), "totalRuns": len(rows), "metrics": {}}
    for metric in COMPARISON_METRICS:
        result["metrics"][metric] = metric_summary(ok, metric)
    return result


def percent_change(baseline: Optional[float], candidate: Optional[float]) -> Optional[float]:
    if baseline is None or candidate is None or baseline == 0:
        return None
    return (candidate - baseline) / baseline * 100.0


def compare_summaries(baseline: Dict[str, Any], candidate: Dict[str, Any]) -> Dict[str, Any]:
    comparison: Dict[str, Any] = {}
    for metric in COMPARISON_METRICS:
        base_value = baseline["metrics"][metric]["median"]
        candidate_value = candidate["metrics"][metric]["median"]
        comparison[metric] = {
            "baselineMedian": base_value,
            "candidateMedian": candidate_value,
            "deltaPercent": percent_change(base_value, candidate_value),
            "deltaAbsolute": (
                candidate_value - base_value
                if base_value is not None and candidate_value is not None
                else None
            ),
        }
    return comparison


def data_quality(baseline: Optional[Dict[str, Any]], candidate: Dict[str, Any], requested_runs: int) -> str:
    if baseline is None:
        return "single-app"
    if baseline["okRuns"] < 3 or candidate["okRuns"] < 3:
        return "insufficient"
    if baseline["okRuns"] < requested_runs or candidate["okRuns"] < requested_runs:
        return "partial"
    return "complete"


def environment_quality(
    quality: str,
    environment: Dict[str, Any],
    logical_cpu_count: Optional[int] = None,
) -> Tuple[str, List[str]]:
    warnings: List[str] = []
    contaminated = False
    logical = logical_cpu_count or os.cpu_count() or 1
    load = environment.get("loadAverage") or []
    if load and load[0] >= max(1.0, logical * 0.5):
        warnings.append("high background load: load1=%.3f" % load[0])
        contaminated = True
    top = environment.get("topProcesses") or []
    if top and top[0].get("cpuPercent", 0) >= 50:
        warnings.append(
            "high background CPU: %s %.1f%%"
            % (top[0].get("command", "unknown"), top[0].get("cpuPercent", 0))
        )
        contaminated = True
    if quality == "complete" and contaminated:
        return "contaminated", warnings
    return quality, warnings


def gate_results(
    comparison: Optional[Dict[str, Any]],
    quality: str,
    max_launch_regression_percent: float,
    max_rss_regression_percent: float,
    max_footprint_regression_percent: float,
    max_cpu_increase_points: float,
) -> Dict[str, Any]:
    if comparison is None:
        return {"status": "insufficient", "checks": []}
    thresholds = {
        "launchMs": max_launch_regression_percent,
        "rssKb": max_rss_regression_percent,
        "footprintBytes": max_footprint_regression_percent,
    }
    checks = []
    for metric, threshold in thresholds.items():
        item = comparison[metric]
        delta = item["deltaPercent"]
        if delta is None:
            checks.append({"metric": metric, "status": "unknown", "delta": None, "limit": threshold})
        else:
            checks.append(
                {
                    "metric": metric,
                    "status": "pass" if delta <= threshold else "fail",
                    "delta": delta,
                    "limit": threshold,
                }
            )
    cpu_delta = comparison["cpuPercent"]["deltaAbsolute"]
    if cpu_delta is None:
        checks.append({"metric": "cpuPercent", "status": "unknown", "delta": None, "limit": max_cpu_increase_points})
    else:
        checks.append(
            {
                "metric": "cpuPercent",
                "status": "pass" if cpu_delta <= max_cpu_increase_points else "fail",
                "delta": cpu_delta,
                "limit": max_cpu_increase_points,
            }
        )
    if quality != "complete" or any(check["status"] == "unknown" for check in checks):
        status = "insufficient"
    elif any(check["status"] == "fail" for check in checks):
        status = "fail"
    else:
        status = "pass"
    return {"status": status, "checks": checks}


def write_csv(path: pathlib.Path, rows: Sequence[Dict[str, Any]]) -> None:
    fields = [
        "label",
        "run",
        "warmMeasured",
        "status",
        "error",
        "launchMs",
        "rssKb",
        "footprintBytes",
        "footprintPeakBytes",
        "mallocLargeBytes",
        "cpuPercent",
        "threads",
        "fdCount",
        "processCount",
        "pid",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def format_value(metric: str, value: Optional[float]) -> str:
    if value is None:
        return "n/a"
    if metric == "footprintBytes":
        return "%.2f MB" % (value / 1_000_000.0)
    if metric == "rssKb":
        return "%.0f KiB" % value
    if metric == "launchMs":
        return "%.3f ms" % value
    if metric == "cpuPercent":
        return "%.3f%%" % value
    if metric == "threads":
        return "%.1f" % value
    if metric == "fdCount":
        return "%.1f" % value
    return "%.3f" % value


def metric_label(metric: str) -> str:
    return {
        "launchMs": "warm launch",
        "rssKb": "process-tree RSS",
        "footprintBytes": "physical footprint",
        "cpuPercent": "CPU average",
        "threads": "threads",
        "fdCount": "file descriptors",
    }[metric]


def write_summary(path: pathlib.Path, result: Dict[str, Any]) -> None:
    lines = [
        "# Covio performance summary",
        "",
        "Generated: `%s`" % result["generatedAt"],
        "",
        "Data quality: **%s**" % result["quality"],
        "",
        "## Environment",
        "",
        "| Field | Value |",
        "| --- | --- |",
        "| Device | `%s` |" % result["environment"]["machine"],
        "| OS | `%s (%s)` |" % (result["environment"]["osVersion"], result["environment"]["osBuild"]),
        "| Architecture | `%s` |" % result["environment"]["architecture"],
        "| Xcode | `%s` |" % result["environment"]["xcode"].replace("\n", " "),
        "| Power | `%s` |" % result["environment"]["power"].replace("\n", " "),
        "| Load average | `%s` |" % ", ".join("%.3f" % value for value in result["environment"]["loadAverage"]),
        "",
        "## Median comparison",
        "",
    ]
    apps = result["apps"]
    if len(apps) == 2 and result["comparison"] is not None:
        baseline_label = apps[0]["label"]
        candidate_label = apps[1]["label"]
        lines.extend(
            [
                "| Metric | %s | %s | Change |" % (baseline_label, candidate_label),
                "| --- | ---: | ---: | ---: |",
            ]
        )
        for metric in COMPARISON_METRICS:
            item = result["comparison"][metric]
            change = item["deltaPercent"]
            change_text = "n/a" if change is None else "%+.2f%%" % change
            lines.append(
                "| %s | %s | %s | %s |"
                % (
                    metric_label(metric),
                    format_value(metric, item["baselineMedian"]),
                    format_value(metric, item["candidateMedian"]),
                    change_text,
                )
            )
    else:
        label = apps[-1]["label"]
        summary = result["summaries"][label]
        lines.extend(["| Metric | Median | p95 |", "| --- | ---: | ---: |"])
        for metric in COMPARISON_METRICS:
            item = summary["metrics"][metric]
            lines.append("| %s | %s | %s |" % (metric_label(metric), format_value(metric, item["median"]), format_value(metric, item["p95"])))
    if result["artifacts"]:
        lines.extend(["", "## Artifacts", "", "| App | Label | Bytes |", "| --- | --- | ---: |"])
        for artifact in result["artifacts"]:
            lines.append("| %s | %s | %s |" % (artifact["app"], artifact["label"], artifact["bytes"]))
    if result["gate"] is not None:
        lines.extend(["", "## Gate", "", "Status: **%s**" % result["gate"]["status"], ""])
        for check in result["gate"]["checks"]:
            delta = check["delta"]
            delta_text = "n/a" if delta is None else "%.3f" % delta
            lines.append("- `%s`: %s; delta=%s; limit=%s" % (check["metric"], check["status"], delta_text, check["limit"]))
    if result["warnings"]:
        lines.extend(["", "## Warnings", ""])
        lines.extend("- %s" % warning for warning in result["warnings"])
    lines.extend(
        [
            "",
            "## Result files",
            "",
            "- `results.json`",
            "- `results.csv`",
            "- `summary.md`",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Reproducible macOS performance comparison.")
    parser.add_argument("--baseline-label", default="baseline")
    parser.add_argument("--candidate-label", default="candidate")
    parser.add_argument("--baseline-app", type=pathlib.Path)
    parser.add_argument("--candidate-app", type=pathlib.Path)
    parser.add_argument("--baseline-artifact", action="append", default=[], metavar="LABEL=PATH")
    parser.add_argument("--candidate-artifact", action="append", default=[], metavar="LABEL=PATH")
    parser.add_argument("--runs", type=int, default=DEFAULT_RUNS)
    parser.add_argument("--settle-seconds", type=float, default=DEFAULT_SETTLE_SECONDS)
    parser.add_argument("--sample-seconds", type=int, default=DEFAULT_SAMPLE_SECONDS)
    parser.add_argument("--launch-timeout-seconds", type=float, default=DEFAULT_LAUNCH_TIMEOUT_SECONDS)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--window-ready", type=pathlib.Path)
    parser.add_argument("--keep-homes", action="store_true")
    parser.add_argument("--stop-running", action="store_true")
    parser.add_argument("--enforce", action="store_true")
    parser.add_argument("--max-launch-regression-percent", type=float, default=0.0)
    parser.add_argument("--max-rss-regression-percent", type=float, default=0.0)
    parser.add_argument("--max-footprint-regression-percent", type=float, default=0.0)
    parser.add_argument("--max-cpu-increase-points", type=float, default=0.0)
    return parser.parse_args(argv)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    if sys.platform != "darwin":
        print("macos_benchmark.py requires macOS.", file=sys.stderr)
        return 1
    if args.runs < 1 or args.sample_seconds < 1 or args.settle_seconds < 0:
        print("runs and sample seconds must be positive; settle seconds must be non-negative.", file=sys.stderr)
        return 1
    if args.baseline_app is None and args.candidate_app is None:
        print("Specify --baseline-app, --candidate-app, or both.", file=sys.stderr)
        return 1
    output = args.output
    if output is None:
        output = pathlib.Path("build") / "performance" / datetime.now().strftime("%Y%m%d-%H%M%S")
    output = output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    warnings: List[str] = []
    try:
        wait_for_no_existing_app(args.stop_running)
        window_source = pathlib.Path(__file__).with_name("window_ready.swift")
        window_ready = args.window_ready.expanduser().resolve() if args.window_ready else compile_window_ready(window_source, output / ".window-ready")
        if not window_ready.is_file():
            raise RuntimeError("window readiness helper does not exist: %s" % window_ready)
        apps: List[Dict[str, Any]] = []
        specs = []
        if args.baseline_app is not None:
            specs.append((args.baseline_label, args.baseline_app, args.baseline_artifact))
        if args.candidate_app is not None:
            specs.append((args.candidate_label, args.candidate_app, args.candidate_artifact))
        for label, path, artifact_specs in specs:
            executable = executable_for(path)
            identity = app_identity(path)
            artifacts = []
            for spec in artifact_specs:
                artifact = parse_artifact(spec)
                artifact["app"] = label
                artifacts.append(artifact)
            apps.append(
                {
                    "label": label,
                    "path": str(path.expanduser().resolve()),
                    "executable": str(executable),
                    "identity": identity,
                    "diskSize": app_disk_size(path),
                    "artifacts": artifacts,
                }
            )
        all_artifacts = [artifact for app in apps for artifact in app["artifacts"]]
        rows: List[Dict[str, Any]] = []
        for app in apps:
            row = launch_once(
                app,
                0,
                False,
                output,
                window_ready,
                args.settle_seconds,
                args.sample_seconds,
                args.launch_timeout_seconds,
                args.keep_homes,
            )
            if row["status"] != "ok":
                warnings.append("prewarm failed for %s: %s" % (app["label"], row["error"]))
        for run_index in range(1, args.runs + 1):
            ordered = list(apps)
            if run_index % 2 == 0:
                ordered.reverse()
            for app in ordered:
                row = launch_once(
                    app,
                    run_index,
                    True,
                    output,
                    window_ready,
                    args.settle_seconds,
                    args.sample_seconds,
                    args.launch_timeout_seconds,
                    args.keep_homes,
                )
                rows.append(row)
                print("%s run %d: %s" % (app["label"], run_index, row["status"]), flush=True)
        summaries = {app["label"]: summarize_app([row for row in rows if row["label"] == app["label"]]) for app in apps}
        for app in apps:
            if summaries[app["label"]]["okRuns"] < args.runs:
                warnings.append("%s produced %d/%d successful runs" % (app["label"], summaries[app["label"]]["okRuns"], args.runs))
        environment = environment_report(pathlib.Path.cwd())
        comparison = None
        quality = "single-app"
        gate = None
        if len(apps) == 2:
            comparison = compare_summaries(summaries[apps[0]["label"]], summaries[apps[1]["label"]])
            quality = data_quality(summaries[apps[0]["label"]], summaries[apps[1]["label"]], args.runs)
        quality, environment_warnings = environment_quality(quality, environment)
        warnings.extend(environment_warnings)
        if comparison is not None and args.enforce:
            gate = gate_results(
                comparison,
                quality,
                args.max_launch_regression_percent,
                args.max_rss_regression_percent,
                args.max_footprint_regression_percent,
                args.max_cpu_increase_points,
            )
        result = {
            "schemaVersion": SCHEMA_VERSION,
            "generatedAt": utc_now(),
            "quality": quality,
            "environment": environment,
            "config": {
                "runs": args.runs,
                "settleSeconds": args.settle_seconds,
                "sampleSeconds": args.sample_seconds,
                "launchTimeoutSeconds": args.launch_timeout_seconds,
            },
            "apps": apps,
            "artifacts": all_artifacts,
            "runs": rows,
            "summaries": summaries,
            "comparison": comparison,
            "gate": gate,
            "warnings": warnings,
        }
        write_csv(output / "results.csv", rows)
        (output / "results.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
        write_summary(output / "summary.md", result)
        print("quality=%s output=%s" % (quality, output))
        if gate is not None and gate["status"] != "pass":
            print("performance gate status=%s" % gate["status"], file=sys.stderr)
            return 2
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print("performance benchmark failed: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
