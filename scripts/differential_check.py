#!/usr/bin/env python3
"""Compare XBRLens fixture output with an independent XML parser."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
INSTANCE = ROOT / "fixtures" / "sample" / "instance.xml"


def expected_facts() -> list[dict[str, str]]:
    root = ET.parse(INSTANCE).getroot()
    facts = []
    for node in root:
        context_ref = node.attrib.get("contextRef")
        if context_ref is None:
            continue
        facts.append({
            "id": node.attrib.get("id", ""),
            "name": node.tag.rsplit("}", 1)[-1],
            "context": context_ref,
            "value": (node.text or "").strip(),
        })
    return facts


def main() -> int:
    expected = expected_facts()
    instance_xml = INSTANCE.read_text(encoding="utf-8")
    output = subprocess.check_output(
        ["moon", "run", "cmd/main", "--", "facts", instance_xml],
        cwd=ROOT,
        text=True,
    )
    actual = json.loads(output)
    if len(actual) != len(expected):
        print(f"fact count mismatch: moonbit={len(actual)} python={len(expected)}")
        return 1
    by_id = {row.get("factId") or "": row for row in actual}
    for fact in expected:
        row = by_id.get(fact["id"])
        if row is None:
            print(f"missing fact {fact['id']}")
            return 1
        if row["localName"] != fact["name"] or row["contextRef"] != fact["context"]:
            print(f"fact mismatch {fact['id']}")
            return 1
    print(f"differential check passed: {len(actual)} facts")
    return 0


if __name__ == "__main__":
    sys.exit(main())