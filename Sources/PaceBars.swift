import AppKit

/// One quota on the shared weekly pace view: used now, projected use at reset, and where even pacing would be.
struct PaceRow {
    let name: String
    let color: NSColor          // provider identity; used fill and projection tint
    let used: Double?           // percent used now
    let projectedUsed: Double?  // percent used at reset; >= 100 means it runs out first
    let pace: Double?           // fraction of the week elapsed (even-pace position)
    let endText: String
    let tone: NSColor           // status color for the end text
    let tooltip: String

    var runsOut: Bool { (projectedUsed ?? 0) >= 100 }

    static func tone(remaining: Double, runsOut: Bool) -> NSColor {
        runsOut ? .systemRed : (remaining < 15 ? .systemOrange : .labelColor)
    }
}

/// Pace bars replace overlapping weekly curves: one row per quota, readable at a glance.
final class PaceBarsView: NSView {
    static let headerHeight: CGFloat = 20
    static let rowHeight: CGFloat = 22
    static func height(rows: Int) -> CGFloat { headerHeight + CGFloat(max(1, rows)) * rowHeight + 4 }

    var title = "Weekly pace"
    var legend: (used: String, projected: String, pace: String) = ("used", "projected", "even pace")
    var rows: [PaceRow] = []
    private var tooltipOwners: [NSString] = [] // addToolTip does not retain its owner
    override var isFlipped: Bool { true }

    static let nameX: CGFloat = 16, barX: CGFloat = 86, barWidth: CGFloat = 226, endX: CGFloat = 322, endWidth: CGFloat = 122

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
        NSAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: NSFont.systemFontSize),
                                                       .foregroundColor: NSColor.labelColor])
            .draw(in: NSRect(x: Self.nameX, y: 2, width: 90, height: 18))
        // Legend, right-aligned: ■ used  ■ projected  | even pace
        var x = Self.endX + Self.endWidth
        for (text, swatch) in [(legend.pace, 0), (legend.projected, 2), (legend.used, 1)] {
            let label = NSAttributedString(string: text, attributes: small)
            x -= ceil(label.size().width)
            label.draw(at: NSPoint(x: x, y: 5))
            x -= 4
            switch swatch {
            case 0: NSColor.labelColor.setFill(); NSRect(x: x - 2, y: 5, width: 2, height: 11).fill(); x -= 2
            case 1: NSColor.secondaryLabelColor.setFill(); NSBezierPath(roundedRect: NSRect(x: x - 8, y: 7, width: 8, height: 8), xRadius: 2, yRadius: 2).fill(); x -= 8
            default: NSColor.secondaryLabelColor.withAlphaComponent(0.3).setFill(); NSBezierPath(roundedRect: NSRect(x: x - 8, y: 7, width: 8, height: 8), xRadius: 2, yRadius: 2).fill(); x -= 8
            }
            x -= 10
        }

        for (index, row) in rows.enumerated() {
            let top = Self.headerHeight + CGFloat(index) * Self.rowHeight
            NSAttributedString(string: row.name, attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
                .draw(in: NSRect(x: Self.nameX, y: top + 2, width: Self.barX - Self.nameX - 6, height: 18))
            let bar = NSRect(x: Self.barX, y: top + 6, width: Self.barWidth, height: 10)
            NSColor.labelColor.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
            func span(_ from: Double, _ to: Double) -> NSRect {
                let a = CGFloat(max(0, min(100, from)) / 100), b = CGFloat(max(0, min(100, to)) / 100)
                return NSRect(x: bar.minX + a * bar.width, y: bar.minY, width: max(0, b - a) * bar.width, height: bar.height)
            }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).addClip()
            if let used = row.used {
                if let projected = row.projectedUsed, projected > used {
                    (row.runsOut ? NSColor.systemRed.withAlphaComponent(0.28) : row.color.withAlphaComponent(0.24)).setFill()
                    span(used, projected).fill()
                }
                row.color.setFill()
                span(0, used).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            if row.runsOut {
                NSColor.systemRed.setFill()
                NSRect(x: bar.maxX - 2, y: bar.minY, width: 2, height: bar.height).fill()
            }
            if let pace = row.pace {
                NSColor.labelColor.setFill()
                NSRect(x: bar.minX + CGFloat(max(0, min(1, pace))) * bar.width - 1, y: bar.minY - 3, width: 2, height: bar.height + 6).fill()
            }
            let right = NSMutableParagraphStyle()
            right.alignment = .right
            right.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: row.endText, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                                 .foregroundColor: row.tone, .paragraphStyle: right])
                .draw(in: NSRect(x: Self.endX, y: top + 3, width: Self.endWidth, height: 16))
        }
    }

    /// Per-row tooltips: hovering a quota shows its own forecast details.
    func installTooltips() {
        removeAllToolTips()
        tooltipOwners = rows.map { $0.tooltip as NSString }
        for (index, owner) in tooltipOwners.enumerated() {
            addToolTip(NSRect(x: 0, y: Self.headerHeight + CGFloat(index) * Self.rowHeight, width: bounds.width, height: Self.rowHeight),
                       owner: owner, userData: nil)
        }
    }
}
