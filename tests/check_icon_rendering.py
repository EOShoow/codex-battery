#!/usr/bin/env python3
"""Regression guard for the menu-bar quota icon's visual invariants."""

import os
from pathlib import Path
import subprocess
import tempfile


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

preview_value = os.environ.get("CODEX_BATTERY_ICON_PREVIEW")
preview_path = Path(preview_value) if preview_value else None
with tempfile.TemporaryDirectory() as temporary_directory:
    temporary_path = Path(temporary_directory)
    render_source = temporary_path / "main.swift"
    render_binary = temporary_path / "render-icon"
    app_entrypoint = """let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
"""
    render_entrypoint = r"""let view = QuotaIconView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
view.style = .serviceTier
view.serviceTier = "standard"
view.fiveHour = 64
view.week = 82

guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
    fatalError("cannot create icon bitmap")
}
view.cacheDisplay(in: view.bounds, to: representation)
let centerX = representation.pixelsWide / 2
let centerY = representation.pixelsHigh / 2
precondition((representation.colorAt(x: centerX, y: centerY)?.alphaComponent ?? 1) < 0.5,
             "the published standard service tier has no center mark")
view.serviceTier = "fast"
view.cacheDisplay(in: view.bounds, to: representation)
precondition((representation.colorAt(x: centerX, y: centerY)?.alphaComponent ?? 0) > 0.5,
             "the fast tier has a bolt center mark")
if CommandLine.arguments.count > 1,
   let png = representation.representation(using: .png, properties: [:]) {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print("original service tier center marks rendered")

// Split digits: the left half and digit are Codex, the right half and digit are Claude Code.
func ink(_ configure: (QuotaIconView) -> Void, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> CGFloat {
    let icon = QuotaIconView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
    icon.style = .dualResets
    icon.week = 87
    icon.availableResetCredits = 3
    configure(icon)
    guard let bitmap = icon.bitmapImageRepForCachingDisplay(in: icon.bounds) else { fatalError("cannot create icon bitmap") }
    icon.cacheDisplay(in: icon.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / 24
    var total: CGFloat = 0
    for px in Int(x.lowerBound * scale)..<Int(x.upperBound * scale) {
        for py in Int(y.lowerBound * scale)..<Int(y.upperBound * scale) {
            total += bitmap.colorAt(x: px, y: py)?.alphaComponent ?? 0
        }
    }
    return total / (scale * scale)
}
let leftDigit: ClosedRange<CGFloat> = 5.0...10.2
let rightDigit: ClosedRange<CGFloat> = 13.8...19.0
let digitRows: ClosedRange<CGFloat> = 6.5...15.5
let rightEdge: ClosedRange<CGFloat> = 20.5...22.0
precondition(ink({ $0.claudeWeek = 86; $0.claudeResetCredits = 2 }, x: leftDigit, y: digitRows) > 4, "Codex reset digit is missing")
precondition(ink({ $0.claudeWeek = 86; $0.claudeResetCredits = 2 }, x: rightDigit, y: digitRows) > 4, "Claude reset digit is missing")
precondition(ink({ $0.claudeWeek = 86 }, x: rightDigit, y: digitRows) < 0.5, "an unknown Claude count must draw no digit")
precondition(ink({ $0.availableResetCredits = nil; $0.claudeWeek = 86 }, x: leftDigit, y: digitRows) < 0.5,
             "an unknown Codex count must draw no digit")
let fullEdge = ink({ $0.claudeWeek = 100 }, x: rightEdge, y: digitRows)
let staleEdge = ink({ $0.claudeWeek = 100; $0.claudeWeekStale = true }, x: rightEdge, y: digitRows)
let emptyEdge = ink({ $0.claudeWeek = 0 }, x: rightEdge, y: digitRows)
let unknownEdge = ink({ _ in }, x: rightEdge, y: digitRows)
precondition(fullEdge > emptyEdge * 3, "the Claude half-ring must follow its weekly quota")
precondition(staleEdge > emptyEdge && staleEdge < fullEdge * 0.8, "old weekly readings use a muted stroke")
precondition(unknownEdge > emptyEdge * 1.3 && unknownEdge < fullEdge * 0.7, "no Claude reading is dotted, not empty or full")
let plain = ink({ $0.claudeResetCredits = 2 }, x: leftDigit, y: 15.5...17.5)
let underlined = ink({ $0.claudeResetCredits = 2; $0.resetCreditsExpiringSoon = true }, x: leftDigit, y: 15.5...17.5)
precondition(underlined > plain + 2, "a Codex reset expiring soon must be underlined")
print("split digits icon rendered")
"""
    assert app_entrypoint in text, "cannot locate the app entrypoint for icon rendering"
    render_source.write_text(text.replace(app_entrypoint, render_entrypoint), encoding="utf-8")
    subprocess.run(
        ["swiftc", str(render_source),
         *[str(path) for path in sorted(source.parent.glob("*.swift")) if path != source],
         "-framework", "AppKit", "-o", str(render_binary)],
        check=True,
    )
    command = [str(render_binary)]
    if preview_path is not None:
        preview_path.parent.mkdir(parents=True, exist_ok=True)
        command.append(str(preview_path))
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    assert "original service tier center marks rendered" in completed.stdout
    assert "split digits icon rendered" in completed.stdout

print("icon rendering invariants: ok")
