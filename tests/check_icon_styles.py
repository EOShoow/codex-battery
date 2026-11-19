#!/usr/bin/env python3
"""Regression guard for the user-selectable menu-bar icon styles."""

from pathlib import Path


source = Path(__file__).parents[1] / "Sources" / "main.swift"
text = source.read_text(encoding="utf-8")

for required in (
    'fileprivate enum IconStyle: String',
    'case resetCredits',
    'case serviceTier',
    'case dualResets',
    'private static let iconStyleKey = "iconStyle"',
    'private func drawResetCreditsIcon()',
    'private func drawServiceTierIcon()',
    'private func drawServiceTierCenterMark(in rect: NSRect)',
    '@objc private func selectResetCreditsIcon()',
    '@objc private func selectServiceTierIcon()',
    'private func drawDualResetsIcon()',
    '@objc private func selectDualResetsIcon()',
):
    assert required in text, f"missing user-selectable icon style component: {required}"

assert 'guard !Self.isStandardServiceTier(serviceTier) else { return }' in text, (
    "the standard service tier keeps its original unmarked center"
)

print("icon style selection invariants: ok")
