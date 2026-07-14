#!/usr/bin/env python3
"""Keep today's token total while preventing the unstable comparison multiplier from returning."""

from pathlib import Path


root = Path(__file__).parents[1]
source = (root / "Sources" / "main.swift").read_text(encoding="utf-8")
readme = (root / "README.md").read_text(encoding="utf-8")
readme_zh = (root / "README.zh-CN.md").read_text(encoding="utf-8")

for required in (
    "private let todayItem",
    'label: t("今日消耗", "Today burn")',
    "let todayTokens: Int?",
    '"todayTokens": today_tokens',
):
    assert required in source, f"today total must remain visible: {required}"

for removed in (
    "todayVs3DayAvg",
    "today_vs_3",
    "prev3_avg",
    "formatTodayFlag",
    "今日冲高",
    "spike today",
):
    assert removed not in source, f"unstable today multiplier remains: {removed}"

assert "Today burn  76.2M  0.3x" not in readme
assert "今日消耗    76.2M  0.3x" not in readme
assert "Today burn  76.2M" in readme
assert "今日消耗    76.2M" in readme_zh

print("today multiplier removed, total retained: ok")
