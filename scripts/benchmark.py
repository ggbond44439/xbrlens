#!/usr/bin/env python3
"""Run a repeatable CLI startup/inspect benchmark against the sample fixture."""
from __future__ import annotations

import argparse
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTANCE = ROOT / "fixtures" / "sample" / "instance.xml"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=3)
    args = parser.parse_args()
    source = INSTANCE.read_text(encoding="utf-8")
    samples = []
    for _ in range(args.iterations):
        started = time.perf_counter()
        subprocess.run(
            ["moon", "run", "cmd/main", "--", "inspect", source],
            cwd=ROOT,
            check=True,
            stdout=subprocess.DEVNULL,
        )
        samples.append(time.perf_counter() - started)
    print(f"iterations={args.iterations}")
    print(f"mean_seconds={sum(samples) / len(samples):.6f}")
    print(f"min_seconds={min(samples):.6f}")
    print(f"max_seconds={max(samples):.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())