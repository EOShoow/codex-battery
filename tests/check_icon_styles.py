#!/usr/bin/env python3
"""Regression guard for the two user-selectable menu-bar icon styles."""

from pathlib import Path


source = Path(__file__).parents[1] / "Sources" / "main.swift"
text = source.read_text(encoding="utf-8")

for required in (
    'fileprivate enum IconStyle: String',
    'case resetCredits',
    'case serviceTier',
    'private static let iconStyleKey = "iconStyle"',
    'private func drawResetCreditsIcon()',
    'private func drawServiceTierIcon()',
    '@objc private func selectResetCreditsIcon()',
    '@objc private func selectServiceTierIcon()',
):
    assert required in text, f"missing user-selectable icon style component: {required}"

print("icon style selection invariants: ok")
