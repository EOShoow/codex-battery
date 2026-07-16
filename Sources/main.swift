import AppKit
import Foundation

fileprivate enum IconStyle: String {
    case resetCredits
    case serviceTier
}

final class QuotaIconView: NSView {
    var fiveHour: Int?
    var week: Int?
    var availableResetCredits: Int?
    var serviceTier = "standard"
    fileprivate var style: IconStyle = .resetCredits
    var tooltipText = "Codex quota" {
        didSet { toolTip = tooltipText }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = tooltipText
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        toolTip = tooltipText
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.shouldAntialias = true
        switch style {
        case .resetCredits:
            drawResetCreditsIcon()
        case .serviceTier:
            drawServiceTierIcon()
        }
    }

    private func drawResetCreditsIcon() {
        let outerRect = bounds.insetBy(dx: 2.5, dy: 2.5)
        if week == nil && fiveHour == nil {
            drawRoundedRing(in: outerRect, radius: 5.0, remaining: 0, width: 1.5)
        }
        if let week {
            drawRoundedRing(in: outerRect, radius: 5.0, remaining: week, width: 1.5)
            if let fiveHour {
                drawRoundedRing(in: outerRect.insetBy(dx: 2.3, dy: 2.3), radius: 2.7, remaining: fiveHour, width: 1.5)
            }
        } else if let fiveHour {
            drawRoundedRing(in: outerRect, radius: 5.0, remaining: fiveHour, width: 1.5)
        }
        drawResetPips(availableResetCredits)
    }

    private func drawServiceTierIcon() {
        let size = min(bounds.width, bounds.height)
        let origin = NSPoint(x: bounds.midX - size / 2, y: bounds.midY - size / 2)
        let square = NSRect(origin: origin, size: NSSize(width: size, height: size)).insetBy(dx: 2.5, dy: 2.5)
        if week == nil && fiveHour == nil {
            drawServiceTierRing(in: square, remaining: 0, width: 2.7)
        }
        if let week {
            drawServiceTierRing(in: square, remaining: week, width: 2.7)
            if let fiveHour {
                drawServiceTierRing(in: square.insetBy(dx: 3.5, dy: 3.5), remaining: fiveHour, width: 2.7)
            }
        } else if let fiveHour {
            drawServiceTierRing(in: square, remaining: fiveHour, width: 2.7)
        }
        drawServiceTierCenterMark(in: square.insetBy(dx: 7.0, dy: 7.0))
    }

    private func drawServiceTierRing(in rect: NSRect, remaining: Int, width: CGFloat) {
        let base = NSBezierPath(ovalIn: rect)
        base.lineWidth = width
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        base.stroke()

        let clamped = max(0, min(100, remaining))
        guard clamped > 0 else { return }

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: 90,
            endAngle: 90 - CGFloat(clamped) / 100 * 360,
            clockwise: true
        )
        arc.lineWidth = width
        arc.lineCapStyle = .round
        NSColor.labelColor.withAlphaComponent(0.86).setStroke()
        arc.stroke()
    }

    private func drawServiceTierCenterMark(in rect: NSRect) {
        guard !Self.isStandardServiceTier(serviceTier) else { return }
        let x = rect.midX
        let y = rect.midY
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: x + 0.9, y: y + 4.0))
        bolt.line(to: NSPoint(x: x - 3.0, y: y - 0.2))
        bolt.line(to: NSPoint(x: x - 0.5, y: y - 0.2))
        bolt.line(to: NSPoint(x: x - 1.0, y: y - 4.0))
        bolt.line(to: NSPoint(x: x + 3.0, y: y + 0.6))
        bolt.line(to: NSPoint(x: x + 0.5, y: y + 0.6))
        bolt.close()
        NSColor.labelColor.withAlphaComponent(0.9).setFill()
        bolt.fill()
    }

    private static func isStandardServiceTier(_ serviceTier: String) -> Bool {
        let normalized = serviceTier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "standard" || normalized == "default" || normalized == "none" || normalized == "null"
    }

    private func drawRoundedRing(in rect: NSRect, radius: CGFloat, remaining: Int, width: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let path = roundedRectPath(in: rect, radius: radius)
        context.saveGState()
        context.addPath(path)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.08).cgColor)
        context.strokePath()

        let clamped = max(0, min(100, remaining))
        guard clamped > 0 else {
            context.restoreGState()
            return
        }

        let effectiveRadius = min(radius, min(rect.width, rect.height) / 2)
        let perimeter = 2 * (rect.width + rect.height - 4 * effectiveRadius) + 2 * .pi * effectiveRadius
        context.addPath(path)
        context.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.86).cgColor)
        if clamped < 100 {
            let proportionalActiveLength = perimeter * CGFloat(clamped) / 100
            let minimumGapLength: CGFloat = 1.35
            let activeLength = min(proportionalActiveLength, perimeter - minimumGapLength)
            context.setLineDash(
                phase: 0,
                lengths: [activeLength, perimeter - activeLength]
            )
        }
        context.strokePath()
        context.restoreGState()
    }

    private func roundedRectPath(in rect: NSRect, radius: CGFloat) -> CGPath {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .pi / 2,
            endAngle: 0,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: 0,
            endAngle: -.pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: -.pi / 2,
            endAngle: -.pi,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .pi,
            endAngle: .pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private func drawResetPips(_ count: Int?) {
        guard let count else { return }
        let normalizedCount = max(0, count)
        let visibleCount = min(6, normalizedCount)
        let positions: [(CGFloat, CGFloat)]
        let spacing: NSSize
        let pipRadius: CGFloat
        switch visibleCount {
        case 1:
            positions = [(0, 0)]
            spacing = .zero
            pipRadius = 3.0
        case 2:
            positions = [(-1, 1), (1, -1)]
            spacing = NSSize(width: 2.9, height: 2.4)
            pipRadius = 2.2
        case 3:
            positions = [(-1, 1), (0, 0), (1, -1)]
            spacing = NSSize(width: 3.35, height: 2.85)
            pipRadius = 1.8
        case 4:
            positions = [(-1, 1), (1, 1), (-1, -1), (1, -1)]
            spacing = NSSize(width: 2.9, height: 2.4)
            pipRadius = 1.8
        case 5:
            positions = [(-1, 1), (1, 1), (0, 0), (-1, -1), (1, -1)]
            spacing = NSSize(width: 2.9, height: 2.45)
            pipRadius = 1.6
        case 6:
            positions = [(-1, 1), (-1, 0), (-1, -1), (1, 1), (1, 0), (1, -1)]
            spacing = NSSize(width: 2.8, height: 3.1)
            pipRadius = 1.5
        default:
            positions = []
            spacing = .zero
            pipRadius = 0
        }
        NSColor.labelColor.withAlphaComponent(0.9).setFill()
        for position in positions {
            let center = NSPoint(
                x: bounds.midX + position.0 * spacing.width,
                y: bounds.midY + position.1 * spacing.height
            )
            NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - pipRadius,
                    y: center.y - pipRadius,
                    width: pipRadius * 2,
                    height: pipRadius * 2
                )
            ).fill()
        }
    }
}

struct WeeklyTrendPoint: Decodable {
    let timestamp: Double
    let used: Double
}

private struct WeeklyTrendCalculation {
    let rate: Double?
    let confidence: String
    let spanHours: Double
    let points: [WeeklyTrendPoint]
    let projectedUsed: Double?
    let exhaustAt: Double?
    let model: String
}

private enum WeeklyTrendCalculator {
    static func merge(
        points: [WeeklyTrendPoint],
        sourceReset: Int?,
        targetReset: Int?,
        timestamp: String?,
        currentUsed: Double?,
        habitWeights: [Double]? = nil,
        habitTimeZoneOffsetSeconds: Int? = nil,
        habitSampleDays: Int? = nil,
        habitSampleBuckets: Int? = nil
    ) -> WeeklyTrendCalculation {
        guard let targetReset,
              let currentUsed,
              let now = parseTimestamp(timestamp) else {
            return emptyCalculation()
        }

        let resetAt = TimeInterval(targetReset)
        let nowAt = now.timeIntervalSince1970
        let weekSeconds: TimeInterval = 7 * 24 * 3600
        let startAt = resetAt - weekSeconds
        guard nowAt >= startAt, nowAt <= resetAt + 300 else {
            return emptyCalculation()
        }

        let sameWindow = sourceReset.map { abs($0 - targetReset) <= 300 } ?? false
        let clampedUsed = max(0, min(100, currentUsed))
        let sourcePoints = sameWindow ? points : []
        var buckets: [Int: Double] = [:]
        for point in sourcePoints where point.timestamp >= startAt - 300 && point.timestamp <= nowAt + 300 {
            let bucket = Int(point.timestamp / 300) * 300
            let used = max(0, min(clampedUsed, point.used))
            buckets[bucket] = max(used, buckets[bucket] ?? 0)
        }

        var observed: [WeeklyTrendPoint] = []
        var highest = 0.0
        for (bucket, used) in buckets.sorted(by: { $0.key < $1.key }) {
            highest = max(highest, used)
            observed.append(WeeklyTrendPoint(timestamp: Double(bucket), used: highest))
        }
        if observed.last?.timestamp != nowAt || observed.last?.used != clampedUsed {
            observed.append(WeeklyTrendPoint(timestamp: nowAt, used: clampedUsed))
        }

        let elapsedHours = max((nowAt - startAt) / 3600, 1 / 60)
        let target = nowAt - 24 * 3600
        let chartSource = [WeeklyTrendPoint(timestamp: startAt, used: 0)] + observed
        let anchor = chartSource.last(where: { $0.timestamp <= target }) ?? chartSource.first

        let realObserved = observed.filter { $0.timestamp > startAt + 300 }
        let spanHours: Double
        if let first = realObserved.first, let last = realObserved.last, realObserved.count >= 2 {
            spanHours = max(0, (last.timestamp - first.timestamp) / 3600)
        } else {
            spanHours = 0
        }
        let changes = zip(realObserved, realObserved.dropFirst()).filter { $0.used < $1.used }.count
        let historyDays = max(0, habitSampleDays ?? 0)
        let historyBuckets = max(0, habitSampleBuckets ?? 0)
        let confidence: String
        if historyDays >= 18, historyBuckets >= 48, spanHours >= 24, changes >= 3 {
            confidence = "high"
        } else if historyDays >= 7, historyBuckets >= 20, changes >= 2 {
            confidence = "medium"
        } else if spanHours >= 48, changes >= 5 {
            confidence = "high"
        } else if spanHours >= 24, changes >= 3 {
            confidence = "medium"
        } else {
            confidence = "low"
        }

        var displayPoints = [WeeklyTrendPoint(timestamp: startAt, used: 0)]
        for point in observed where point.used != displayPoints.last?.used {
            displayPoints.append(point)
        }
        if displayPoints.last?.timestamp != nowAt || displayPoints.last?.used != clampedUsed {
            displayPoints.append(WeeklyTrendPoint(timestamp: nowAt, used: clampedUsed))
        }

        let offsetSeconds = habitTimeZoneOffsetSeconds ?? 0
        let usableHabitWeights: [Double]?
        if let habitWeights,
           habitWeights.count == 168,
           habitWeights.contains(where: { $0.isFinite && $0 > 0 }) {
            usableHabitWeights = habitWeights.map { $0.isFinite ? max(0, $0) : 0 }
        } else {
            usableHabitWeights = nil
        }

        let rate: Double
        let projectedUsed: Double
        let exhaustAt: Double?
        let model: String
        if let weights = usableHabitWeights {
            let elapsedWeight = max(
                habitWeight(
                    from: startAt,
                    to: nowAt,
                    weights: weights,
                    timeZoneOffsetSeconds: offsetSeconds
                ),
                1 / 60
            )
            let baseHabitRate = clampedUsed / elapsedWeight
            var habitRate = baseHabitRate
            if let anchor {
                let coverageHours = (nowAt - anchor.timestamp) / 3600
                let recentHabitWeight = habitWeight(
                    from: anchor.timestamp,
                    to: nowAt,
                    weights: weights,
                    timeZoneOffsetSeconds: offsetSeconds
                )
                if coverageHours >= 6, recentHabitWeight >= 1 {
                    var recentRate = max(0, (clampedUsed - anchor.used) / recentHabitWeight)
                    let recentCap = max(baseHabitRate * 2.5, baseHabitRate + 0.25)
                    recentRate = min(recentRate, recentCap)
                    let recentWeight = 0.35 * min(1, coverageHours / 24)
                    habitRate = baseHabitRate * (1 - recentWeight) + recentRate * recentWeight
                }
            }
            let futureWeight = habitWeight(
                from: nowAt,
                to: resetAt,
                weights: weights,
                timeZoneOffsetSeconds: offsetSeconds
            )
            projectedUsed = clampedUsed + habitRate * futureWeight
            let remainingHours = max(0, (resetAt - nowAt) / 3600)
            rate = remainingHours > 0 ? max(0, projectedUsed - clampedUsed) / remainingHours : 0
            if projectedUsed >= 100, habitRate > 0 {
                exhaustAt = habitExhaustTimestamp(
                    from: nowAt,
                    to: resetAt,
                    requiredWeight: max(0, (100 - clampedUsed) / habitRate),
                    weights: weights,
                    timeZoneOffsetSeconds: offsetSeconds
                )
            } else {
                exhaustAt = nil
            }
            model = "habit"
        } else {
            let baseRate = clampedUsed / elapsedHours
            var wallClockRate = baseRate
            if let anchor {
                let coverageHours = (nowAt - anchor.timestamp) / 3600
                if coverageHours >= 6 {
                    var recentRate = max(0, (clampedUsed - anchor.used) / coverageHours)
                    let recentCap = max(baseRate * 2.5, baseRate + 0.25)
                    recentRate = min(recentRate, recentCap)
                    let recentWeight = 0.35 * min(1, coverageHours / 24)
                    wallClockRate = baseRate * (1 - recentWeight) + recentRate * recentWeight
                }
            }
            rate = wallClockRate
            let remainingHours = max(0, (resetAt - nowAt) / 3600)
            projectedUsed = clampedUsed + wallClockRate * remainingHours
            exhaustAt = projectedUsed >= 100 && wallClockRate > 0
                ? nowAt + max(0, (100 - clampedUsed) / wallClockRate) * 3600
                : nil
            model = "elapsed"
        }

        return WeeklyTrendCalculation(
            rate: rate,
            confidence: confidence,
            spanHours: spanHours,
            points: displayPoints,
            projectedUsed: projectedUsed,
            exhaustAt: exhaustAt,
            model: model
        )
    }

