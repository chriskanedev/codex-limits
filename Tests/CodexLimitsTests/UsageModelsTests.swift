import Foundation
import Testing
@testable import CodexLimits

struct UsageModelsTests {
    @Test func remainingPercentageIsClamped() {
        #expect(window(used: 21).remainingPercent == 79)
        #expect(window(used: -8).remainingPercent == 100)
        #expect(window(used: 140).remainingPercent == 0)
    }

    @Test func durationLabelsUseCompactUnits() {
        #expect(DurationLabel.format(minutes: 300) == "5h")
        #expect(DurationLabel.format(minutes: 10_080) == "7d")
        #expect(DurationLabel.format(minutes: 45) == "45m")
        #expect(DurationLabel.format(minutes: nil) == "Limit")
    }

    @Test func justUpdatedTextDoesNotDescribeZeroSecondsAsFuture() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(FreshnessText.format(now.addingTimeInterval(0.5), now: now) == "Updated just now")
        #expect(FreshnessText.format(now, now: now, stale: true) == "Updated just now · stale")
    }

    @Test func plusSnapshotHasSortedFiveHourAndWeeklyWindows() throws {
        let bucket = RateLimitBucketPayload(
            limitId: "codex",
            limitName: nil,
            primary: .init(usedPercent: 21, windowDurationMins: 300, resetsAt: 1_800_000_000),
            secondary: .init(usedPercent: 11, windowDurationMins: 10_080, resetsAt: 1_800_100_000),
            planType: "plus"
        )

        let snapshot = try bucket.snapshot(at: Date(timeIntervalSince1970: 1))
        #expect(snapshot.windows.map(\.durationLabel) == ["5h", "7d"])
        #expect(snapshot.windows.map(\.remainingPercent) == [79, 89])
    }

    @Test func weeklyOnlySnapshotHasOneWindow() throws {
        let bucket = RateLimitBucketPayload(
            limitId: "codex",
            limitName: nil,
            primary: .init(usedPercent: 11, windowDurationMins: 10_080, resetsAt: nil),
            secondary: nil,
            planType: "pro"
        )

        let snapshot = try bucket.snapshot()
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].durationLabel == "7d")
        #expect(snapshot.windows[0].resetsAt == nil)
    }

    @Test func sparseUpdatePreservesExistingFields() throws {
        let current = RateLimitBucketPayload(
            limitId: "codex",
            limitName: nil,
            primary: .init(usedPercent: 20, windowDurationMins: 300, resetsAt: 100),
            secondary: .init(usedPercent: 10, windowDurationMins: 10_080, resetsAt: 200),
            planType: "plus"
        )
        let update = RateLimitBucketPayload(
            limitId: "codex",
            limitName: nil,
            primary: .init(usedPercent: 25, windowDurationMins: nil, resetsAt: nil),
            secondary: nil,
            planType: nil
        )

        let merged = current.merged(with: update)
        #expect(merged.primary?.usedPercent == 25)
        #expect(merged.primary?.windowDurationMins == 300)
        #expect(merged.secondary?.usedPercent == 10)
        #expect(merged.planType == "plus")
    }

    @Test func responsePrefersCodexBucket() throws {
        let legacy = RateLimitBucketPayload(primary: .init(usedPercent: 99, windowDurationMins: 60))
        let codex = RateLimitBucketPayload(primary: .init(usedPercent: 20, windowDurationMins: 300))
        let json = """
        {"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":60}},
         "rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":20,"windowDurationMins":300}},
                                "codex_other":{"primary":{"usedPercent":50,"windowDurationMins":60}}}}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(RateLimitResultPayload.self, from: json)
        #expect(result.rateLimits == legacy)
        #expect(result.codexBucket == codex)
    }

    @Test func emptyBucketIsRejected() {
        #expect(throws: UsageError.incompatibleResponse) {
            try RateLimitBucketPayload().snapshot()
        }
    }

    private func window(used: Int) -> UsageWindow {
        UsageWindow(id: "test", usedPercent: used, durationMinutes: 300, resetsAt: nil)
    }
}
