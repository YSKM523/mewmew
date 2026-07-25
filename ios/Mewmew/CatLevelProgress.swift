import Foundation

struct CatLevelProgress: Equatable {
    let level: Int64
    let fraction: Double

    init(xp: Int64) {
        let clampedXP = max(0, xp)
        let level = Self.level(for: clampedXP)
        let currentThreshold = Self.threshold(for: level)
        let nextThreshold = Self.threshold(for: level + 1)
        let span = max(1, nextThreshold - currentThreshold)

        self.level = level
        fraction = min(
            1,
            max(
                0,
                Double(clampedXP - currentThreshold) / Double(span)
            )
        )
    }

    static func threshold(for level: Int64) -> Int64 {
        if level <= 1 {
            return 0
        }
        if level == 2 {
            return 30
        }

        let (factors, factorsOverflow) = (level - 2)
            .multipliedReportingOverflow(by: level - 1)
        guard !factorsOverflow else { return .max }

        let (scaled, scaledOverflow) = factors
            .multipliedReportingOverflow(by: 20)
        guard !scaledOverflow else { return .max }

        let (threshold, additionOverflow) = scaled
            .addingReportingOverflow(40)
        return additionOverflow ? .max : threshold
    }

    private static func level(for xp: Int64) -> Int64 {
        if xp < 30 {
            return 1
        }
        if xp < 80 {
            return 2
        }

        var low: Int64 = 3
        var high: Int64 = 1_000_000_000
        while low < high {
            let middle = low + (high - low + 1) / 2
            if threshold(for: middle) <= xp {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }
}