    private static func emptyCalculation() -> WeeklyTrendCalculation {
        WeeklyTrendCalculation(
            rate: nil,
            confidence: "low",
            spanHours: 0,
            points: [],
            projectedUsed: nil,
            exhaustAt: nil,
            model: "elapsed"
        )
    }

    private static func habitHourIndex(_ timestamp: Double, timeZoneOffsetSeconds: Int) -> Int {
        let localHours = Int(floor((timestamp + Double(timeZoneOffsetSeconds)) / 3600))
        let localDays = Int(floor(Double(localHours) / 24))
        let hour = ((localHours % 24) + 24) % 24
        let weekday = ((localDays + 3) % 7 + 7) % 7
        return weekday * 24 + hour
    }

    private static func habitWeight(
        from start: Double,
        to end: Double,
        weights: [Double],
        timeZoneOffsetSeconds: Int
    ) -> Double {
        guard end > start, weights.count == 168 else { return 0 }
        var cursor = start
        var total = 0.0
        while cursor < end {
            let localHour = floor((cursor + Double(timeZoneOffsetSeconds)) / 3600)
            let nextBoundary = (localHour + 1) * 3600 - Double(timeZoneOffsetSeconds)
            let segmentEnd = min(end, max(cursor + 1, nextBoundary))
            let durationHours = (segmentEnd - cursor) / 3600
            total += durationHours * weights[habitHourIndex(cursor, timeZoneOffsetSeconds: timeZoneOffsetSeconds)]
            cursor = segmentEnd
        }
        return total
    }

    private static func habitExhaustTimestamp(
        from start: Double,
        to end: Double,
        requiredWeight: Double,
        weights: [Double],
        timeZoneOffsetSeconds: Int
    ) -> Double? {
        guard requiredWeight > 0, end > start, weights.count == 168 else { return start }
        var remaining = requiredWeight
        var cursor = start
        while cursor < end {
            let localHour = floor((cursor + Double(timeZoneOffsetSeconds)) / 3600)
            let nextBoundary = (localHour + 1) * 3600 - Double(timeZoneOffsetSeconds)
            let segmentEnd = min(end, max(cursor + 1, nextBoundary))
            let weight = weights[habitHourIndex(cursor, timeZoneOffsetSeconds: timeZoneOffsetSeconds)]
            let segmentHours = (segmentEnd - cursor) / 3600
            let available = segmentHours * weight
            if weight > 0, remaining <= available {
                return cursor + remaining / weight * 3600
            }
            remaining -= available
            cursor = segmentEnd
        }
        return nil
    }

    private static func parseTimestamp(_ timestamp: String?) -> Date? {
        guard var timestamp, !timestamp.isEmpty else { return nil }
        if timestamp.hasSuffix("Z") {
            timestamp = String(timestamp.dropLast()) + "+00:00"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp) ?? fallback.date(from: timestamp)
    }
}

private enum WeeklyForecastClock {
    static func isExpired(resetSeconds: Int, wallClockNow: Date = Date()) -> Bool {
        Date(timeIntervalSince1970: TimeInterval(resetSeconds)) <= wallClockNow
    }

    static func referenceNow(snapshot: Date?, wallClockNow: Date = Date()) -> Date {
        max(snapshot ?? wallClockNow, wallClockNow)
    }
}

private struct ResetCreditMarkerTiming {
    let expiration: Date
    let progress: CGFloat
    let countOnDay: Int
    let isUrgent: Bool
}

private enum ResetCreditTimeline {
    static func futureExpirations(_ seconds: [Int]?, now: Date = Date()) -> [Date] {
        (seconds ?? [])
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
            .filter { $0 > now }
            .sorted()
    }

    static func progress(for expiration: Date, from start: Date, to reset: Date) -> CGFloat? {
        let duration = reset.timeIntervalSince(start)
        guard duration > 0,
              expiration >= start,
              expiration <= reset else { return nil }
        return CGFloat(expiration.timeIntervalSince(start) / duration)
    }

    static func nearestMarker(
        expirations: [Int]?,
        now: Date,
        start: Date,
        reset: Date,
        calendar: Calendar = .current
    ) -> ResetCreditMarkerTiming? {
        let inCurrentWeek = futureExpirations(expirations, now: now)
            .filter { $0 >= start && $0 <= reset }
        guard let nearest = inCurrentWeek.first,
              let progress = progress(for: nearest, from: start, to: reset) else {
            return nil
        }
        let countOnDay = inCurrentWeek.filter { calendar.isDate($0, inSameDayAs: nearest) }.count
        return ResetCreditMarkerTiming(
            expiration: nearest,
            progress: progress,
            countOnDay: countOnDay,
            isUrgent: nearest.timeIntervalSince(now) <= 24 * 3600
        )
    }

    static func missingExpiryCount(availableCount: Int?, knownExpirations: Int) -> Int {
        guard let availableCount else { return 0 }
        return max(0, availableCount - max(0, knownExpirations))
    }
}

private struct ResetCreditExpiryMarker {
    let progress: CGFloat
    let label: String
    let tone: NSColor
}

private struct WeeklyForecastPresentation {
    let summary: String
    let confidence: String
    let actualPoints: [CGPoint]
    let currentPoint: CGPoint?
    let forecastPoint: CGPoint?
    let resetCreditMarker: ResetCreditExpiryMarker?
    let tone: NSColor
    let tooltip: String
}

final class WeeklyForecastView: NSView {
    var title = "Forecast"
    var summary = "-"
    var confidence = ""
    var startLabel = "Start"
    var resetLabel = "Reset"
    var actualPoints: [CGPoint] = []
    var currentPoint: CGPoint?
    var forecastPoint: CGPoint?
    fileprivate var resetCreditMarker: ResetCreditExpiryMarker?
    var tone = NSColor.secondaryLabelColor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        let summaryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: tone,
        ]
        let smallAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        NSAttributedString(string: title, attributes: titleAttributes)
            .draw(in: NSRect(x: 16, y: 57, width: 90, height: 18))
        NSAttributedString(string: summary, attributes: summaryAttributes)
            .draw(in: NSRect(x: 112, y: 57, width: 245, height: 18))
        let rightAligned = NSMutableParagraphStyle()
        rightAligned.alignment = .right
        var rightSmallAttributes = smallAttributes
        rightSmallAttributes[.paragraphStyle] = rightAligned
        NSAttributedString(string: confidence, attributes: rightSmallAttributes)
            .draw(in: NSRect(x: 360, y: 59, width: 84, height: 15))

        let graph = NSRect(x: 112, y: 27, width: 332, height: 25)
        let background = NSBezierPath(roundedRect: graph, xRadius: 4, yRadius: 4)
        NSColor.labelColor.withAlphaComponent(0.045).setFill()
        background.fill()

        let ideal = NSBezierPath()
        ideal.move(to: map(CGPoint(x: 0, y: 0), into: graph))
        ideal.line(to: map(CGPoint(x: 1, y: 1), into: graph))
        ideal.lineWidth = 1
        ideal.setLineDash([3, 3], count: 2, phase: 0)
        NSColor.secondaryLabelColor.withAlphaComponent(0.45).setStroke()
        ideal.stroke()

        if let marker = resetCreditMarker {
            let markerX = graph.minX + max(0, min(1, marker.progress)) * graph.width
            let markerLine = NSBezierPath()
            markerLine.move(to: NSPoint(x: markerX, y: graph.minY - 2))
            markerLine.line(to: NSPoint(x: markerX, y: graph.maxY + 1))
            markerLine.lineWidth = 1
            markerLine.setLineDash([2, 2], count: 2, phase: 0)
            marker.tone.withAlphaComponent(0.9).setStroke()
            markerLine.stroke()

            let markerTriangle = NSBezierPath()
            markerTriangle.move(to: NSPoint(x: markerX, y: graph.minY + 1))
            markerTriangle.line(to: NSPoint(x: markerX - 3, y: graph.minY + 6))
            markerTriangle.line(to: NSPoint(x: markerX + 3, y: graph.minY + 6))
            markerTriangle.close()
            marker.tone.setFill()
            markerTriangle.fill()

            let markerAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: marker.tone,
            ]
            let markerText = NSAttributedString(string: marker.label, attributes: markerAttributes)
            let markerWidth = min(126, ceil(markerText.size().width) + 4)
            let markerXOrigin = max(graph.minX, min(graph.maxX - markerWidth, markerX - markerWidth / 2))
            markerText.draw(in: NSRect(x: markerXOrigin + 2, y: 13, width: markerWidth, height: 12))
        }

        if actualPoints.count >= 2 {
            let actual = NSBezierPath()
            actual.move(to: map(actualPoints[0], into: graph))
            for point in actualPoints.dropFirst() {
                actual.line(to: map(point, into: graph))
            }
            actual.lineWidth = 2
            actual.lineCapStyle = .round
            actual.lineJoinStyle = .round
            NSColor.labelColor.withAlphaComponent(0.88).setStroke()
            actual.stroke()
        }

        if let currentPoint, let forecastPoint {
            let forecast = NSBezierPath()
            forecast.move(to: map(currentPoint, into: graph))
            forecast.line(to: map(forecastPoint, into: graph))
            forecast.lineWidth = 2
            forecast.lineCapStyle = .round
            forecast.setLineDash([4, 3], count: 2, phase: 0)
            tone.setStroke()
            forecast.stroke()
        }

        if let currentPoint {
            let center = map(currentPoint, into: graph)
            tone.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)).fill()
        }

        NSAttributedString(string: startLabel, attributes: smallAttributes)
            .draw(in: NSRect(x: 112, y: 1, width: 80, height: 13))
        let resetText = NSAttributedString(string: resetLabel, attributes: rightSmallAttributes)
        resetText.draw(in: NSRect(x: 392, y: 1, width: 52, height: 13))
    }

    private func map(_ point: CGPoint, into rect: NSRect) -> NSPoint {
        let x = rect.minX + max(0, min(1, point.x)) * rect.width
        let y = rect.maxY - max(0, min(1, point.y)) * rect.height
        return NSPoint(x: x, y: y)
    }
}

struct QuotaInfo: Decodable {
    let ok: Bool
    let error: String?
    let timestamp: String?
    let planType: String?
    let limitId: String?
    let limitName: String?
    let quotaSource: String?
    let serviceTier: String?
    let availableResetCredits: Int?
    let resetCreditExpirations: [Int]?
    let primaryUsed: Double?
    let secondaryUsed: Double?
    let primaryReset: Int?
    let secondaryReset: Int?
    let title: String?
    let model: String?
    let effort: String?
    let totalTokens: Int?
    let todayTokens: Int?
    let weeklyTrendRatePctPerHour: Double?
    let weeklyTrendConfidence: String?
    let weeklyTrendSpanHours: Double?
    let weeklyTrendPoints: [WeeklyTrendPoint]?
    let weeklyTrendProjectedUsed: Double?
    let weeklyTrendExhaustAt: Double?
    let weeklyTrendModel: String?
    let weeklyHabitWeights: [Double]?
    let weeklyHabitTimeZoneOffsetSeconds: Int?
    let weeklyHabitSampleDays: Int?
    let weeklyHabitSampleBuckets: Int?
    let topThread: String?
    let topThreadTokens: Int?
    let activeThreads: Int?
    let activeWindowSeconds: Int?

