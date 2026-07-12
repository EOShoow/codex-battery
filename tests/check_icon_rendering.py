#!/usr/bin/env python3
"""Regression guard for the menu-bar quota rings' visual invariants."""

from pathlib import Path


source = Path(__file__).parents[1] / "Sources" / "main.swift"
text = source.read_text(encoding="utf-8")
start = text.index("    private func drawRoundedRing")
end = text.index("    private func roundedRectPath", start)
ring = text[start:end]

assert "withAlphaComponent(0.08)" in ring, (
    "The inactive track must stay subtle enough that an unfilled segment is not read as remaining quota."
)
assert "phase: 0" in ring, (
    "The active stroke must start from a fixed point; a percentage-dependent phase makes the gap jump around the icon."
)
assert "phase: activeLength" not in ring, (
    "Do not couple dash phase to active length: every 1% update would rotate the visible gap."
)

print("icon rendering invariants: ok")
