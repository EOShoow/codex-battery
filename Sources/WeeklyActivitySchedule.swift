import Foundation

/// The local weekday/hour activity profile used by the weekly quota forecasts.
struct WeeklyActivitySchedule {
    private let weights: [Double]
    private let timeZoneOffsetSeconds: Int

    init?(weights: [Double]?, timeZoneOffsetSeconds: Int? = nil) {
        guard let weights, weights.count == 7 * 24,
              weights.contains(where: { $0.isFinite && $0 > 0 }) else { return nil }
        self.weights = weights.map { $0.isFinite ? max(0, $0) : 0 }
        self.timeZoneOffsetSeconds = timeZoneOffsetSeconds ?? 0
    }

    func weight(from start: Double, to end: Double) -> Double {
        var cursor = start
        var total = 0.0
        while cursor < end {
            let segment = hourSegment(from: cursor, to: end)
            total += (segment.end - cursor) / 3600 * segment.weight
            cursor = segment.end
        }
        return total
    }

    func timestamp(from start: Double, to end: Double, requiring requiredWeight: Double) -> Double? {
        guard requiredWeight > 0, end > start else { return start }
        var remaining = requiredWeight
        var cursor = start
        while cursor < end {
            let segment = hourSegment(from: cursor, to: end)
            let available = (segment.end - cursor) / 3600 * segment.weight
            if segment.weight > 0, remaining <= available {
                return cursor + remaining / segment.weight * 3600
            }
            remaining -= available
            cursor = segment.end
        }
        return nil
    }

    private func hourSegment(from start: Double, to end: Double) -> (end: Double, weight: Double) {
        let offset = Double(timeZoneOffsetSeconds)
        let localHour = floor((start + offset) / 3600)
        let localDay = Int(floor(localHour / 24))
        let hour = (Int(localHour) % 24 + 24) % 24
        let weekday = ((localDay + 3) % 7 + 7) % 7  // The Unix epoch starts on Thursday.
        let nextBoundary = (localHour + 1) * 3600 - offset
        return (min(end, max(start + 1, nextBoundary)), weights[weekday * 24 + hour])
    }
}