    func replacingQuota(with quota: QuotaInfo, activeThreads: Int, activeWindowSeconds: Int) -> QuotaInfo {
        let mergedTrend = WeeklyTrendCalculator.merge(
            points: weeklyTrendPoints ?? [],
            sourceReset: secondaryReset,
            targetReset: quota.secondaryReset,
            timestamp: quota.timestamp,
            currentUsed: quota.secondaryUsed,
            habitWeights: weeklyHabitWeights,
            habitTimeZoneOffsetSeconds: weeklyHabitTimeZoneOffsetSeconds,
            habitSampleDays: weeklyHabitSampleDays,
            habitSampleBuckets: weeklyHabitSampleBuckets
        )
        return QuotaInfo(
            ok: quota.ok,
            error: quota.error,
            timestamp: quota.timestamp,
            planType: quota.planType,
            limitId: quota.limitId,
            limitName: quota.limitName,
            quotaSource: quota.quotaSource,
            serviceTier: serviceTier ?? quota.serviceTier,
            availableResetCredits: quota.availableResetCredits,
            resetCreditExpirations: quota.resetCreditExpirations,
            primaryUsed: quota.primaryUsed,
            secondaryUsed: quota.secondaryUsed,
            primaryReset: quota.primaryReset,
            secondaryReset: quota.secondaryReset,
            title: title,
            model: model,
            effort: effort,
            totalTokens: totalTokens,
            todayTokens: todayTokens,
            weeklyTrendRatePctPerHour: mergedTrend.rate,
            weeklyTrendConfidence: mergedTrend.confidence,
            weeklyTrendSpanHours: mergedTrend.spanHours,
            weeklyTrendPoints: mergedTrend.points,
            weeklyTrendProjectedUsed: mergedTrend.projectedUsed,
            weeklyTrendExhaustAt: mergedTrend.exhaustAt,
            weeklyTrendModel: mergedTrend.model,
            weeklyHabitWeights: weeklyHabitWeights,
            weeklyHabitTimeZoneOffsetSeconds: weeklyHabitTimeZoneOffsetSeconds,
            weeklyHabitSampleDays: weeklyHabitSampleDays,
            weeklyHabitSampleBuckets: weeklyHabitSampleBuckets,
            topThread: topThread,
            topThreadTokens: topThreadTokens,
            activeThreads: activeThreads,
            activeWindowSeconds: activeWindowSeconds
        )
    }
}

