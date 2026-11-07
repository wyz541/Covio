#!/usr/bin/env python3
"""Tests for the repeatable performance benchmark tooling."""

from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODULE_PATH = ROOT / "scripts" / "performance" / "macos_benchmark.py"
WINDOW_SOURCE = ROOT / "scripts" / "performance" / "window_ready.swift"
WINDOWS_SCRIPT = ROOT / "scripts" / "performance" / "windows_benchmark.ps1"

spec = importlib.util.spec_from_file_location("covio_macos_benchmark", MODULE_PATH)
benchmark = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(benchmark)


class PerformanceBenchmarkTests(unittest.TestCase):
    def test_nearest_rank_percentile(self) -> None:
        values = [10.0, 20.0, 30.0, 40.0, 50.0]
        self.assertEqual(benchmark.nearest_rank_percentile(values, 50), 30.0)
        self.assertEqual(benchmark.nearest_rank_percentile(values, 95), 50.0)
        self.assertIsNone(benchmark.nearest_rank_percentile([], 95))

    def test_parse_process_tree(self) -> None:
        text = "\n".join(
            [
                "100 1 1000 1.0 0:01.50 /Applications/Covio.app/Contents/MacOS/Covio",
                "101 100 500 0.5 0:00.25 /usr/bin/pmset -g log",
                "102 999 700 2.0 0:02.00 /usr/bin/other",
            ]
        )
        rows = benchmark.parse_ps_rows(text)
        selected = benchmark.process_tree_rows(100, rows)
        self.assertEqual([item["pid"] for item in selected], [100, 101])
        self.assertEqual(sum(item["rssKb"] for item in selected), 1500)
        self.assertAlmostEqual(sum(item["cpuSeconds"] for item in selected), 1.75)

    def test_exact_process_pid_parser(self) -> None:
        text = "  101 /usr/bin/pmset -g log\n  102 /usr/bin/pmset -g log extra\n  103 /usr/bin/pmset -g log\n"
        self.assertEqual(
            benchmark.parse_exact_process_pids(text, "/usr/bin/pmset -g log"),
            [101, 103],
        )

    def test_helper_probe_parser_records_status_and_identity(self) -> None:
        output = '{"status":"IDENTITY_MISMATCH","releaseId":"0.6.0-internal.32","helperSHA256":"abc"}\n'
        parsed = benchmark.parse_helper_probe(output, "", 1)
        self.assertEqual(parsed["status"], "IDENTITY_MISMATCH")
        self.assertEqual(parsed["releaseId"], "0.6.0-internal.32")
        self.assertEqual(parsed["helperSHA256"], "abc")
        self.assertEqual(parsed["exitCode"], 1)

    def test_helper_probe_parser_marks_non_json_output_unavailable(self) -> None:
        parsed = benchmark.parse_helper_probe("", "unsupported", 2)
        self.assertEqual(parsed["status"], "unavailable")
        self.assertEqual(parsed["exitCode"], 2)
        self.assertEqual(parsed["detail"], "unsupported")

    def test_footprint_parser(self) -> None:
        output = """
 202702848 B           0 B           0 B         11    Malloc Large
 Auxiliary data:
    phys_footprint: 246170824 B
    phys_footprint_peak: 246187208 B
"""
        parsed = benchmark.parse_footprint_text(output)
        self.assertEqual(parsed["footprintBytes"], 246170824)
        self.assertEqual(parsed["footprintPeakBytes"], 246187208)
        self.assertEqual(parsed["mallocLargeBytes"], 202702848)

    def test_summary_and_gate(self) -> None:
        baseline_rows = [
            {
                "status": "ok",
                "launchMs": 400,
                "rssKb": 200000,
                "footprintBytes": 200000000,
                "cpuPercent": 0.4,
                "threads": 15,
                "fdCount": 50,
            }
            for _ in range(3)
        ]
        candidate_rows = [
            {
                "status": "ok",
                "launchMs": 300,
                "rssKb": 150000,
                "footprintBytes": 100000000,
                "cpuPercent": 0.3,
                "threads": 12,
                "fdCount": 45,
            }
            for _ in range(3)
        ]
        baseline = benchmark.summarize_app(baseline_rows)
        candidate = benchmark.summarize_app(candidate_rows)
        comparison = benchmark.compare_summaries(baseline, candidate)
        gate = benchmark.gate_results(comparison, "complete", 0.0, 0.0, 0.0, 0.0)
        self.assertEqual(comparison["rssKb"]["deltaPercent"], -25.0)
        self.assertEqual(gate["status"], "pass")

    def test_gate_fails_on_regression(self) -> None:
        baseline = benchmark.summarize_app(
            [{"status": "ok", "launchMs": 400, "rssKb": 100, "footprintBytes": 100, "cpuPercent": 0.2, "threads": 10, "fdCount": 10}] * 3
        )
        candidate = benchmark.summarize_app(
            [{"status": "ok", "launchMs": 500, "rssKb": 120, "footprintBytes": 100, "cpuPercent": 0.2, "threads": 10, "fdCount": 10}] * 3
        )
        comparison = benchmark.compare_summaries(baseline, candidate)
        gate = benchmark.gate_results(comparison, "complete", 0.0, 0.0, 0.0, 0.0)
        self.assertEqual(gate["status"], "fail")

    def test_data_quality_is_explicit(self) -> None:
        summary = benchmark.summarize_app([{"status": "ok", "launchMs": 1, "rssKb": 1, "footprintBytes": 1, "cpuPercent": 1, "threads": 1, "fdCount": 1}])
        self.assertEqual(benchmark.data_quality(None, summary, 10), "single-app")
        self.assertEqual(benchmark.data_quality(summary, summary, 10), "insufficient")

    def test_high_background_load_marks_quality_contaminated(self) -> None:
        environment = {
            "loadAverage": [8.0, 7.0, 6.0],
            "topProcesses": [{"cpuPercent": 99.0, "command": "rustc"}],
        }
        quality, warnings = benchmark.environment_quality("complete", environment, logical_cpu_count=8)
        self.assertEqual(quality, "contaminated")
        self.assertEqual(len(warnings), 2)

    def test_artifact_spec_parse(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            artifact = pathlib.Path(directory) / "Covio.zip"
            artifact.write_bytes(b"1234")
            parsed = benchmark.parse_artifact("App ZIP=%s" % artifact)
            self.assertEqual(parsed["label"], "App ZIP")
            self.assertEqual(parsed["bytes"], 4)

    def test_cli_help(self) -> None:
        result = subprocess.run(
            [sys.executable, "-I", str(MODULE_PATH), "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("--baseline-app", result.stdout)
        self.assertIn("--candidate-app", result.stdout)
        self.assertIn("--enforce", result.stdout)

    def test_window_ready_source_contract(self) -> None:
        text = WINDOW_SOURCE.read_text()
        self.assertIn("AXExtrasMenuBar", text)
        self.assertIn("--serve", text)
        self.assertIn("CGWindowListCopyWindowInfo", text)
        self.assertIn("kCGWindowOwnerPID", text)
        if sys.platform == "darwin":
            with tempfile.TemporaryDirectory() as directory:
                output = pathlib.Path(directory) / "window-ready"
                result = subprocess.run(["swiftc", str(WINDOW_SOURCE), "-o", str(output)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_windows_script_contract(self) -> None:
        text = WINDOWS_SCRIPT.read_text()
        for value in (
            "BaselinePath",
            "CandidatePath",
            "MainWindowHandle",
            "WorkingSet64",
            "PrivateMemorySize64",
            "results.csv",
            "results.json",
        ):
            self.assertIn(value, text)


if __name__ == "__main__":
    unittest.main()
