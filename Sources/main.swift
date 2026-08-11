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
    let projectedLowUsed: Double?
    let projectedHighUsed: Double?
    let exhaustAt: Double?
    let todayUsed: Double?
    let todayBaselineUsed: Double?
    let todayBaselineDayStart: Double?
    let cycleAveragePctPerDay: Double?
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
        habitSampleBuckets: Int? = nil,
        historicalRatePctPerHabitHour: Double? = nil,
        historicalLowRatePctPerHabitHour: Double? = nil,
        historicalHighRatePctPerHabitHour: Double? = nil,
        historicalSampleCycles: Int? = nil,
        todayBaselineUsed: Double? = nil,
        todayBaselineDayStart: Double? = nil
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
        let paceCycles = max(0, historicalSampleCycles ?? 0)
        let confidence: String
        if paceCycles >= 4, spanHours >= 48, changes >= 5 {
            confidence = "high"
        } else if paceCycles >= 3, spanHours >= 24, changes >= 3 {
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

        let usableHistoricalRate = historicalRatePctPerHabitHour.flatMap {
            $0.isFinite && $0 > 0 && paceCycles >= 2 ? $0 : nil
        }
        let usableHistoricalLowRate = historicalLowRatePctPerHabitHour.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }
        let usableHistoricalHighRate = historicalHighRatePctPerHabitHour.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }

        let rate: Double
        let projectedUsed: Double
        let projectedLowUsed: Double
        let projectedHighUsed: Double
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
            var habitRate = usableHistoricalRate ?? baseHabitRate
            var lowHabitRate = min(
                usableHistoricalLowRate ?? habitRate,
                usableHistoricalHighRate ?? habitRate
            )
            var highHabitRate = max(
                usableHistoricalLowRate ?? habitRate,
                usableHistoricalHighRate ?? habitRate
            )
            if let anchor {
                let coverageHours = (nowAt - anchor.timestamp) / 3600
                let recentHabitWeight = habitWeight(
                    from: anchor.timestamp,
                    to: nowAt,
                    weights: weights,
                    timeZoneOffsetSeconds: offsetSeconds
                )
                if coverageHours >= 12, recentHabitWeight >= 1 {
                    var recentRate = max(0, (clampedUsed - anchor.used) / recentHabitWeight)
                    let referenceRate = usableHistoricalRate ?? baseHabitRate
                    let referenceHigh = max(highHabitRate, referenceRate)
                    let recentCap = max(referenceHigh * 2, referenceRate + 0.5)
                    recentRate = min(recentRate, recentCap)
                    let recentWeight: Double
                    if usableHistoricalRate != nil {
                        recentWeight = min(0.45, 0.15 + 0.30 * min(1, max(0, spanHours - 12) / 36))
                    } else {
                        recentWeight = 0.35 * min(1, coverageHours / 24)
                    }
                    habitRate = habitRate * (1 - recentWeight) + recentRate * recentWeight
                    lowHabitRate = lowHabitRate * (1 - recentWeight) + recentRate * recentWeight
                    highHabitRate = highHabitRate * (1 - recentWeight) + recentRate * recentWeight
                }
            }
            let futureWeight = habitWeight(
                from: nowAt,
                to: resetAt,
                weights: weights,
                timeZoneOffsetSeconds: offsetSeconds
            )
            projectedUsed = clampedUsed + habitRate * futureWeight
            projectedLowUsed = clampedUsed + min(lowHabitRate, highHabitRate) * futureWeight
            projectedHighUsed = clampedUsed + max(lowHabitRate, highHabitRate) * futureWeight
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
            model = usableHistoricalRate == nil ? "habit" : "habit-history"
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
            projectedLowUsed = projectedUsed
            projectedHighUsed = projectedUsed
            exhaustAt = projectedUsed >= 100 && wallClockRate > 0
                ? nowAt + max(0, (100 - clampedUsed) / wallClockRate) * 3600
                : nil
            model = "elapsed"
        }

        let localDayStart = floor((nowAt + Double(offsetSeconds)) / 86_400) * 86_400 - Double(offsetSeconds)
        let usedAtDayStart: Double?
        if startAt >= localDayStart {
            usedAtDayStart = 0
        } else {
            usedAtDayStart = todayBaselineDayStart.flatMap { baselineDayStart in
                guard sameWindow, abs(baselineDayStart - localDayStart) <= 1 else { return nil }
                return todayBaselineUsed.flatMap {
                    $0.isFinite ? max(0, min(clampedUsed, $0)) : nil
                }
            }
        }
        let todayUsed = usedAtDayStart.map { max(0, clampedUsed - $0) }
        let elapsedDays = max(elapsedHours / 24, 1 / 24)
        let cycleAveragePctPerDay = clampedUsed / elapsedDays
        let paceIsBuilding = usableHistoricalRate == nil && (spanHours < 12 || changes < 3)

        return WeeklyTrendCalculation(
            rate: paceIsBuilding ? nil : rate,
            confidence: confidence,
            spanHours: spanHours,
            points: displayPoints,
            projectedUsed: paceIsBuilding ? nil : projectedUsed,
            projectedLowUsed: paceIsBuilding ? nil : projectedLowUsed,
            projectedHighUsed: paceIsBuilding ? nil : projectedHighUsed,
            exhaustAt: paceIsBuilding ? nil : exhaustAt,
            todayUsed: todayUsed,
            todayBaselineUsed: usedAtDayStart,
            todayBaselineDayStart: usedAtDayStart == nil ? nil : localDayStart,
            cycleAveragePctPerDay: cycleAveragePctPerDay,
            model: paceIsBuilding ? "building" : model
        )
    }

    private static func emptyCalculation() -> WeeklyTrendCalculation {
        WeeklyTrendCalculation(
            rate: nil,
            confidence: "low",
            spanHours: 0,
            points: [],
            projectedUsed: nil,
            projectedLowUsed: nil,
            projectedHighUsed: nil,
            exhaustAt: nil,
            todayUsed: nil,
            todayBaselineUsed: nil,
            todayBaselineDayStart: nil,
            cycleAveragePctPerDay: nil,
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

private struct ResetCreditSnapshot {
    let count: Int?
    let expirations: [Int]?
    let isStale: Bool

    static func resolve(
        liveCount: Int?,
        liveExpirations: [Int]?,
        liveIsStale: Bool = false,
        cachedCount: Int?,
        cachedExpirations: [Int]?
    ) -> ResetCreditSnapshot {
        if let liveCount {
            return ResetCreditSnapshot(
                count: max(0, liveCount),
                expirations: liveCount == 0 ? [] : liveExpirations,
                isStale: liveIsStale
            )
        }
        if let cachedCount {
            return ResetCreditSnapshot(
                count: max(0, cachedCount),
                expirations: cachedExpirations,
                isStale: true
            )
        }
        return ResetCreditSnapshot(count: nil, expirations: nil, isStale: false)
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

private struct QuotaBurnPresentation {
    let value: String
    let detail: String
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
    let resetCreditsStale: Bool?
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
    let weeklyTrendProjectedLowUsed: Double?
    let weeklyTrendProjectedHighUsed: Double?
    let weeklyTrendExhaustAt: Double?
    let weeklyTrendModel: String?
    let weeklyTodayUsed: Double?
    let weeklyTodayBaselineUsed: Double?
    let weeklyTodayBaselineDayStart: Double?
    let weeklyCycleAveragePctPerDay: Double?
    let weeklyHabitWeights: [Double]?
    let weeklyHabitTimeZoneOffsetSeconds: Int?
    let weeklyHabitSampleDays: Int?
    let weeklyHabitSampleBuckets: Int?
    let weeklyHistoricalRatePctPerHabitHour: Double?
    let weeklyHistoricalLowRatePctPerHabitHour: Double?
    let weeklyHistoricalHighRatePctPerHabitHour: Double?
    let weeklyHistoricalSampleCycles: Int?
    let topThread: String?
    let topThreadTokens: Int?
    let activeThreads: Int?
    let activeWindowSeconds: Int?

    func replacingQuota(
        with quota: QuotaInfo,
        cachedQuota: QuotaInfo? = nil,
        activeThreads: Int,
        activeWindowSeconds: Int
    ) -> QuotaInfo {
        let resetCreditCache = cachedQuota ?? self
        let resetCredits = ResetCreditSnapshot.resolve(
            liveCount: quota.availableResetCredits,
            liveExpirations: quota.resetCreditExpirations,
            liveIsStale: quota.resetCreditsStale == true,
            cachedCount: resetCreditCache.availableResetCredits,
            cachedExpirations: resetCreditCache.resetCreditExpirations
        )
        let mergedTrend = WeeklyTrendCalculator.merge(
            points: weeklyTrendPoints ?? [],
            sourceReset: secondaryReset,
            targetReset: quota.secondaryReset,
            timestamp: quota.timestamp,
            currentUsed: quota.secondaryUsed,
            habitWeights: weeklyHabitWeights,
            habitTimeZoneOffsetSeconds: weeklyHabitTimeZoneOffsetSeconds,
            habitSampleDays: weeklyHabitSampleDays,
            habitSampleBuckets: weeklyHabitSampleBuckets,
            historicalRatePctPerHabitHour: weeklyHistoricalRatePctPerHabitHour,
            historicalLowRatePctPerHabitHour: weeklyHistoricalLowRatePctPerHabitHour,
            historicalHighRatePctPerHabitHour: weeklyHistoricalHighRatePctPerHabitHour,
            historicalSampleCycles: weeklyHistoricalSampleCycles,
            todayBaselineUsed: weeklyTodayBaselineUsed,
            todayBaselineDayStart: weeklyTodayBaselineDayStart
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
            availableResetCredits: resetCredits.count,
            resetCreditExpirations: resetCredits.expirations,
            resetCreditsStale: resetCredits.isStale,
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
            weeklyTrendProjectedLowUsed: mergedTrend.projectedLowUsed,
            weeklyTrendProjectedHighUsed: mergedTrend.projectedHighUsed,
            weeklyTrendExhaustAt: mergedTrend.exhaustAt,
            weeklyTrendModel: mergedTrend.model,
            weeklyTodayUsed: mergedTrend.todayUsed,
            weeklyTodayBaselineUsed: mergedTrend.todayBaselineUsed,
            weeklyTodayBaselineDayStart: mergedTrend.todayBaselineDayStart,
            weeklyCycleAveragePctPerDay: mergedTrend.cycleAveragePctPerDay,
            weeklyHabitWeights: weeklyHabitWeights,
            weeklyHabitTimeZoneOffsetSeconds: weeklyHabitTimeZoneOffsetSeconds,
            weeklyHabitSampleDays: weeklyHabitSampleDays,
            weeklyHabitSampleBuckets: weeklyHabitSampleBuckets,
            weeklyHistoricalRatePctPerHabitHour: weeklyHistoricalRatePctPerHabitHour,
            weeklyHistoricalLowRatePctPerHabitHour: weeklyHistoricalLowRatePctPerHabitHour,
            weeklyHistoricalHighRatePctPerHabitHour: weeklyHistoricalHighRatePctPerHabitHour,
            weeklyHistoricalSampleCycles: weeklyHistoricalSampleCycles,
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
    private let quotaBurnItem = NSMenuItem(title: "Quota burn -", action: nil, keyEquivalent: "")
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
        menu.addItem(quotaBurnItem)
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
            setInfoItem(quotaBurnItem, label: t("额度油耗", "Quota burn"), value: "-")
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
                            cachedQuota: self.lastGoodInfo,
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
                        cachedQuota: cached,
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
            quotaBurnItem.isHidden = true
            forecastItem.isHidden = false
            setInfoItem(fiveHourItem, label: t("错误", "Error"), value: message)
            setResetCreditsItem(count: nil, expirations: [])
            setInfoItem(todayItem, label: t("今日消耗", "Today burn"), value: "-")
            setInfoItem(quotaBurnItem, label: t("额度油耗", "Quota burn"), value: "-")
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
        let quotaBurn = makeQuotaBurnPresentation(info)
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
        var resetCreditsDetail = nearestCreditExpiry.map {
            useChinese ? "可用重置: \(resetCredits)  最近 \($0) 到期" : "Resets available: \(resetCredits)  Nearest expires \($0)"
        } ?? (useChinese ? "可用重置: \(resetCredits)" : "Resets available: \(resetCredits)")
        if info.resetCreditsStale == true {
            resetCreditsDetail += t("  旧数据", "  cached")
        }
        detailLines.append(resetCreditsDetail)
        detailLines.append(useChinese ? "今日: \(today)" : "Today: \(today)")
        detailLines.append(useChinese
            ? "额度油耗: \(quotaBurn.value)  \(quotaBurn.detail)"
            : "Quota burn: \(quotaBurn.value)  \(quotaBurn.detail)")
        detailLines.append(useChinese ? "周预测: \(weeklyForecast.summary)  \(weeklyForecast.confidence)" : "Weekly forecast: \(weeklyForecast.summary)  \(weeklyForecast.confidence)")
        detailLines.append("Top: \(topThread)  \(topThreadTokens)")
        detailLines.append(useChinese ? "后台活动: \(activity)" : "Activity: \(activity)")
        detailLines.append(useChinese ? "数据于: \(dataAt)" : "Data at: \(dataAt)")
        let detail = detailLines.joined(separator: "\n")

        fiveHourItem.isHidden = fiveHour == nil
        weekItem.isHidden = week == nil
        quotaBurnItem.isHidden = week == nil
        forecastItem.isHidden = week == nil
        if let fiveHour {
            setInfoItem(fiveHourItem, label: t("5小时剩余", "5h left"), value: "\(fiveHour)%", detail: primaryReset)
        }
        if let week {
            setInfoItem(weekItem, label: t("1周剩余", "1w left"), value: "\(week)%", detail: secondaryReset)
        }
        setResetCreditsItem(
            count: availableResetCredits,
            expirations: resetCreditExpirations,
            isStale: info.resetCreditsStale == true
        )
        setInfoItem(todayItem, label: t("今日消耗", "Today burn"), value: today)
        setQuotaBurnItem(quotaBurnItem, presentation: quotaBurn)
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

    private func makeQuotaBurnPresentation(_ info: QuotaInfo) -> QuotaBurnPresentation {
        let todayText = info.weeklyTodayUsed.map {
            t("今日约 \(formatQuotaPercent($0))", "today ~\(formatQuotaPercent($0))")
        } ?? t("今日 -", "today -")
        let cycleUsed = info.secondaryUsed.map(formatQuotaPercent) ?? "-"
        let sampleCycles = max(0, info.weeklyHistoricalSampleCycles ?? 0)
        let typicalPerDay = info.weeklyHistoricalRatePctPerHabitHour.flatMap {
            $0.isFinite && $0 > 0 && sampleCycles >= 2 ? $0 * 24 : nil
        }
        let detailText = typicalPerDay.map {
            t(
                "本期\(cycleUsed) · 常态\(formatQuotaPercent($0))/日",
                "cycle \(cycleUsed) · typical \(formatQuotaPercent($0))/d"
            )
        } ?? t("本期 \(cycleUsed)", "cycle \(cycleUsed)")

        let cycleAverage = info.weeklyCycleAveragePctPerDay.flatMap {
            $0.isFinite && $0 >= 0 ? $0 : nil
        }
        let cycleAverageText = cycleAverage.map {
            t("当前周期折合 \(formatQuotaPercent($0))/日", "current cycle averages \(formatQuotaPercent($0))/day")
        } ?? t("当前周期均耗暂不可用", "current cycle average unavailable")
        let typicalText = typicalPerDay.map {
            t(
                "历史常态约 \(formatQuotaPercent($0))/日，取 \(sampleCycles) 个可用周期的稳健中位数，优先采用持续至少 3 天的周期。",
                "Historical typical burn is about \(formatQuotaPercent($0))/day, the robust median of \(sampleCycles) usable cycles, preferring cycles lasting at least three days."
            )
        } ?? t("历史周期样本仍在积累。", "Historical cycle samples are still building.")
        let tooltip = t(
            "\(todayText)；本周期累计 \(cycleUsed)，\(cycleAverageText)；均匀预算为 14.3%/日。\(typicalText) Token 与额度百分比不做换算。",
            "\(todayText); \(cycleUsed) used this cycle, \(cycleAverageText); the even budget is 14.3%/day. \(typicalText) Token volume is not converted into quota percentage."
        )
        return QuotaBurnPresentation(value: todayText, detail: detailText, tooltip: tooltip)
    }

    private func setQuotaBurnItem(_ item: NSMenuItem, presentation: QuotaBurnPresentation) {
        setInfoItem(
            item,
            label: t("额度油耗", "Quota burn"),
            value: presentation.value,
            detail: presentation.detail
        )
        item.view?.toolTip = presentation.tooltip
        item.view?.subviews.forEach { $0.toolTip = presentation.tooltip }
    }

    private func formatQuotaPercent(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return String(format: "%.0f%%", rounded)
        }
        return String(format: "%.1f%%", value)
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
        let paceCycles = max(0, info.weeklyHistoricalSampleCycles ?? 0)
        let usesHistoryModel = info.weeklyTrendModel == "habit-history" && paceCycles >= 2
        let usesHabitModel = (info.weeklyTrendModel == "habit" || usesHistoryModel) && habitDays > 0
        let confidence: String
        if usesHistoryModel {
            let shortConfidence: String
            switch info.weeklyTrendConfidence {
            case "high": shortConfidence = t("高", "high")
            case "medium": shortConfidence = t("中", "med")
            default: shortConfidence = t("低", "low")
            }
            confidence = t(
                "\(shortConfidence) · 常态\(paceCycles)期",
                "\(shortConfidence) · \(paceCycles) cycles"
            )
        } else if usesHabitModel {
            let shortConfidence = info.weeklyTrendConfidence == "high"
                ? t("高", "high")
                : (info.weeklyTrendConfidence == "medium" ? t("中", "med") : t("低", "low"))
            confidence = t("\(shortConfidence) · 历史\(habitDays)d", "\(shortConfidence) · \(habitDays)d")
        } else {
            confidence = spanHours > 0 ? "\(confidenceName) · \(spanText)" : confidenceName
        }
        let habitHint = usesHistoryModel
            ? t(
                "未来速度以历史常态周期的稳健中位数为基线，短期重置冲量会被降权；本周期持续变化后才逐步接管预测。活跃时段仍按近 \(habitDays) 天作息分配。",
                "Future pace starts from the robust median of typical historical cycles, down-weighting short reset sprints; the current cycle takes over only after sustained evidence. Active hours still follow the last \(habitDays) days."
            )
            : (usesHabitModel
            ? t(
                "预测按近 \(habitDays) 天本机活跃时段加权，夜间和历史空闲时段不会沿用白天速率。",
                "The forecast weights the last \(habitDays) days of local active hours, so nights and historically idle periods do not continue the daytime rate."
            )
            : "")

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
        let projectedLowUsed = info.weeklyTrendProjectedLowUsed.flatMap { $0.isFinite ? $0 : nil }
            ?? projectedUsed
        let projectedHighUsed = info.weeklyTrendProjectedHighUsed.flatMap { $0.isFinite ? $0 : nil }
            ?? projectedUsed
        let lowerProjection = min(projectedLowUsed, projectedHighUsed)
        let upperProjection = max(projectedLowUsed, projectedHighUsed)
        let rangeCrossesExhaustion = lowerProjection < 100 && upperProjection >= 100
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
            if rangeCrossesExhaustion {
                summary = t("存在提前用完风险", "Risk of running out early")
            } else if lowerProjection >= 100, info.weeklyTrendConfidence == "low" {
                summary = t("按常态可能提前用完", "Typical pace may run out early")
            } else {
                summary = t("预计提前 \(earlyText) 用完", "Runs out \(earlyText) early")
            }
            let exhaustProgress = min(1, max(0, exhaustAt.timeIntervalSince(startAt) / weekSeconds))
            forecastPoint = CGPoint(x: exhaustProgress, y: 1)
            tone = (rangeCrossesExhaustion || info.weeklyTrendConfidence == "low") ? .systemOrange : .systemRed
        } else {
            let projectedRemaining = max(0, 100 - projectedUsed)
            if rangeCrossesExhaustion {
                summary = t("预计可撑到重置 · 有波动", "Likely lasts · variable")
            } else {
                summary = t(
                    "预计重置时剩 \(Int(round(projectedRemaining)))%",
                    "\(Int(round(projectedRemaining)))% left at reset"
                )
            }
            forecastPoint = CGPoint(x: 1, y: CGFloat(projectedUsed / 100))
            tone = (rangeCrossesExhaustion || projectedRemaining < 15) ? .systemOrange : .systemGreen
        }
        let markerHint = resetCreditMarker.map {
            t("，竖线标记\($0.label)", "; vertical marker: \($0.label)")
        } ?? ""
        let rangeHint = rangeCrossesExhaustion
            ? t("稳健区间跨过 100% 用完线，因此当前只提示风险，不给确定的提前天数。", "The robust range crosses the 100% exhaustion line, so this is shown as a risk rather than a certain early date.")
            : ""
        let tooltip = t(
            "\(summary)，\(confidence)。\(habitHint)\(rangeHint)实线为实际消耗，彩色虚线为典型预测，灰线为均匀预算\(markerHint)。",
            "\(summary), \(confidence). \(habitHint) \(rangeHint) Solid is actual usage, colored dash is the typical projection, gray is the even-budget line\(markerHint)."
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

    private func setResetCreditsItem(count: Int?, expirations: [Date], isStale: Bool = false) {
        resetCreditsItem.view = nil
        resetCreditsItem.isHidden = false
        resetCreditsItem.isEnabled = true

        let countText = count.map(String.init) ?? "-"
        let staleSuffix = isStale ? t(" · 旧数据", " · cached") : ""
        if let nearest = expirations.first {
            resetCreditsItem.title = t(
                "可用重置：\(countText) 次 · 最近 \(formatResetCreditExpiry(nearest)) 到期\(staleSuffix)",
                "Resets available: \(countText) · nearest expires \(formatResetCreditExpiry(nearest))\(staleSuffix)"
            )
        } else {
            resetCreditsItem.title = t(
                "可用重置：\(countText) 次\(staleSuffix)",
                "Resets available: \(countText)\(staleSuffix)"
            )
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
                resetCreditsStale: nil,
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
                weeklyTrendProjectedLowUsed: nil,
                weeklyTrendProjectedHighUsed: nil,
                weeklyTrendExhaustAt: nil,
                weeklyTrendModel: nil,
                weeklyTodayUsed: nil,
                weeklyTodayBaselineUsed: nil,
                weeklyTodayBaselineDayStart: nil,
                weeklyCycleAveragePctPerDay: nil,
                weeklyHabitWeights: nil,
                weeklyHabitTimeZoneOffsetSeconds: nil,
                weeklyHabitSampleDays: nil,
                weeklyHabitSampleBuckets: nil,
                weeklyHistoricalRatePctPerHabitHour: nil,
                weeklyHistoricalLowRatePctPerHabitHour: nil,
                weeklyHistoricalHighRatePctPerHabitHour: nil,
                weeklyHistoricalSampleCycles: nil,
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

def quantile(values, fraction):
    ordered = sorted(float(value) for value in values)
    if not ordered:
        return None
    if len(ordered) == 1:
        return ordered[0]
    position = max(0.0, min(1.0, float(fraction))) * (len(ordered) - 1)
    lower = int(position)
    upper = min(len(ordered) - 1, lower + 1)
    blend = position - lower
    return ordered[lower] * (1 - blend) + ordered[upper] * blend

def build_historical_pace_profile(
    points,
    target_reset,
    now_at,
    habit_weights,
    habit_offset_seconds=0,
    minimum_cycle_hours=72,
):
    empty = {
        "rate": None,
        "lowRate": None,
        "highRate": None,
        "sampleCycles": 0,
        "excludedShortCycles": 0,
    }
    try:
        target_reset = float(target_reset)
        now_at = float(now_at)
    except (TypeError, ValueError):
        return empty
    if (
        not isinstance(habit_weights, list)
        or len(habit_weights) != 168
        or not any(isinstance(value, (int, float)) and value > 0 for value in habit_weights)
    ):
        return empty
    weights = [max(0.0, float(value)) for value in habit_weights]

    clusters = []
    cutoff = now_at - 35 * 24 * 3600
    for raw_timestamp, raw_used, raw_reset in points:
        try:
            timestamp = raw_timestamp.timestamp() if hasattr(raw_timestamp, "timestamp") else float(raw_timestamp)
            used = max(0.0, min(100.0, float(raw_used)))
            reset = float(raw_reset)
        except (TypeError, ValueError):
            continue
        if timestamp < cutoff - 24 * 3600 or timestamp > now_at + 300:
            continue
        cluster = next((item for item in clusters if abs(item["reset"] - reset) <= 300), None)
        if cluster is None:
            cluster = {"reset": reset, "points": []}
            clusters.append(cluster)
        cluster["points"].append((timestamp, used))

    if not any(abs(item["reset"] - target_reset) <= 300 for item in clusters):
        clusters.append({"reset": target_reset, "points": []})

    clusters.sort(key=lambda item: item["reset"])
    all_rates = []
    long_rates = []
    for index, cluster in enumerate(clusters):
        reset = cluster["reset"]
        if abs(reset - target_reset) <= 300:
            continue
        start_at = reset - 7 * 24 * 3600
        next_start = None
        if index + 1 < len(clusters):
            next_start = clusters[index + 1]["reset"] - 7 * 24 * 3600
        end_at = reset
        if next_start is not None and next_start > start_at:
            end_at = min(end_at, next_start)
        if end_at > now_at + 300 or end_at <= start_at:
            continue

        buckets = {}
        for timestamp, used in cluster["points"]:
            if timestamp < start_at - 300 or timestamp > end_at + 300:
                continue
            bucket = int(timestamp // 300) * 300
            buckets[bucket] = max(used, buckets.get(bucket, 0.0))
        if not buckets:
            continue
        last_observed_at = max(buckets)
        if end_at - last_observed_at > 18 * 3600:
            continue
        used = max(buckets.values())
        cycle_weight = habit_weight_between(
            start_at,
            end_at,
            weights,
            habit_offset_seconds,
        )
        if used <= 0 or cycle_weight < 2:
            continue
        rate = used / cycle_weight
        all_rates.append(rate)
        if (end_at - start_at) / 3600 >= minimum_cycle_hours:
            long_rates.append(rate)

    selected = long_rates if len(long_rates) >= 2 else []
    if not selected:
        return empty
    low_rate = quantile(selected, 0.25) if len(selected) >= 4 else min(selected)
    high_rate = quantile(selected, 0.75) if len(selected) >= 4 else max(selected)
    return {
        "rate": quantile(selected, 0.5),
        "lowRate": low_rate,
        "highRate": high_rate,
        "sampleCycles": len(selected),
        "excludedShortCycles": max(0, len(all_rates) - len(selected)),
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
    historical_rate=None,
    historical_low_rate=None,
    historical_high_rate=None,
    historical_sample_cycles=0,
):
    empty = {
        "rate": None,
        "confidence": "low",
        "spanHours": 0.0,
        "points": [],
        "projectedUsed": None,
        "projectedLowUsed": None,
        "projectedHighUsed": None,
        "exhaustAt": None,
        "todayUsed": None,
        "todayBaselineUsed": None,
        "todayBaselineDayStart": None,
        "cycleAveragePctPerDay": None,
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
    raw_observed = []
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
        raw_observed.append((timestamp, used))
        bucket = int(timestamp // 300) * 300
        buckets[bucket] = max(used, buckets.get(bucket, 0.0))

    observed = []
    highest = 0.0
    for timestamp, used in sorted(buckets.items()):
        highest = max(highest, used)
        observed.append((float(timestamp), highest))
    if not observed or observed[-1][0] != now_at or observed[-1][1] != current_used:
        observed.append((now_at, current_used))

    chart_source = [(start_at, 0.0)] + observed
    target = now_at - 24 * 3600
    earlier = [item for item in chart_source if item[0] <= target]
    anchor = earlier[-1] if earlier else (chart_source[0] if chart_source else None)

    span_hours = 0.0
    real_observed = [item for item in observed if item[0] > start_at + 300]
    if len(real_observed) >= 2:
        span_hours = max(0.0, (real_observed[-1][0] - real_observed[0][0]) / 3600)
    changes = sum(a[1] < b[1] for a, b in zip(real_observed, real_observed[1:]))
    try:
        pace_cycles = max(0, int(historical_sample_cycles or 0))
    except (TypeError, ValueError):
        pace_cycles = 0
    if pace_cycles >= 4 and span_hours >= 48 and changes >= 5:
        confidence = "high"
    elif pace_cycles >= 3 and span_hours >= 24 and changes >= 3:
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
    try:
        historical_rate = float(historical_rate)
    except (TypeError, ValueError):
        historical_rate = None
    try:
        historical_low_rate = float(historical_low_rate)
    except (TypeError, ValueError):
        historical_low_rate = None
    try:
        historical_high_rate = float(historical_high_rate)
    except (TypeError, ValueError):
        historical_high_rate = None
    usable_history = historical_rate is not None and historical_rate > 0 and pace_cycles >= 2
    remaining_hours = max(0.0, (reset_at - now_at) / 3600)
    if usable_habit:
        weights = [max(0.0, float(value)) for value in habit_weights]
        elapsed_weight = max(
            habit_weight_between(start_at, now_at, weights, habit_offset_seconds),
            1 / 60,
        )
        base_habit_rate = current_used / elapsed_weight
        habit_rate = historical_rate if usable_history else base_habit_rate
        low_habit_rate = min(
            historical_low_rate if historical_low_rate is not None and historical_low_rate > 0 else habit_rate,
            historical_high_rate if historical_high_rate is not None and historical_high_rate > 0 else habit_rate,
        )
        high_habit_rate = max(
            historical_low_rate if historical_low_rate is not None and historical_low_rate > 0 else habit_rate,
            historical_high_rate if historical_high_rate is not None and historical_high_rate > 0 else habit_rate,
        )
        if anchor is not None:
            coverage_hours = (now_at - anchor[0]) / 3600
            recent_habit_weight = habit_weight_between(
                anchor[0], now_at, weights, habit_offset_seconds
            )
            if coverage_hours >= 12 and recent_habit_weight >= 1:
                recent_rate = max(0.0, (current_used - anchor[1]) / recent_habit_weight)
                reference_rate = historical_rate if usable_history else base_habit_rate
                reference_high = max(high_habit_rate, reference_rate)
                recent_cap = max(reference_high * 2, reference_rate + 0.5)
                recent_rate = min(recent_rate, recent_cap)
                if usable_history:
                    recent_weight = min(0.45, 0.15 + 0.30 * min(1.0, max(0.0, span_hours - 12) / 36))
                else:
                    recent_weight = 0.35 * min(1.0, coverage_hours / 24)
                habit_rate = habit_rate * (1 - recent_weight) + recent_rate * recent_weight
                low_habit_rate = low_habit_rate * (1 - recent_weight) + recent_rate * recent_weight
                high_habit_rate = high_habit_rate * (1 - recent_weight) + recent_rate * recent_weight
        future_weight = habit_weight_between(now_at, reset_at, weights, habit_offset_seconds)
        projected_used = current_used + habit_rate * future_weight
        projected_low_used = current_used + min(low_habit_rate, high_habit_rate) * future_weight
        projected_high_used = current_used + max(low_habit_rate, high_habit_rate) * future_weight
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
        model = "habit-history" if usable_history else "habit"
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
        projected_low_used = projected_used
        projected_high_used = projected_used
        exhaust_at = (
            now_at + max(0.0, (100 - current_used) / rate) * 3600
            if projected_used >= 100 and rate > 0
            else None
        )
        model = "elapsed"

    local_day_start = ((now_at + int(habit_offset_seconds)) // 86400) * 86400 - int(habit_offset_seconds)
    if start_at >= local_day_start:
        used_at_day_start = 0.0
    else:
        day_start_points = [item for item in raw_observed if item[0] <= local_day_start]
        latest_baseline_at = max((item[0] for item in day_start_points), default=None)
        used_at_day_start = (
            max(item[1] for item in day_start_points)
            if latest_baseline_at is not None and local_day_start - latest_baseline_at <= 6 * 3600
            else None
        )
    today_used = max(0.0, current_used - used_at_day_start) if used_at_day_start is not None else None
    elapsed_hours = max((now_at - start_at) / 3600, 1 / 60)
    cycle_average = current_used / max(elapsed_hours / 24, 1 / 24)
    pace_is_building = not usable_history and (span_hours < 12 or changes < 3)

    return {
        "rate": None if pace_is_building else rate,
        "confidence": confidence,
        "spanHours": span_hours,
        "projectedUsed": None if pace_is_building else projected_used,
        "projectedLowUsed": None if pace_is_building else projected_low_used,
        "projectedHighUsed": None if pace_is_building else projected_high_used,
        "exhaustAt": None if pace_is_building else exhaust_at,
        "todayUsed": today_used,
        "todayBaselineUsed": used_at_day_start,
        "todayBaselineDayStart": local_day_start if used_at_day_start is not None else None,
        "cycleAveragePctPerDay": cycle_average,
        "model": "building" if pace_is_building else model,
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

    last_quota_snapshot = None
    try:
        send({
            "method": "initialize",
            "id": 1,
            "params": {
                "clientInfo": {"name": "codex-battery", "version": "0.1.44"},
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
        reset_credit_retry_requested = False
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
            if message.get("id") in (2, 3):
                result = message.get("result") or {}
                by_id = result.get("rateLimitsByLimitId") or {}
                snapshot = by_id.get("codex") or result.get("rateLimits")
                if not snapshot:
                    return last_quota_snapshot
                five_hour, week = normalize_quota_windows(
                    snapshot.get("primary"),
                    snapshot.get("secondary"),
                )
                reset_credits = result.get("rateLimitResetCredits") or {}
                if not isinstance(reset_credits, dict):
                    reset_credits = {}
                last_quota_snapshot = {
                    "timestamp": datetime.now(tz).isoformat(),
                    "planType": snapshot.get("planType"),
                    "limitId": snapshot.get("limitId"),
                    "limitName": snapshot.get("limitName"),
                    "quotaSource": "app_server",
                    "availableResetCredits": normalize_reset_credit_count(reset_credits),
                    "resetCreditExpirations": normalize_reset_credit_expirations(reset_credits),
                    "resetCreditsStale": False,
                    "primaryUsed": five_hour.get("used") if five_hour else None,
                    "secondaryUsed": week.get("used") if week else None,
                    "primaryReset": five_hour.get("reset") if five_hour else None,
                    "secondaryReset": week.get("reset") if week else None,
                }
                if (
                    last_quota_snapshot["availableResetCredits"] is None
                    and message.get("id") == 2
                    and not reset_credit_retry_requested
                ):
                    # The app-server can return the quota windows successfully
                    # while transiently leaving reset credits null. Retry only
                    # that live read once and keep the first quota snapshot if
                    # the retry does not finish within the grace period.
                    send({"method": "account/rateLimits/read", "id": 3, "params": None})
                    reset_credit_retry_requested = True
                    deadline = max(deadline, time.monotonic() + 4)
                    continue
                return last_quota_snapshot
    except Exception:
        pass
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
    return last_quota_snapshot

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
        "weeklyTrendProjectedLowUsed": None,
        "weeklyTrendProjectedHighUsed": None,
        "weeklyTrendExhaustAt": None,
        "weeklyTrendModel": None,
        "weeklyTodayUsed": None,
        "weeklyTodayBaselineUsed": None,
        "weeklyTodayBaselineDayStart": None,
        "weeklyCycleAveragePctPerDay": None,
        "weeklyHabitWeights": [],
        "weeklyHabitTimeZoneOffsetSeconds": int(tz.utcoffset(None).total_seconds()),
        "weeklyHabitSampleDays": 0,
        "weeklyHabitSampleBuckets": 0,
        "weeklyHistoricalRatePctPerHabitHour": None,
        "weeklyHistoricalLowRatePctPerHabitHour": None,
        "weeklyHistoricalHighRatePctPerHabitHour": None,
        "weeklyHistoricalSampleCycles": 0,
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
historical_pace = build_historical_pace_profile(
    weekly_points,
    reset_at,
    now.timestamp(),
    habit_profile.get("weights"),
    habit_profile.get("timeZoneOffsetSeconds", 0),
)
weekly_trend = build_weekly_trend(
    weekly_points,
    reset_at,
    now.timestamp(),
    used_week,
    habit_weights=habit_profile.get("weights"),
    habit_offset_seconds=habit_profile.get("timeZoneOffsetSeconds", 0),
    habit_sample_days=habit_profile.get("sampleDays", 0),
    habit_sample_buckets=habit_profile.get("sampleBuckets", 0),
    historical_rate=historical_pace.get("rate"),
    historical_low_rate=historical_pace.get("lowRate"),
    historical_high_rate=historical_pace.get("highRate"),
    historical_sample_cycles=historical_pace.get("sampleCycles", 0),
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
    "weeklyTrendProjectedLowUsed": weekly_trend.get("projectedLowUsed"),
    "weeklyTrendProjectedHighUsed": weekly_trend.get("projectedHighUsed"),
    "weeklyTrendExhaustAt": weekly_trend.get("exhaustAt"),
    "weeklyTrendModel": weekly_trend.get("model"),
    "weeklyTodayUsed": weekly_trend.get("todayUsed"),
    "weeklyTodayBaselineUsed": weekly_trend.get("todayBaselineUsed"),
    "weeklyTodayBaselineDayStart": weekly_trend.get("todayBaselineDayStart"),
    "weeklyCycleAveragePctPerDay": weekly_trend.get("cycleAveragePctPerDay"),
    "weeklyHabitWeights": habit_profile.get("weights"),
    "weeklyHabitTimeZoneOffsetSeconds": habit_profile.get("timeZoneOffsetSeconds"),
    "weeklyHabitSampleDays": habit_profile.get("sampleDays"),
    "weeklyHabitSampleBuckets": habit_profile.get("sampleBuckets"),
    "weeklyHistoricalRatePctPerHabitHour": historical_pace.get("rate"),
    "weeklyHistoricalLowRatePctPerHabitHour": historical_pace.get("lowRate"),
    "weeklyHistoricalHighRatePctPerHabitHour": historical_pace.get("highRate"),
    "weeklyHistoricalSampleCycles": historical_pace.get("sampleCycles", 0),
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