struct ActivityProbeInfo: Decodable {
    let ok: Bool
    let error: String?
    let timestamp: String?
    let sourceUpdatedAt: String?
    let activeThreads: Int?
    let activeWindowSeconds: Int?
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let menuWidth: CGFloat = 460
    private static let syncOnMenuOpenKey = "syncOnMenuOpen"
    private static let activeRefreshMinutesKey = "activeRefreshMinutes"
    private static let idleRefreshMinutesKey = "idleRefreshMinutes"
    private static let failureRetryMinutesKey = "failureRetryMinutes"
    private static let activityProbeSecondsKey = "activityProbeSeconds"
    private static let detailRefreshMinutesKey = "detailRefreshMinutes"
    private static let iconStyleKey = "iconStyle"
    private static let defaultActiveRefreshMinutes = 5
    private static let defaultIdleRefreshMinutes = 30
    private static let defaultFailureRetryMinutes = 5
    private static let defaultActivityProbeSeconds = 300
    private static let defaultDetailRefreshMinutes = 60
    private static let menuQuotaFreshnessSeconds: TimeInterval = 60
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let iconView = QuotaIconView(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
    private let menu = NSMenu()
    private let fiveHourItem = NSMenuItem(title: "5h -", action: nil, keyEquivalent: "")
    private let weekItem = NSMenuItem(title: "1w -", action: nil, keyEquivalent: "")
    private let resetCreditsItem = NSMenuItem(title: "Resets -", action: nil, keyEquivalent: "")
    private let todayItem = NSMenuItem(title: "Today -", action: nil, keyEquivalent: "")
    private let forecastItem = NSMenuItem(title: "Forecast -", action: nil, keyEquivalent: "")
    private let topItem = NSMenuItem(title: "Top -", action: nil, keyEquivalent: "")
    private let activityItem = NSMenuItem(title: "Activity -", action: nil, keyEquivalent: "")
    private let updatedItem = NSMenuItem(title: "Data at -", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Refresh", action: nil, keyEquivalent: "")
    private let syncOnOpenItem = NSMenuItem(title: "Sync on open Off", action: nil, keyEquivalent: "")
    private let iconStyleItem = NSMenuItem(title: "Icon Style", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
    private let useChinese = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
    private var refreshTimer: Timer?
    private var activityProbeTimer: Timer?
    private var isRefreshing = false
    private var nextRefreshInterval: TimeInterval = 300
    private var lastGoodInfo: QuotaInfo?
    private var lastDetailAttemptAt: Date?
    private var lastProbeTriggeredRefreshAt: Date?
    private var lastMenuRefreshAttemptAt: Date?
    private var lastObservedActiveThreads = 0
    private var lastObservedActiveWindowSeconds = 120
    private var pendingScheduledRefresh = false

    private func t(_ zh: String, _ en: String) -> String {
        useChinese ? zh : en
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.length = 24
        if let button = statusItem.button {
            iconView.frame = button.bounds
            iconView.autoresizingMask = [.width, .height]
            button.addSubview(iconView)
            button.toolTip = "Codex Battery"
        }

        configureActionItem(refreshItem, title: t("刷新", "Refresh"), action: #selector(refreshNow))
        configureActionItem(syncOnOpenItem, title: syncOnOpenTitle(), action: #selector(toggleSyncOnOpen))
        configureActionItem(quitItem, title: t("退出", "Quit"), action: #selector(quit))
        configureIconStyleMenu()
        menu.delegate = self
        menu.addItem(fiveHourItem)
        menu.addItem(weekItem)
        menu.addItem(resetCreditsItem)
        menu.addItem(todayItem)
        menu.addItem(forecastItem)
        menu.addItem(topItem)
        menu.addItem(activityItem)
        menu.addItem(updatedItem)
        menu.addItem(.separator())
        menu.addItem(iconStyleItem)
        menu.addItem(refreshItem)
        menu.addItem(syncOnOpenItem)
        menu.addItem(quitItem)
        statusItem.menu = menu

        refreshNow()
        startActivityProbeTimer()
    }

    @objc private func refreshNow() {
        performRefresh(includeDetails: true, reschedule: true)
    }

    @objc private func refreshScheduled() {
        guard !isRefreshing else {
            pendingScheduledRefresh = true
            return
        }
        let detailInterval = Self.detailRefreshInterval()
        let detailsAreDue = lastDetailAttemptAt.map { Date().timeIntervalSince($0) >= detailInterval } ?? true
        performRefresh(includeDetails: detailsAreDue, reschedule: true)
    }

    private func performRefresh(includeDetails: Bool, reschedule: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true
        if includeDetails {
            lastDetailAttemptAt = Date()
        }
        setInfoItem(updatedItem, label: t("数据于", "Data at"), value: t("刷新中...", "Refreshing..."))
        if includeDetails || lastGoodInfo == nil {
            setInfoItem(fiveHourItem, label: t("5小时剩余", "5h left"), value: t("刷新中...", "Refreshing..."))
            setInfoItem(weekItem, label: t("1周剩余", "1w left"), value: "-")
            setResetCreditsItem(count: nil, expirations: [])
            setInfoItem(todayItem, label: t("今日消耗", "Today burn"), value: "-")
            setInfoItem(forecastItem, label: t("周预测", "Forecast"), value: "-")
            setInfoItem(topItem, label: "Top", value: "-")
            setInfoItem(activityItem, label: t("后台活动", "Activity"), value: "-")
        }
        DispatchQueue.global(qos: .utility).async {
            let quotaInfo = Self.readQuotaOnly()
            let detailInfo = includeDetails ? Self.readDetails() : nil
            DispatchQueue.main.async {
                let info: QuotaInfo
                if let detailInfo, detailInfo.ok {
                    self.lastObservedActiveThreads = detailInfo.activeThreads ?? 0
                    self.lastObservedActiveWindowSeconds = detailInfo.activeWindowSeconds ?? 120
                    if quotaInfo.ok {
                        info = detailInfo.replacingQuota(
                            with: quotaInfo,
                            activeThreads: self.lastObservedActiveThreads,
                            activeWindowSeconds: self.lastObservedActiveWindowSeconds
                        )
                    } else if let cached = self.lastGoodInfo, cached.quotaSource == "app_server" {
                        info = detailInfo.replacingQuota(
                            with: cached,
                            activeThreads: self.lastObservedActiveThreads,
                            activeWindowSeconds: self.lastObservedActiveWindowSeconds
                        )
                    } else {
                        info = detailInfo
                    }
                } else if quotaInfo.ok, let cached = self.lastGoodInfo {
                    info = cached.replacingQuota(
                        with: quotaInfo,
                        activeThreads: self.lastObservedActiveThreads,
                        activeWindowSeconds: self.lastObservedActiveWindowSeconds
                    )
                } else {
                    info = quotaInfo
                }
                if info.ok {
                    self.lastGoodInfo = info
                    self.render(info)
                    if !quotaInfo.ok, info.quotaSource == "app_server" {
                        self.setInfoItem(
                            self.updatedItem,
                            label: self.t("旧数据", "Stale"),
                            value: self.formatDataTimestamp(info.timestamp)
                        )
                        self.iconView.tooltipText = self.t(
                            "实时额度读取失败，显示上次成功数据",
                            "Live quota read failed, showing last successful data"
                        )
                    }
                } else if let cached = self.lastGoodInfo {
                    self.render(cached)
                    self.setInfoItem(
                        self.updatedItem,
                        label: self.t("旧数据", "Stale"),
                        value: self.formatDataTimestamp(cached.timestamp)
                    )
                    self.iconView.tooltipText = info.error ?? self.t("读取失败，显示上次成功数据", "Read failed, showing last successful data")
                } else {
                    self.render(info)
                }
                self.isRefreshing = false
                if self.pendingScheduledRefresh {
                    self.pendingScheduledRefresh = false
                    self.refreshScheduled()
                } else if reschedule {
                    self.scheduleNextRefresh(for: quotaInfo.ok ? info : nil)
                } else if !quotaInfo.ok {
                    self.scheduleFailureRetryPreservingEarlierTimer()
                }
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        configureActionItem(syncOnOpenItem, title: syncOnOpenTitle(), action: #selector(toggleSyncOnOpen))
        configureIconStyleMenu()
        guard !isRefreshing else { return }
        let now = Date()
        let lastAttemptIsRecent = lastMenuRefreshAttemptAt.map {
            let age = now.timeIntervalSince($0)
            return age >= 0 && age < Self.menuQuotaFreshnessSeconds
        } ?? false
        guard !lastAttemptIsRecent else { return }
        let fullSyncEnabled = UserDefaults.standard.bool(forKey: Self.syncOnMenuOpenKey)
        let snapshotIsFresh = Self.parseQuotaTimestamp(lastGoodInfo?.timestamp).map { timestamp in
            let age = now.timeIntervalSince(timestamp)
            return age >= 0 && age < Self.menuQuotaFreshnessSeconds
        } ?? false
        guard fullSyncEnabled || !snapshotIsFresh else { return }
        lastMenuRefreshAttemptAt = now
        performRefresh(includeDetails: fullSyncEnabled, reschedule: false)
    }

    private static func parseQuotaTimestamp(_ timestamp: String?) -> Date? {
        guard var timestamp, !timestamp.isEmpty else { return nil }
        if timestamp.hasSuffix("Z") {
            timestamp = String(timestamp.dropLast()) + "+00:00"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp) ?? fallbackFormatter.date(from: timestamp)
    }

    private func render(_ info: QuotaInfo) {
        guard info.ok else {
            let message = info.error ?? "No quota data"
            iconView.fiveHour = nil
            iconView.week = nil
            iconView.availableResetCredits = nil
            iconView.serviceTier = "standard"
            iconView.style = iconStyle
            iconView.needsDisplay = true
            fiveHourItem.isHidden = false
            weekItem.isHidden = true
            forecastItem.isHidden = false
            setInfoItem(fiveHourItem, label: t("错误", "Error"), value: message)
            setResetCreditsItem(count: nil, expirations: [])
            setInfoItem(todayItem, label: t("今日消耗", "Today burn"), value: "-")
            setInfoItem(forecastItem, label: t("周预测", "Forecast"), value: "-")
            setInfoItem(topItem, label: "Top", value: "-")
            setInfoItem(activityItem, label: t("后台活动", "Activity"), value: "-")
            setInfoItem(updatedItem, label: t("数据于", "Data at"), value: "-")
            iconView.tooltipText = message
            return
        }

        let fiveHour = remainingPercentage(used: info.primaryUsed, reset: info.primaryReset)
        let week = remainingPercentage(used: info.secondaryUsed, reset: info.secondaryReset)
        iconView.fiveHour = fiveHour
        iconView.week = week
        let availableResetCredits = info.availableResetCredits.map { max(0, $0) }
        iconView.availableResetCredits = availableResetCredits
        iconView.serviceTier = info.serviceTier ?? "standard"
        iconView.style = iconStyle
        iconView.needsDisplay = true

        let primaryReset = formatReset(info.primaryReset)
        let secondaryReset = formatReset(info.secondaryReset)
        let today = info.todayTokens.map { Self.formatCompact($0) } ?? "-"
        let weeklyForecast = makeWeeklyForecastPresentation(info)
        let topThread = info.topThread ?? "-"
        let topThreadTokens = info.topThreadTokens.map { Self.formatCompact($0) } ?? "-"
        let activity = formatActivity(info)
        let dataAt = formatDataTimestamp(info.timestamp)
        let resetCredits = availableResetCredits.map(String.init) ?? "-"
        let resetCreditExpirations = ResetCreditTimeline.futureExpirations(info.resetCreditExpirations)
        let nearestCreditExpiry = resetCreditExpirations.first.map(formatResetCreditExpiry)
        var detailLines: [String] = []
        if let fiveHour {
            detailLines.append(useChinese ? "5小时剩余: \(fiveHour)%  \(primaryReset)" : "5h left: \(fiveHour)%  \(primaryReset)")
        }
        if let week {
            detailLines.append(useChinese ? "1周剩余: \(week)%  \(secondaryReset)" : "1w left: \(week)%  \(secondaryReset)")
        }
        let resetCreditsDetail = nearestCreditExpiry.map {
            useChinese ? "可用重置: \(resetCredits)  最近 \($0) 到期" : "Resets available: \(resetCredits)  Nearest expires \($0)"
        } ?? (useChinese ? "可用重置: \(resetCredits)" : "Resets available: \(resetCredits)")
        detailLines.append(resetCreditsDetail)
        detailLines.append(useChinese ? "今日: \(today)" : "Today: \(today)")
        detailLines.append(useChinese ? "周预测: \(weeklyForecast.summary)  \(weeklyForecast.confidence)" : "Weekly forecast: \(weeklyForecast.summary)  \(weeklyForecast.confidence)")
        detailLines.append("Top: \(topThread)  \(topThreadTokens)")
        detailLines.append(useChinese ? "后台活动: \(activity)" : "Activity: \(activity)")
        detailLines.append(useChinese ? "数据于: \(dataAt)" : "Data at: \(dataAt)")
        let detail = detailLines.joined(separator: "\n")

        fiveHourItem.isHidden = fiveHour == nil
        weekItem.isHidden = week == nil
        forecastItem.isHidden = week == nil
        if let fiveHour {
            setInfoItem(fiveHourItem, label: t("5小时剩余", "5h left"), value: "\(fiveHour)%", detail: primaryReset)
        }
        if let week {
            setInfoItem(weekItem, label: t("1周剩余", "1w left"), value: "\(week)%", detail: secondaryReset)
        }
        setResetCreditsItem(count: availableResetCredits, expirations: resetCreditExpirations)
        setInfoItem(todayItem, label: t("今日消耗", "Today burn"), value: today)
        setWeeklyForecastItem(forecastItem, presentation: weeklyForecast)
        setInfoItem(topItem, label: "Top", value: topThread, detail: topThreadTokens)
        setInfoItem(activityItem, label: t("后台活动", "Activity"), value: activity)
        setInfoItem(updatedItem, label: t("数据于", "Data at"), value: dataAt)
        iconView.tooltipText = detail
    }

    private func remainingPercentage(used: Double?, reset: Int?) -> Int? {
        guard let used else { return nil }
        return isResetExpired(reset) ? 100 : max(0, 100 - Int(round(used)))
    }

    private func makeWeeklyForecastPresentation(_ info: QuotaInfo) -> WeeklyForecastPresentation {
        guard let used = info.secondaryUsed,
              let resetSeconds = info.secondaryReset else {
            return WeeklyForecastPresentation(
                summary: t("暂无周额度", "No weekly quota"),
                confidence: "",
                actualPoints: [],
                currentPoint: nil,
                forecastPoint: nil,
                resetCreditMarker: nil,
                tone: .secondaryLabelColor,
                tooltip: t("当前没有可预测的周额度窗口", "No weekly quota window is available for forecasting")
            )
        }

        let resetAt = Date(timeIntervalSince1970: TimeInterval(resetSeconds))
        let wallClockNow = Date()
        if WeeklyForecastClock.isExpired(resetSeconds: resetSeconds, wallClockNow: wallClockNow) {
            let summary = t("等待新周数据", "Waiting for new week")
            return WeeklyForecastPresentation(
                summary: summary,
                confidence: t("低置信", "low"),
                actualPoints: [],
                currentPoint: nil,
                forecastPoint: nil,
                resetCreditMarker: nil,
                tone: .secondaryLabelColor,
                tooltip: t("额度窗口已重置，等待 Codex 返回新周快照。", "The quota window reset; waiting for a new weekly snapshot from Codex.")
            )
        }
        let now = WeeklyForecastClock.referenceNow(
            snapshot: Self.parseQuotaTimestamp(info.timestamp),
            wallClockNow: wallClockNow
        )
        let weekSeconds: TimeInterval = 7 * 24 * 3600
        let startAt = resetAt.addingTimeInterval(-weekSeconds)
        let elapsed = max(0, min(weekSeconds, now.timeIntervalSince(startAt)))
        let nowProgress = CGFloat(elapsed / weekSeconds)
        let currentPoint = CGPoint(x: nowProgress, y: CGFloat(max(0, min(100, used)) / 100))
        let resetCreditMarker = makeResetCreditMarker(
            expirations: info.resetCreditExpirations,
            now: now,
            startAt: startAt,
            resetAt: resetAt
        )

        var actualPoints = (info.weeklyTrendPoints ?? []).compactMap { point -> CGPoint? in
            let timestamp = Date(timeIntervalSince1970: point.timestamp)
            let progress = timestamp.timeIntervalSince(startAt) / weekSeconds
            guard progress >= 0, progress <= 1.01 else { return nil }
            return CGPoint(
                x: CGFloat(max(0, min(1, progress))),
                y: CGFloat(max(0, min(used, point.used)) / 100)
            )
        }
        if actualPoints.last != currentPoint {
            actualPoints.append(currentPoint)
        }
        actualPoints.sort { $0.x < $1.x }

        let confidenceName: String
        switch info.weeklyTrendConfidence {
        case "high": confidenceName = t("高置信", "high")
        case "medium": confidenceName = t("中置信", "medium")
        default: confidenceName = t("低置信", "low")
        }
        let spanHours = max(0, info.weeklyTrendSpanHours ?? 0)
        let spanText: String
        if spanHours >= 24 {
            spanText = String(format: "%.1fd", spanHours / 24)
        } else {
            spanText = String(format: "%.0fh", spanHours)
        }
        let habitDays = max(0, info.weeklyHabitSampleDays ?? 0)
        let usesHabitModel = info.weeklyTrendModel == "habit" && habitDays > 0
        let confidence: String
        if usesHabitModel {
            let shortConfidence: String
            switch info.weeklyTrendConfidence {
            case "high": shortConfidence = t("高", "high")
            case "medium": shortConfidence = t("中", "med")
            default: shortConfidence = t("低", "low")
            }
            confidence = t(
                "\(shortConfidence) · 历史\(habitDays)d",
                "\(shortConfidence) · \(habitDays)d"
            )
        } else {
            confidence = spanHours > 0 ? "\(confidenceName) · \(spanText)" : confidenceName
        }
        let habitHint = usesHabitModel
            ? t(
                "预测按近 \(habitDays) 天本机活跃时段加权，夜间和历史空闲时段不会沿用白天速率。",
                "The forecast weights the last \(habitDays) days of local active hours, so nights and historically idle periods do not continue the daytime rate."
            )
            : ""

        guard let rate = info.weeklyTrendRatePctPerHour,
              rate.isFinite,
              rate > 0,
              now < resetAt else {
            let summary = t("样本积累中", "Building forecast")
            let markerHint = resetCreditMarker.map {
                t("，竖线标记\($0.label)", "; vertical marker: \($0.label)")
            } ?? ""
            return WeeklyForecastPresentation(
                summary: summary,
                confidence: confidence,
                actualPoints: actualPoints,
                currentPoint: currentPoint,
                forecastPoint: nil,
                resetCreditMarker: resetCreditMarker,
                tone: .secondaryLabelColor,
                tooltip: t(
                    "\(summary)。\(habitHint)实线为实际消耗，灰线为均匀预算线\(markerHint)。",
                    "\(summary). \(habitHint) Solid is actual usage; gray is the even-budget line\(markerHint)."
                )
            )
        }

        let remainingHours = max(0, resetAt.timeIntervalSince(now) / 3600)
        let projectedUsed = info.weeklyTrendProjectedUsed.flatMap { $0.isFinite ? $0 : nil }
            ?? (used + rate * remainingHours)
        let summary: String
        let forecastPoint: CGPoint
        let tone: NSColor
        if projectedUsed >= 100 {
            let fallbackExhaustAt = now.addingTimeInterval(max(0, (100 - used) / rate) * 3600)
            let exhaustAt: Date
            if let rawExhaustAt = info.weeklyTrendExhaustAt,
               rawExhaustAt.isFinite {
                let candidate = Date(timeIntervalSince1970: rawExhaustAt)
                exhaustAt = min(resetAt, max(now, candidate))
            } else {
                exhaustAt = min(resetAt, fallbackExhaustAt)
            }
            let hoursToExhaust = max(0, exhaustAt.timeIntervalSince(now) / 3600)
            let earlyHours = max(0, remainingHours - hoursToExhaust)
            let earlyText: String
            if earlyHours >= 24 {
                earlyText = useChinese
                    ? String(format: "%.1f 天", earlyHours / 24)
                    : String(format: "%.1f days", earlyHours / 24)
            } else {
                earlyText = useChinese
                    ? String(format: "%.0f 小时", earlyHours)
                    : String(format: "%.0f hours", earlyHours)
            }
            summary = t("预计提前 \(earlyText) 用完", "Runs out \(earlyText) early")
            let exhaustProgress = min(1, max(0, exhaustAt.timeIntervalSince(startAt) / weekSeconds))
            forecastPoint = CGPoint(x: exhaustProgress, y: 1)
            tone = .systemRed
        } else {
            let projectedRemaining = max(0, 100 - projectedUsed)
            summary = t(
                "预计重置时剩 \(Int(round(projectedRemaining)))%",
                "\(Int(round(projectedRemaining)))% left at reset"
            )
            forecastPoint = CGPoint(x: 1, y: CGFloat(projectedUsed / 100))
            tone = projectedRemaining < 15 ? .systemOrange : .systemGreen
        }
        let markerHint = resetCreditMarker.map {
            t("，竖线标记\($0.label)", "; vertical marker: \($0.label)")
        } ?? ""
        let tooltip = t(
            "\(summary)，\(confidence)。\(habitHint)实线为实际消耗，彩色虚线为预测，灰线为均匀预算\(markerHint)。",
            "\(summary), \(confidence). \(habitHint) Solid is actual usage, colored dash is forecast, gray is the even-budget line\(markerHint)."
        )
        return WeeklyForecastPresentation(
            summary: summary,
            confidence: confidence,
            actualPoints: actualPoints,
            currentPoint: currentPoint,
            forecastPoint: forecastPoint,
            resetCreditMarker: resetCreditMarker,
            tone: tone,
            tooltip: tooltip
        )
    }

    private func setWeeklyForecastItem(_ item: NSMenuItem, presentation: WeeklyForecastPresentation) {
        let view = WeeklyForecastView(frame: NSRect(x: 0, y: 0, width: Self.menuWidth, height: 82))
        view.title = t("周预测", "Forecast")
        view.summary = presentation.summary
        view.confidence = presentation.confidence
        view.startLabel = t("周起点", "start")
        view.resetLabel = t("重置", "reset")
        view.actualPoints = presentation.actualPoints
        view.currentPoint = presentation.currentPoint
        view.forecastPoint = presentation.forecastPoint
        view.resetCreditMarker = presentation.resetCreditMarker
        view.tone = presentation.tone
        view.toolTip = presentation.tooltip
        item.view = view
    }

    private func makeResetCreditMarker(
        expirations: [Int]?,
        now: Date,
        startAt: Date,
        resetAt: Date
    ) -> ResetCreditExpiryMarker? {
        guard let timing = ResetCreditTimeline.nearestMarker(
            expirations: expirations,
            now: now,
            start: startAt,
            reset: resetAt
        ) else { return nil }
        let label = t(
            "最近 \(timing.countOnDay) 次 · \(formatResetCreditAxisDate(timing.expiration))到期",
            "\(timing.countOnDay) expires \(formatResetCreditAxisDate(timing.expiration))"
        )
        let tone: NSColor = timing.isUrgent ? .systemRed : .systemOrange
        return ResetCreditExpiryMarker(progress: timing.progress, label: label, tone: tone)
    }

    private func setResetCreditsItem(count: Int?, expirations: [Date]) {
        resetCreditsItem.view = nil
        resetCreditsItem.isHidden = false
        resetCreditsItem.isEnabled = true

        let countText = count.map(String.init) ?? "-"
        if let nearest = expirations.first {
            resetCreditsItem.title = t(
                "可用重置：\(countText) 次 · 最近 \(formatResetCreditExpiry(nearest)) 到期",
                "Resets available: \(countText) · nearest expires \(formatResetCreditExpiry(nearest))"
            )
        } else {
            resetCreditsItem.title = t("可用重置：\(countText) 次", "Resets available: \(countText)")
        }

        let submenu = NSMenu(title: t("重置到期日期", "Reset expiry dates"))
        submenu.autoenablesItems = false
        let missingExpiryCount = ResetCreditTimeline.missingExpiryCount(
            availableCount: count,
            knownExpirations: expirations.count
        )
        if expirations.isEmpty, missingExpiryCount == 0 {
            let empty = NSMenuItem(title: t("暂无到期日期明细", "No expiry-date details"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else if !expirations.isEmpty {
            for (index, expiration) in expirations.enumerated() {
                let prefix = index == 0 ? t("最近到期", "Nearest") : t("第\(index + 1)次", "#\(index + 1)")
                let title = "\(prefix)  \(formatResetCreditExpiry(expiration)) · \(formatResetCreditRelative(expiration))"
                let dateItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                dateItem.isEnabled = false
                submenu.addItem(dateItem)
            }
        }
        if missingExpiryCount > 0 {
            if !expirations.isEmpty {
                submenu.addItem(.separator())
            }
            let missing = NSMenuItem(
                title: t(
                    "另有 \(missingExpiryCount) 次未返回到期日期",
                    "\(missingExpiryCount) expiry date(s) unavailable"
                ),
                action: nil,
                keyEquivalent: ""
            )
            missing.isEnabled = false
            submenu.addItem(missing)
        }
        resetCreditsItem.submenu = submenu
    }

    private func formatResetCreditExpiry(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = useChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        formatter.dateFormat = useChinese ? "M月d日 HH:mm" : "MMM d HH:mm"
        return formatter.string(from: date)
    }

    private func formatResetCreditAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = useChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        formatter.dateFormat = useChinese ? "M/d" : "MMM d"
        return formatter.string(from: date)
    }

    private func formatResetCreditRelative(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 3600 {
            let minutes = max(1, Int(ceil(seconds / 60)))
            return t("\(minutes)分钟后", "in \(minutes)m")
        }
        if seconds < 24 * 3600 {
            let hours = max(1, Int(ceil(seconds / 3600)))
            return t("\(hours)小时后", "in \(hours)h")
        }
        let days = max(1, Int(ceil(seconds / (24 * 3600))))
        return t("\(days)天后", "in \(days)d")
    }

    private func setInfoItem(_ item: NSMenuItem, label: String, value: String, detail: String? = nil) {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: Self.menuWidth, height: 30))
        let tooltip = detail.map { "\(label)  \(value)  \($0)" } ?? "\(label)  \(value)"
        row.toolTip = tooltip

        let labelField = makeLabel(label, frame: NSRect(x: 16, y: 5, width: 90, height: 20))
        let valueWidth: CGFloat = detail == nil ? 326 : 150
        let valueField = makeLabel(value, frame: NSRect(x: 112, y: 5, width: valueWidth, height: 20))
        valueField.lineBreakMode = .byTruncatingTail
        valueField.toolTip = value
        row.addSubview(labelField)
        row.addSubview(valueField)

        if let detail {
            let detailField = makeLabel(detail, frame: NSRect(x: 270, y: 5, width: 174, height: 20))
            detailField.lineBreakMode = .byTruncatingTail
            detailField.toolTip = detail
            row.addSubview(detailField)
        }
        item.view = row
    }

    private func makeLabel(_ text: String, frame: NSRect) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        field.font = .menuFont(ofSize: NSFont.systemFontSize)
        field.textColor = .labelColor
        field.alignment = .left
        return field
    }

    private func configureActionItem(_ item: NSMenuItem, title: String, action: Selector) {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: Self.menuWidth, height: 30))

        let button = NSButton(frame: NSRect(x: 16, y: 1, width: Self.menuWidth - 32, height: 28))
        button.title = title
        button.target = self
        button.action = action
        button.isBordered = false
        button.alignment = .left
        button.font = .menuFont(ofSize: NSFont.systemFontSize)
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryChange)
        button.autoresizingMask = [.width, .height]
        button.contentTintColor = .labelColor

        row.addSubview(button)
        item.view = row
    }

    private func syncOnOpenTitle() -> String {
        let enabled = UserDefaults.standard.bool(forKey: Self.syncOnMenuOpenKey)
        return enabled ? t("打开时完整刷新：开", "Full sync on open: On") : t("打开时完整刷新：关", "Full sync on open: Off")
    }

    private var iconStyle: IconStyle {
        IconStyle(rawValue: UserDefaults.standard.string(forKey: Self.iconStyleKey) ?? "") ?? .resetCredits
    }

    private func configureIconStyleMenu() {
        let submenu = NSMenu(title: t("图标样式", "Icon Style"))
        let resetCreditsItem = NSMenuItem(
            title: t("骰子双环（重置次数）", "Rounded dice (reset credits)"),
            action: #selector(selectResetCreditsIcon),
            keyEquivalent: ""
        )
        resetCreditsItem.target = self
        resetCreditsItem.state = iconStyle == .resetCredits ? .on : .off
        submenu.addItem(resetCreditsItem)

        let serviceTierItem = NSMenuItem(
            title: t("圆环闪电（速度档位）", "Round bolt (service tier)"),
            action: #selector(selectServiceTierIcon),
            keyEquivalent: ""
        )
        serviceTierItem.target = self
        serviceTierItem.state = iconStyle == .serviceTier ? .on : .off
        submenu.addItem(serviceTierItem)

        iconStyleItem.title = t("图标样式", "Icon Style")
        iconStyleItem.submenu = submenu
    }

    @objc private func selectResetCreditsIcon() {
        setIconStyle(.resetCredits)
    }

    @objc private func selectServiceTierIcon() {
        setIconStyle(.serviceTier)
    }

    private func setIconStyle(_ style: IconStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: Self.iconStyleKey)
        iconView.style = style
        iconView.needsDisplay = true
        configureIconStyleMenu()
    }

    @objc private func toggleSyncOnOpen() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: Self.syncOnMenuOpenKey), forKey: Self.syncOnMenuOpenKey)
        configureActionItem(syncOnOpenItem, title: syncOnOpenTitle(), action: #selector(toggleSyncOnOpen))
    }

    private func scheduleNextRefresh(for info: QuotaInfo?) {
        refreshTimer?.invalidate()
        guard let info, info.ok else {
            nextRefreshInterval = Self.refreshInterval(for: Self.failureRetryMinutesKey, defaultMinutes: Self.defaultFailureRetryMinutes)
            refreshTimer = Timer.scheduledTimer(
                timeInterval: nextRefreshInterval,
                target: self,
                selector: #selector(refreshScheduled),
                userInfo: nil,
                repeats: false
            )
            return
        }
        let activeThreads = lastObservedActiveThreads
        nextRefreshInterval = activeThreads > 0
            ? Self.refreshInterval(for: Self.activeRefreshMinutesKey, defaultMinutes: Self.defaultActiveRefreshMinutes)
            : Self.refreshInterval(for: Self.idleRefreshMinutesKey, defaultMinutes: Self.defaultIdleRefreshMinutes)
        refreshTimer = Timer.scheduledTimer(
            timeInterval: nextRefreshInterval,
            target: self,
            selector: #selector(refreshScheduled),
            userInfo: nil,
            repeats: false
        )
    }

    private func scheduleFailureRetryPreservingEarlierTimer() {
        let retryInterval = Self.refreshInterval(
            for: Self.failureRetryMinutesKey,
            defaultMinutes: Self.defaultFailureRetryMinutes
        )
        let retryDate = Date().addingTimeInterval(retryInterval)
        if let refreshTimer, refreshTimer.isValid, refreshTimer.fireDate <= retryDate {
            return
        }
        refreshTimer?.invalidate()
        nextRefreshInterval = retryInterval
        refreshTimer = Timer.scheduledTimer(
            timeInterval: retryInterval,
            target: self,
            selector: #selector(refreshScheduled),
            userInfo: nil,
            repeats: false
        )
    }

    private func startActivityProbeTimer() {
        activityProbeTimer?.invalidate()
        activityProbeTimer = Timer.scheduledTimer(
            timeInterval: Self.activityProbeInterval(),
            target: self,
            selector: #selector(probeActivity),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func probeActivity() {
        guard !isRefreshing else { return }
        DispatchQueue.global(qos: .utility).async {
            let probe = Self.readActivityProbe()
            DispatchQueue.main.async {
                guard probe.ok else { return }
                let activeThreads = probe.activeThreads ?? 0
                let windowSeconds = probe.activeWindowSeconds ?? 120
                let becameActive = activeThreads > 0 && self.lastObservedActiveThreads == 0
                self.lastObservedActiveThreads = activeThreads
                self.lastObservedActiveWindowSeconds = windowSeconds

                if self.lastGoodInfo != nil {
                    self.setInfoItem(
                        self.activityItem,
                        label: self.t("后台活动", "Activity"),
                        value: self.formatActivity(count: activeThreads, seconds: windowSeconds)
                    )
                }

                guard becameActive else { return }
                if let last = self.lastProbeTriggeredRefreshAt, Date().timeIntervalSince(last) < 240 {
                    return
                }
                self.lastProbeTriggeredRefreshAt = Date()
                self.refreshScheduled()
            }
        }
    }

    private static func refreshInterval(for key: String, defaultMinutes: Int) -> TimeInterval {
        let configured = UserDefaults.standard.integer(forKey: key)
        let minutes = configured > 0 ? configured : defaultMinutes
        return TimeInterval(max(1, minutes) * 60)
    }

    private static func activityProbeInterval() -> TimeInterval {
        let configured = UserDefaults.standard.integer(forKey: activityProbeSecondsKey)
        let seconds = configured > 0 ? configured : defaultActivityProbeSeconds
        return TimeInterval(max(30, seconds))
    }

    private static func detailRefreshInterval() -> TimeInterval {
        let configured = UserDefaults.standard.integer(forKey: detailRefreshMinutesKey)
        let minutes = configured > 0 ? configured : defaultDetailRefreshMinutes
        return TimeInterval(max(60, minutes) * 60)
    }

    private static func readQuotaOnly() -> QuotaInfo {
        return readPythonOutput(as: QuotaInfo.self, arguments: ["--quota-only"])
    }

    private static func readDetails() -> QuotaInfo {
        return readPythonOutput(as: QuotaInfo.self, arguments: ["--details-only"])
    }

    private static func readActivityProbe() -> ActivityProbeInfo {
        return readPythonOutput(as: ActivityProbeInfo.self, arguments: ["--activity-probe"])
    }

    private static func readPythonOutput<T: Decodable>(as type: T.Type, arguments: [String]) -> T {
        let script = pythonScript
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script] + arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let fallback = QuotaInfo(
                ok: false,
                error: error.localizedDescription,
                timestamp: nil,
                planType: nil,
                limitId: nil,
                limitName: nil,
                quotaSource: nil,
                serviceTier: nil,
                availableResetCredits: nil,
                resetCreditExpirations: nil,
                primaryUsed: nil,
                secondaryUsed: nil,
                primaryReset: nil,
                secondaryReset: nil,
                title: nil,
                model: nil,
                effort: nil,
                totalTokens: nil,
                todayTokens: nil,
                weeklyTrendRatePctPerHour: nil,
                weeklyTrendConfidence: nil,
                weeklyTrendSpanHours: nil,
                weeklyTrendPoints: nil,
                weeklyTrendProjectedUsed: nil,
                weeklyTrendExhaustAt: nil,
                weeklyTrendModel: nil,
                weeklyHabitWeights: nil,
                weeklyHabitTimeZoneOffsetSeconds: nil,
                weeklyHabitSampleDays: nil,
                weeklyHabitSampleBuckets: nil,
                topThread: nil,
                topThreadTokens: nil,
                activeThreads: nil,
                activeWindowSeconds: nil
            )
            if let typed = fallback as? T {
                return typed
            }
            return ActivityProbeInfo(
                ok: false,
                error: error.localizedDescription,
                timestamp: nil,
                sourceUpdatedAt: nil,
                activeThreads: nil,
                activeWindowSeconds: nil
            ) as! T
        }
    }

    private func formatReset(_ seconds: Int?) -> String {
        guard let seconds else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        if date <= Date() {
            return t("已重置", "reset")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: useChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : (useChinese ? "M月d日 HH:mm" : "MMM d HH:mm")
        return formatter.string(from: date)
    }

    private func isResetExpired(_ seconds: Int?) -> Bool {
        guard let seconds else { return false }
        return Date(timeIntervalSince1970: TimeInterval(seconds)) <= Date()
    }

    private func formatUpdated(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: useChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm:ss" : (useChinese ? "M月d日 HH:mm" : "MMM d HH:mm")
        return formatter.string(from: date)
    }

    private func formatDataTimestamp(_ timestamp: String?) -> String {
        guard var timestamp, !timestamp.isEmpty else { return "-" }
        if timestamp.hasSuffix("Z") {
            timestamp = String(timestamp.dropLast()) + "+00:00"
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: timestamp) ?? fallbackFormatter.date(from: timestamp) else {
            return "-"
        }
        return formatUpdated(date)
    }

    private static func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func formatCompact(_ value: Int) -> String {
        let double = Double(value)
        if value >= 1_000_000 {
            return String(format: "%.1fM", double / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0fK", double / 1_000)
        }
        return "\(value)"
    }

    private func formatActivity(_ info: QuotaInfo) -> String {
        formatActivity(count: info.activeThreads ?? 0, seconds: info.activeWindowSeconds ?? 120)
    }

    private func formatActivity(count: Int, seconds: Int) -> String {
        if count <= 0 {
            return t("空闲", "idle")
        }
        let minutes = max(1, Int(round(Double(seconds) / 60)))
        return t("近\(minutes)分钟 \(count) 个线程仍在消耗", "\(count) thread(s) active in \(minutes)m")
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private let pythonScript = #"""
import json
import os
import pathlib
import select
import sqlite3
import subprocess
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
try:
    import tomllib
except Exception:
    tomllib = None

home = pathlib.Path.home()
db_path = home / ".codex" / "state_5.sqlite"
session_index_path = home / ".codex" / "session_index.jsonl"
global_state_path = home / ".codex" / ".codex-global-state.json"
config_path = home / ".codex" / "config.toml"
codex_binary_candidates = [
    pathlib.Path("/Applications/ChatGPT.app/Contents/Resources/codex"),
    pathlib.Path("/Applications/Codex.app/Contents/Resources/codex"),
]
tz = timezone(timedelta(hours=8))
now = datetime.now(tz)
today = now.date()
ACTIVE_WINDOW_SECONDS = 120

def fail(message):
    print(json.dumps({"ok": False, "error": message}))
    raise SystemExit(0)

def reversed_lines(path, block_size=65536):
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        position = f.tell()
        buffer = b""
        while position > 0:
            read_size = min(block_size, position)
            position -= read_size
            f.seek(position)
            chunk = f.read(read_size)
            lines = (chunk + buffer).split(b"\n")
            buffer = lines[0]
            for line in reversed(lines[1:]):
                if line:
                    yield line.decode("utf-8", "ignore")
        if buffer:
            yield buffer.decode("utf-8", "ignore")

def parse_ts(value):
    if not value:
        return None
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(value).astimezone(tz)
    except Exception:
        return None

def compact_title(value):
    return (value or "Unknown").replace("\n", " ")[:28]

def normalize_service_tier(value):
    if value is None:
        return "standard"
    text = str(value).strip().strip('"').strip("'")
    return text or "standard"

def read_config_service_tier(path):
    if not path.exists():
        return None
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return None
    if tomllib is not None:
        try:
            data = tomllib.loads(text)
            value = data.get("service_tier")
            if value is not None:
                return normalize_service_tier(value)
            desktop = data.get("desktop") or {}
            value = desktop.get("default-service-tier")
            if value is not None:
                return normalize_service_tier(value)
        except Exception:
            pass
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("default-service-tier") and "=" in line:
            return normalize_service_tier(line.split("=", 1)[1].split("#", 1)[0])
    return None

def read_service_tier():
    config_value = read_config_service_tier(config_path)
    if config_value:
        return config_value
    try:
        data = json.loads(global_state_path.read_text(encoding="utf-8"))
        state = data.get("electron-persisted-atom-state") or {}
        return normalize_service_tier(state.get("default-service-tier"))
    except Exception:
        return "standard"

def load_thread_names(path):
    names = {}
    if not path.exists():
        return names
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                if '"thread_name"' not in line:
                    continue
                try:
                    item = json.loads(line)
                except Exception:
                    continue
                thread_id = item.get("id")
                name = item.get("thread_name")
                updated_at = item.get("updated_at") or ""
                if not thread_id or not name:
                    continue
                previous = names.get(thread_id)
                if previous is None or updated_at >= previous[0]:
                    names[thread_id] = (updated_at, name)
    except Exception:
        return {}
    return {thread_id: name for thread_id, (_, name) in names.items()}

def read_recent_json(path, max_lines=1200):
    lines = []
    for line in reversed_lines(path):
        lines.append(line)
        if len(lines) >= max_lines:
            break
    return reversed(lines)

def normalize_quota_windows(primary, secondary):
    def first_value(window, names):
        for name in names:
            value = window.get(name)
            if value is not None:
                return value
        return None

    windows = []
    for position, raw_window in (("primary", primary), ("secondary", secondary)):
        if not raw_window:
            continue
        duration_names = ("windowDurationMins", "window_minutes")
        duration_present = any(name in raw_window for name in duration_names)
        duration = first_value(raw_window, duration_names)
        try:
            duration = float(duration) if duration is not None else None
        except (TypeError, ValueError):
            duration = None
        windows.append((position, {
            "used": first_value(raw_window, ("usedPercent", "used_percent")),
            "reset": first_value(raw_window, ("resetsAt", "resets_at")),
            "duration": duration,
            "duration_present": duration_present,
        }))

    five_hour = None
    week = None
    unclassified = []
    for position, window in windows:
        duration = window.get("duration")
        if duration is not None and 4 * 60 <= duration <= 6 * 60:
            if five_hour is None:
                five_hour = window
            continue
        if duration is not None and 6 * 24 * 60 <= duration <= 8 * 24 * 60:
            if week is None:
                week = window
            continue
        if duration is None and not window.get("duration_present"):
            unclassified.append((position, window))

    # Preserve the legacy primary=5h / secondary=1w contract when older
    # payloads do not carry duration metadata.
    for position, window in unclassified:
        if position == "primary" and five_hour is None:
            five_hour = window
        elif position == "secondary" and week is None:
            week = window
        elif five_hour is None:
            five_hour = window
        elif week is None:
            week = window

    return five_hour, week

def normalize_reset_credit_count(reset_credits):
    if not isinstance(reset_credits, dict):
        return None
    raw_count = reset_credits.get("availableCount")
    if raw_count is None:
        raw_count = reset_credits.get("available_count")
    count = None
    if isinstance(raw_count, int) and not isinstance(raw_count, bool):
        count = raw_count
    elif isinstance(raw_count, str):
        text = raw_count.strip()
        if text.isdigit():
            count = int(text)
    if count is not None and count >= 0:
        return count

    raw_credits = reset_credits.get("credits")
    if not isinstance(raw_credits, list):
        return None
    return sum(
        1 for credit in raw_credits
        if isinstance(credit, dict)
        and str(credit.get("status") or "").lower() == "available"
    )

def normalize_reset_credit_expirations(reset_credits):
    if not isinstance(reset_credits, dict):
        return []
    raw_credits = reset_credits.get("credits") or []
    if not isinstance(raw_credits, list):
        return []
    expirations = []
    for credit in raw_credits:
        if not isinstance(credit, dict):
            continue
        if str(credit.get("status") or "").lower() != "available":
            continue
        expires_at = credit.get("expiresAt")
        if expires_at is None:
            expires_at = credit.get("expires_at")
        try:
            expires_at = int(expires_at)
        except (TypeError, ValueError):
            continue
        if expires_at > 0:
            expirations.append(expires_at)
    return sorted(expirations)

def prefer_monotonic_quota_values(latest, snapshots):
    for used_key, reset_key in (
        ("primaryUsed", "primaryReset"),
        ("secondaryUsed", "secondaryReset"),
    ):
        if latest.get(used_key) is None:
            continue
        reset_at = latest.get(reset_key)
        candidates = [
            snap for snap in snapshots
            if snap.get(used_key) is not None
            and snap.get(reset_key) == reset_at
        ]
        if not candidates:
            continue
        best = max(candidates, key=lambda snap: (float(snap.get(used_key) or 0), snap["ts"]))
        latest[used_key] = best.get(used_key)
    return latest

def habit_hour_index(timestamp, offset_seconds):
    local_hours = int((float(timestamp) + int(offset_seconds)) // 3600)
    local_days = local_hours // 24
    hour = local_hours % 24
    weekday = (local_days + 3) % 7
    return weekday * 24 + hour

def habit_weight_between(start_at, end_at, weights, offset_seconds):
    if not isinstance(weights, list) or len(weights) != 168 or end_at <= start_at:
        return 0.0
    cursor = float(start_at)
    end_at = float(end_at)
    total = 0.0
    while cursor < end_at:
        local_hour = int((cursor + int(offset_seconds)) // 3600)
        next_boundary = (local_hour + 1) * 3600 - int(offset_seconds)
        segment_end = min(end_at, max(cursor + 0.001, float(next_boundary)))
        weight = max(0.0, float(weights[habit_hour_index(cursor, offset_seconds)]))
        total += (segment_end - cursor) / 3600 * weight
        cursor = segment_end
    return total

def habit_exhaust_at(start_at, end_at, required_weight, weights, offset_seconds):
    if required_weight <= 0:
        return float(start_at)
    cursor = float(start_at)
    end_at = float(end_at)
    remaining = float(required_weight)
    while cursor < end_at:
        local_hour = int((cursor + int(offset_seconds)) // 3600)
        next_boundary = (local_hour + 1) * 3600 - int(offset_seconds)
        segment_end = min(end_at, max(cursor + 0.001, float(next_boundary)))
        weight = max(0.0, float(weights[habit_hour_index(cursor, offset_seconds)]))
        available = (segment_end - cursor) / 3600 * weight
        if weight > 0 and remaining <= available:
            return cursor + remaining / weight * 3600
        remaining -= available
        cursor = segment_end
    return None

def build_habit_profile(active_buckets, window_start_at, lookback_days=28):
    empty = {
        "weights": [],
        "timeZoneOffsetSeconds": int(tz.utcoffset(None).total_seconds()),
        "sampleDays": 0,
        "sampleBuckets": 0,
    }
    try:
        window_start_at = float(window_start_at)
    except (TypeError, ValueError):
        return empty

    end_date = datetime.fromtimestamp(window_start_at, tz).date()
    start_date = end_date - timedelta(days=lookback_days)
    weekday_occurrences = Counter()
    cursor_date = start_date
    while cursor_date < end_date:
        weekday_occurrences[cursor_date.weekday()] += 1
        cursor_date += timedelta(days=1)

    counts = [0.0] * 168
    sample_dates = set()
    accepted = set()
    for raw_timestamp in active_buckets:
        try:
            timestamp = int(float(raw_timestamp) // 900) * 900
            value = datetime.fromtimestamp(timestamp, tz)
        except (TypeError, ValueError, OverflowError):
            continue
        if not (start_date <= value.date() < end_date):
            continue
        if timestamp in accepted:
            continue
        accepted.add(timestamp)
        sample_dates.add(value.date())
        counts[value.weekday() * 24 + value.hour] += 1

    if len(sample_dates) < 3 or len(accepted) < 12:
        return empty

    raw_weights = []
    for index, count in enumerate(counts):
        occurrences = max(1, weekday_occurrences[index // 24])
        raw_weights.append(min(1.0, count / (occurrences * 4)))
    hour_means = [
        sum(raw_weights[weekday * 24 + hour] for weekday in range(7)) / 7
        for hour in range(24)
    ]
    global_mean = sum(raw_weights) / len(raw_weights)
    smoothed = [
        0.72 * raw_weights[index]
        + 0.23 * hour_means[index % 24]
        + 0.05 * global_mean
        for index in range(168)
    ]
    mean_weight = sum(smoothed) / len(smoothed)
    if mean_weight <= 0:
        return empty
    return {
        "weights": [weight / mean_weight for weight in smoothed],
        "timeZoneOffsetSeconds": empty["timeZoneOffsetSeconds"],
        "sampleDays": len(sample_dates),
        "sampleBuckets": len(accepted),
    }

def build_weekly_trend(
    points,
    reset_at,
    now_at,
    current_used,
    habit_weights=None,
    habit_offset_seconds=0,
    habit_sample_days=0,
    habit_sample_buckets=0,
):
    empty = {
        "rate": None,
        "confidence": "low",
        "spanHours": 0.0,
        "points": [],
        "projectedUsed": None,
        "exhaustAt": None,
        "model": "elapsed",
    }
    try:
        reset_at = float(reset_at)
        now_at = float(now_at)
        current_used = max(0.0, min(100.0, float(current_used)))
    except (TypeError, ValueError):
        return empty

    week_seconds = 7 * 24 * 3600
    start_at = reset_at - week_seconds
    if now_at < start_at or now_at > reset_at + 300:
        return empty

    buckets = {}
    for timestamp, used, point_reset in points:
        try:
            timestamp = timestamp.timestamp() if hasattr(timestamp, "timestamp") else float(timestamp)
            used = max(0.0, min(current_used, float(used)))
            point_reset = float(point_reset)
        except (TypeError, ValueError):
            continue
        # Codex has emitted the same reset boundary one second apart. Treat a
        # five-minute difference as the same window, while excluding old weeks.
        if abs(point_reset - reset_at) > 300:
            continue
        if timestamp < start_at - 300 or timestamp > now_at + 300:
            continue
        bucket = int(timestamp // 300) * 300
        buckets[bucket] = max(used, buckets.get(bucket, 0.0))

    observed = []
    highest = 0.0
    for timestamp, used in sorted(buckets.items()):
        highest = max(highest, used)
        observed.append((float(timestamp), highest))

    chart_source = [(start_at, 0.0)] + observed
    target = now_at - 24 * 3600
    earlier = [item for item in chart_source if item[0] <= target]
    anchor = earlier[-1] if earlier else (chart_source[0] if chart_source else None)

    span_hours = 0.0
    if len(observed) >= 2:
        span_hours = max(0.0, (observed[-1][0] - observed[0][0]) / 3600)
    changes = sum(a[1] < b[1] for a, b in zip(observed, observed[1:]))
    if habit_sample_days >= 18 and habit_sample_buckets >= 48 and span_hours >= 24 and changes >= 3:
        confidence = "high"
    elif habit_sample_days >= 7 and habit_sample_buckets >= 20 and changes >= 2:
        confidence = "medium"
    elif span_hours >= 48 and changes >= 5:
        confidence = "high"
    elif span_hours >= 24 and changes >= 3:
        confidence = "medium"
    else:
        confidence = "low"

    display_points = [(start_at, 0.0)]
    for item in observed:
        if item[1] != display_points[-1][1]:
            display_points.append(item)
    if not display_points or display_points[-1][0] != now_at or display_points[-1][1] != current_used:
        display_points.append((now_at, current_used))
    if len(display_points) > 48:
        last = len(display_points) - 1
        indices = sorted(set(round(index * last / 47) for index in range(48)))
        display_points = [display_points[index] for index in indices]

    usable_habit = (
        isinstance(habit_weights, list)
        and len(habit_weights) == 168
        and any(isinstance(value, (int, float)) and value > 0 for value in habit_weights)
    )
    remaining_hours = max(0.0, (reset_at - now_at) / 3600)
    if usable_habit:
        weights = [max(0.0, float(value)) for value in habit_weights]
        elapsed_weight = max(
            habit_weight_between(start_at, now_at, weights, habit_offset_seconds),
            1 / 60,
        )
        base_habit_rate = current_used / elapsed_weight
        habit_rate = base_habit_rate
        if anchor is not None:
            coverage_hours = (now_at - anchor[0]) / 3600
            recent_habit_weight = habit_weight_between(
                anchor[0], now_at, weights, habit_offset_seconds
            )
            if coverage_hours >= 6 and recent_habit_weight >= 1:
                recent_rate = max(0.0, (current_used - anchor[1]) / recent_habit_weight)
                recent_cap = max(base_habit_rate * 2.5, base_habit_rate + 0.25)
                recent_rate = min(recent_rate, recent_cap)
                recent_weight = 0.35 * min(1.0, coverage_hours / 24)
                habit_rate = base_habit_rate * (1 - recent_weight) + recent_rate * recent_weight
        future_weight = habit_weight_between(now_at, reset_at, weights, habit_offset_seconds)
        projected_used = current_used + habit_rate * future_weight
        rate = max(0.0, projected_used - current_used) / remaining_hours if remaining_hours > 0 else 0.0
        exhaust_at = (
            habit_exhaust_at(
                now_at,
                reset_at,
                max(0.0, (100 - current_used) / habit_rate),
                weights,
                habit_offset_seconds,
            )
            if projected_used >= 100 and habit_rate > 0
            else None
        )
        model = "habit"
    else:
        elapsed_hours = max((now_at - start_at) / 3600, 1 / 60)
        base_rate = current_used / elapsed_hours
        rate = base_rate
        if anchor is not None:
            coverage_hours = (now_at - anchor[0]) / 3600
            if coverage_hours >= 6:
                recent_rate = max(0.0, (current_used - anchor[1]) / coverage_hours)
                recent_cap = max(base_rate * 2.5, base_rate + 0.25)
                recent_rate = min(recent_rate, recent_cap)
                recent_weight = 0.35 * min(1.0, coverage_hours / 24)
                rate = base_rate * (1 - recent_weight) + recent_rate * recent_weight
        projected_used = current_used + rate * remaining_hours
        exhaust_at = (
            now_at + max(0.0, (100 - current_used) / rate) * 3600
            if projected_used >= 100 and rate > 0
            else None
        )
        model = "elapsed"

    return {
        "rate": rate,
        "confidence": confidence,
        "spanHours": span_hours,
        "projectedUsed": projected_used,
        "exhaustAt": exhaust_at,
        "model": model,
        "points": [
            {"timestamp": float(timestamp), "used": float(used)}
            for timestamp, used in display_points
        ],
    }

def read_app_server_quota(timeout_seconds=8):
    codex_binary = next((path for path in codex_binary_candidates if path.is_file()), None)
    if codex_binary is None:
        return None
    try:
        proc = subprocess.Popen(
            [str(codex_binary), "app-server", "--analytics-default-enabled"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
    except Exception:
        return None

    def send(message):
        if proc.stdin is None:
            return
        proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        proc.stdin.flush()

    try:
        send({
            "method": "initialize",
            "id": 1,
            "params": {
                "clientInfo": {"name": "codex-battery", "version": "0.1.42"},
                "capabilities": {
                    "experimentalApi": True,
                    "optOutNotificationMethods": [
                        "thread/started",
                        "thread/status/changed",
                        "thread/tokenUsage/updated",
                        "app/list/updated",
                        "remoteControl/status/changed",
                    ],
                },
            },
        })
        deadline = time.monotonic() + timeout_seconds
        requested = False
        while time.monotonic() < deadline:
            if proc.stdout is None:
                break
            readable, _, _ = select.select([proc.stdout], [], [], max(0.1, deadline - time.monotonic()))
            if not readable:
                continue
            line = proc.stdout.readline()
            if not line:
                break
            try:
                message = json.loads(line)
            except Exception:
                continue
            if message.get("id") == 1 and not requested:
                send({"method": "initialized"})
                send({"method": "account/rateLimits/read", "id": 2, "params": None})
                requested = True
                continue
            if message.get("id") == 2:
                result = message.get("result") or {}
                by_id = result.get("rateLimitsByLimitId") or {}
                snapshot = by_id.get("codex") or result.get("rateLimits")
                if not snapshot:
                    return None
                five_hour, week = normalize_quota_windows(
                    snapshot.get("primary"),
                    snapshot.get("secondary"),
                )
                reset_credits = result.get("rateLimitResetCredits") or {}
                if not isinstance(reset_credits, dict):
                    reset_credits = {}
                return {
                    "timestamp": datetime.now(tz).isoformat(),
                    "planType": snapshot.get("planType"),
                    "limitId": snapshot.get("limitId"),
                    "limitName": snapshot.get("limitName"),
                    "quotaSource": "app_server",
                    "availableResetCredits": normalize_reset_credit_count(reset_credits),
                    "resetCreditExpirations": normalize_reset_credit_expirations(reset_credits),
                    "primaryUsed": five_hour.get("used") if five_hour else None,
                    "secondaryUsed": week.get("used") if week else None,
                    "primaryReset": five_hour.get("reset") if five_hour else None,
                    "secondaryReset": week.get("reset") if week else None,
                }
    except Exception:
        return None
    finally:
        try:
            if proc.stdin:
                proc.stdin.close()
        except Exception:
            pass
        try:
            proc.terminate()
            proc.wait(timeout=1)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
    return None

def empty_stats_out(snapshot):
    out = dict(snapshot)
    out.update({
        "ok": True,
        "title": None,
        "model": None,
        "effort": None,
        "serviceTier": read_service_tier(),
        "totalTokens": None,
        "todayTokens": 0,
        "weeklyTrendRatePctPerHour": None,
        "weeklyTrendConfidence": "low",
        "weeklyTrendSpanHours": 0.0,
        "weeklyTrendPoints": [],
        "weeklyTrendProjectedUsed": None,
        "weeklyTrendExhaustAt": None,
        "weeklyTrendModel": None,
        "weeklyHabitWeights": [],
        "weeklyHabitTimeZoneOffsetSeconds": int(tz.utcoffset(None).total_seconds()),
        "weeklyHabitSampleDays": 0,
        "weeklyHabitSampleBuckets": 0,
        "topThread": None,
        "topThreadTokens": None,
        "activeThreads": 0,
        "activeWindowSeconds": ACTIVE_WINDOW_SECONDS,
    })
    return out

def read_activity_probe():
    try:
        if not db_path.exists():
            return {"ok": False, "error": "No Codex state database found"}
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=1.0)
        rows = con.execute(
            """
            SELECT id, rollout_path, updated_at, updated_at_ms
            FROM threads
            WHERE rollout_path IS NOT NULL
            ORDER BY updated_at DESC
            LIMIT 20
            """
        ).fetchall()
        active = set()
        latest_source_at = 0.0
        cutoff_dt = now - timedelta(seconds=ACTIVE_WINDOW_SECONDS)
        cutoff_epoch = cutoff_dt.timestamp()
        for thread_id, rollout_path, updated_at, updated_at_ms in rows:
            try:
                if updated_at:
                    latest_source_at = max(latest_source_at, float(updated_at))
            except Exception:
                pass
            try:
                if updated_at_ms:
                    latest_source_at = max(latest_source_at, float(updated_at_ms) / 1000)
            except Exception:
                pass
            if updated_at and float(updated_at) >= cutoff_epoch:
                active.add(thread_id)
                continue
            if updated_at_ms and float(updated_at_ms) / 1000 >= cutoff_epoch:
                active.add(thread_id)
                continue
            path = pathlib.Path(rollout_path)
            if not path.exists():
                continue
            try:
                stat_mtime = path.stat().st_mtime
                latest_source_at = max(latest_source_at, stat_mtime)
                if stat_mtime >= cutoff_epoch:
                    active.add(thread_id)
                    continue
            except Exception:
                pass
            scanned = 0
            for line in reversed_lines(path):
                scanned += 1
                if scanned > 200:
                    break
                if '"token_count"' not in line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                payload = obj.get("payload") or {}
                if payload.get("type") != "token_count":
                    continue
                ts = parse_ts(obj.get("timestamp"))
                if not ts:
                    continue
                latest_source_at = max(latest_source_at, ts.timestamp())
                if ts >= cutoff_dt:
                    active.add(thread_id)
                break
        source_updated_at = datetime.fromtimestamp(latest_source_at, tz).isoformat() if latest_source_at > 0 else None
        return {
            "ok": True,
            "timestamp": datetime.now(tz).isoformat(),
            "sourceUpdatedAt": source_updated_at,
            "activeThreads": len(active),
            "activeWindowSeconds": ACTIVE_WINDOW_SECONDS,
        }
    except Exception as exc:
        return {"ok": False, "error": str(exc)}

if len(sys.argv) > 1 and sys.argv[1] == "--activity-probe":
    print(json.dumps(read_activity_probe(), ensure_ascii=False))
    raise SystemExit(0)

details_only = len(sys.argv) > 1 and sys.argv[1] == "--details-only"
app_server_snapshot = None if details_only else read_app_server_quota()

if len(sys.argv) > 1 and sys.argv[1] == "--quota-only":
    if app_server_snapshot:
        print(json.dumps(empty_stats_out(app_server_snapshot), ensure_ascii=False))
        raise SystemExit(0)
    fail("Cannot read live Codex quota")

if not db_path.exists():
    if app_server_snapshot:
        print(json.dumps(empty_stats_out(app_server_snapshot), ensure_ascii=False))
        raise SystemExit(0)
    fail("No Codex state database found")

last_db_error = None
rows = None
thread_activity_endpoints = []
for attempt in range(6):
    try:
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=2.0)
        raw_rows = con.execute(
            """
            SELECT id, rollout_path, title, model, reasoning_effort, created_at, updated_at
            FROM threads
            WHERE rollout_path IS NOT NULL
              AND updated_at >= ?
            ORDER BY updated_at DESC
            LIMIT 400
            """,
            ((now - timedelta(days=35)).timestamp(),),
        ).fetchall()
        thread_activity_endpoints = [
            timestamp
            for row in raw_rows
            for timestamp in (row[5], row[6])
            if timestamp is not None
        ]

        latest_rows = raw_rows[:20]
        rows = [tuple(row[:5]) + (1200,) for row in latest_rows]
        selected_ids = {row[0] for row in latest_rows}
        per_day = Counter()
        for row in latest_rows:
            try:
                per_day[datetime.fromtimestamp(float(row[6]), tz).date()] += 1
            except (TypeError, ValueError, OverflowError):
                pass
        for row in raw_rows[20:]:
            if row[0] in selected_ids:
                continue
            try:
                day = datetime.fromtimestamp(float(row[6]), tz).date()
            except (TypeError, ValueError, OverflowError):
                continue
            if per_day[day] >= 2:
                continue
            per_day[day] += 1
            selected_ids.add(row[0])
            rows.append(tuple(row[:5]) + (160,))
        break
    except Exception as exc:
        last_db_error = exc
        time.sleep(0.15 * (attempt + 1))

if rows is None:
    fail(f"Cannot read Codex state after retry: {last_db_error}")

latest = None
daily = defaultdict(Counter)
top_by_thread = defaultdict(Counter)
weekly_points = []
rate_snapshots = []
active_thread_ids = set()
activity_buckets = set()
activity_cutoff = (now - timedelta(days=35)).timestamp()
for raw_timestamp in thread_activity_endpoints:
    try:
        timestamp = float(raw_timestamp)
    except (TypeError, ValueError):
        continue
    if timestamp >= activity_cutoff:
        activity_buckets.add(int(timestamp // 900) * 900)
thread_names = load_thread_names(session_index_path)

for thread_id, rollout_path, title, model, effort, scan_limit in rows:
    if not rollout_path:
        continue
    path = pathlib.Path(rollout_path)
    if not path.exists():
        continue
    display_title = thread_names.get(thread_id) or title
    try:
        if path.stat().st_mtime >= (now - timedelta(seconds=ACTIVE_WINDOW_SECONDS)).timestamp():
            active_thread_ids.add(thread_id)
    except Exception:
        pass
    events = []
    try:
        for line in read_recent_json(path, max_lines=scan_limit):
            try:
                obj = json.loads(line)
            except Exception:
                continue
            payload = obj.get("payload") or {}
            if payload.get("type") != "token_count":
                continue
            ts = parse_ts(obj.get("timestamp"))
            if not ts:
                continue
            if ts.timestamp() >= activity_cutoff:
                activity_buckets.add(int(ts.timestamp() // 900) * 900)
            if ts >= now - timedelta(seconds=ACTIVE_WINDOW_SECONDS):
                active_thread_ids.add(thread_id)
            rate_limits = payload.get("rate_limits")
            info = payload.get("info") or {}
            total = info.get("total_token_usage") or {}
            if "total_tokens" not in total:
                continue
            events.append((ts, obj, rate_limits, total))
        events.sort(key=lambda item: item[0])
        prev = None
        seen = set()
        for ts, obj, rate_limits, total in events:
            state = tuple(int(total.get(k, 0) or 0) for k in ("input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"))
            if state in seen:
                continue
            seen.add(state)
            if rate_limits:
                five_hour, week = normalize_quota_windows(
                    rate_limits.get("primary"),
                    rate_limits.get("secondary"),
                )
                rate_snapshots.append({
                    "ts": ts,
                    "timestamp": obj.get("timestamp"),
                    "planType": rate_limits.get("plan_type"),
                    "limitId": rate_limits.get("limit_id"),
                    "limitName": rate_limits.get("limit_name"),
                    "quotaSource": "rollout",
                    "primaryUsed": five_hour.get("used") if five_hour else None,
                    "secondaryUsed": week.get("used") if week else None,
                    "primaryReset": five_hour.get("reset") if five_hour else None,
                    "secondaryReset": week.get("reset") if week else None,
                    "title": display_title,
                    "model": model,
                    "effort": effort,
                    "totalTokens": total.get("total_tokens")
                })
                used = week.get("used") if week else None
                # Codex may emit additional model-specific quota windows
                # (for example codex_bengalfox) whose reset time is not the
                # main "Remaining quota" window shown in the Codex UI. Keep
                # weekly trend math anchored to the official aggregate window.
                week_reset = week.get("reset") if week else None
                if used is not None and week_reset is not None and rate_limits.get("limit_id") == "codex":
                    weekly_points.append((ts, float(used), float(week_reset)))
                if latest is None or ts > latest["ts"]:
                    latest = {
                        "ts": ts,
                        "timestamp": obj.get("timestamp"),
                        "planType": rate_limits.get("plan_type"),
                        "limitId": rate_limits.get("limit_id"),
                        "limitName": rate_limits.get("limit_name"),
                        "quotaSource": "rollout",
                        "primaryUsed": five_hour.get("used") if five_hour else None,
                        "secondaryUsed": week.get("used") if week else None,
                        "primaryReset": five_hour.get("reset") if five_hour else None,
                        "secondaryReset": week.get("reset") if week else None,
                        "title": display_title,
                        "model": model,
                        "effort": effort,
                        "totalTokens": total.get("total_tokens")
                    }
            if prev is None:
                diff = int(total.get("total_tokens", 0) or 0)
            else:
                diff = max(0, int(total.get("total_tokens", 0) or 0) - int(prev.get("total_tokens", 0) or 0))
            prev = total
            if diff <= 0:
                continue
            day = ts.date()
            if day >= today - timedelta(days=10):
                daily[day]["total_tokens"] += diff
                daily[day]["turns"] += 1
                label = compact_title(display_title)
                top_by_thread[(day, label)]["total_tokens"] += diff
                top_by_thread[(day, label)]["turns"] += 1
    except Exception:
        continue

if not latest:
    if app_server_snapshot:
        print(json.dumps(empty_stats_out(app_server_snapshot), ensure_ascii=False))
        raise SystemExit(0)
    fail("No recent Codex rate-limit data found")

# Prefer the aggregate Codex quota window. Some model-specific windows report
# their own 0% used / now+5h reset values and should not drive the menu.
official_snapshots = [
    snap for snap in rate_snapshots
    if snap.get("limitId") == "codex"
]
if official_snapshots:
    latest = max(official_snapshots, key=lambda snap: snap["ts"])

# Multiple active Codex threads can write rate-limit snapshots with the same
# reset window but stale used_percent values. Within one reset window usage
# should be monotonic, so prefer the highest recent value over a lower snapshot
# that merely has a newer timestamp.
fresh_cutoff = now - timedelta(minutes=15)
same_limit = [
    snap for snap in rate_snapshots
    if snap["ts"] >= fresh_cutoff
    and snap.get("planType") == latest.get("planType")
    and snap.get("limitId") == latest.get("limitId")
]
prefer_monotonic_quota_values(latest, same_limit)

if app_server_snapshot:
    latest.update({
        "timestamp": app_server_snapshot.get("timestamp"),
        "planType": app_server_snapshot.get("planType"),
        "limitId": app_server_snapshot.get("limitId"),
        "limitName": app_server_snapshot.get("limitName"),
        "quotaSource": app_server_snapshot.get("quotaSource"),
        "primaryUsed": app_server_snapshot.get("primaryUsed"),
        "secondaryUsed": app_server_snapshot.get("secondaryUsed"),
        "primaryReset": app_server_snapshot.get("primaryReset"),
        "secondaryReset": app_server_snapshot.get("secondaryReset"),
    })

today_tokens = int(daily[today]["total_tokens"])

today_threads = [
    (label, int(counter["total_tokens"]))
    for (day, label), counter in top_by_thread.items()
    if day == today
]
today_threads.sort(key=lambda item: item[1], reverse=True)
top_thread, top_thread_tokens = today_threads[0] if today_threads else (None, None)

weekly_points.sort(key=lambda item: item[0])
reset_at = latest.get("secondaryReset")
used_week = latest.get("secondaryUsed")
try:
    weekly_start_at = float(reset_at) - 7 * 24 * 3600
except (TypeError, ValueError):
    weekly_start_at = None
habit_profile = build_habit_profile(activity_buckets, weekly_start_at)
weekly_trend = build_weekly_trend(
    weekly_points,
    reset_at,
    now.timestamp(),
    used_week,
    habit_weights=habit_profile.get("weights"),
    habit_offset_seconds=habit_profile.get("timeZoneOffsetSeconds", 0),
    habit_sample_days=habit_profile.get("sampleDays", 0),
    habit_sample_buckets=habit_profile.get("sampleBuckets", 0),
)

out = dict(latest)
out.pop("ts", None)
out.update({
    "ok": True,
    "todayTokens": today_tokens,
    "serviceTier": read_service_tier(),
    "weeklyTrendRatePctPerHour": weekly_trend.get("rate"),
    "weeklyTrendConfidence": weekly_trend.get("confidence"),
    "weeklyTrendSpanHours": weekly_trend.get("spanHours"),
    "weeklyTrendPoints": weekly_trend.get("points"),
    "weeklyTrendProjectedUsed": weekly_trend.get("projectedUsed"),
    "weeklyTrendExhaustAt": weekly_trend.get("exhaustAt"),
    "weeklyTrendModel": weekly_trend.get("model"),
    "weeklyHabitWeights": habit_profile.get("weights"),
    "weeklyHabitTimeZoneOffsetSeconds": habit_profile.get("timeZoneOffsetSeconds"),
    "weeklyHabitSampleDays": habit_profile.get("sampleDays"),
    "weeklyHabitSampleBuckets": habit_profile.get("sampleBuckets"),
    "topThread": top_thread,
    "topThreadTokens": top_thread_tokens,
    "activeThreads": len(active_thread_ids),
    "activeWindowSeconds": ACTIVE_WINDOW_SECONDS
})
print(json.dumps(out, ensure_ascii=False))
raise SystemExit(0)

for thread_id, rollout_path, title, model, effort in []:
    if not rollout_path:
        continue
    path = pathlib.Path(rollout_path)
    if not path.exists():
        continue
    try:
        for line in reversed_lines(path):
            try:
                obj = json.loads(line)
            except Exception:
                continue
            payload = obj.get("payload") or {}
            if payload.get("type") != "token_count":
                continue
            rate_limits = payload.get("rate_limits")
            info = payload.get("info") or {}
            if not rate_limits:
                continue
            five_hour, week = normalize_quota_windows(
                rate_limits.get("primary"),
                rate_limits.get("secondary"),
            )
            total = info.get("total_token_usage") or {}
            print(json.dumps({
                "ok": True,
                "timestamp": obj.get("timestamp"),
                "planType": rate_limits.get("plan_type"),
                "limitId": rate_limits.get("limit_id"),
                "limitName": rate_limits.get("limit_name"),
                "primaryUsed": five_hour.get("used") if five_hour else None,
                "secondaryUsed": week.get("used") if week else None,
                "primaryReset": five_hour.get("reset") if five_hour else None,
                "secondaryReset": week.get("reset") if week else None,
                "title": title,
                "model": model,
                "effort": effort,
                "totalTokens": total.get("total_tokens")
            }, ensure_ascii=False))
            raise SystemExit(0)
    except SystemExit:
        raise
    except Exception:
        continue

fail("No recent Codex rate-limit data found")
"""#

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
