import Foundation

struct RateLimitWindowPayload: Codable, Equatable, Sendable {
    var usedPercent: Int?
    var windowDurationMins: Int?
    var resetsAt: Int?

    func merged(with newer: Self?) -> Self {
        guard let newer else { return self }
        return Self(
            usedPercent: newer.usedPercent ?? usedPercent,
            windowDurationMins: newer.windowDurationMins ?? windowDurationMins,
            resetsAt: newer.resetsAt ?? resetsAt
        )
    }
}

struct RateLimitBucketPayload: Codable, Equatable, Sendable {
    var limitId: String?
    var limitName: String?
    var primary: RateLimitWindowPayload?
    var secondary: RateLimitWindowPayload?
    var planType: String?

    func merged(with newer: Self) -> Self {
        Self(
            limitId: newer.limitId ?? limitId,
            limitName: newer.limitName ?? limitName,
            primary: mergeWindow(primary, newer.primary),
            secondary: mergeWindow(secondary, newer.secondary),
            planType: newer.planType ?? planType
        )
    }

    private func mergeWindow(
        _ current: RateLimitWindowPayload?,
        _ newer: RateLimitWindowPayload?
    ) -> RateLimitWindowPayload? {
        switch (current, newer) {
        case (nil, nil): nil
        case (nil, let newer?): newer
        case (let current?, nil): current
        case (let current?, let newer?): current.merged(with: newer)
        }
    }

    func snapshot(at date: Date = .now) throws -> UsageSnapshot {
        let payloads = [("primary", primary), ("secondary", secondary)]
        let windows = payloads.compactMap { name, payload -> UsageWindow? in
            guard let payload, let used = payload.usedPercent else { return nil }
            return UsageWindow(
                id: name,
                usedPercent: used,
                durationMinutes: payload.windowDurationMins,
                resetsAt: payload.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }
        .sorted {
            ($0.durationMinutes ?? .max) < ($1.durationMinutes ?? .max)
        }

        guard !windows.isEmpty else { throw UsageError.incompatibleResponse }
        return UsageSnapshot(planType: planType, windows: windows, fetchedAt: date)
    }
}

struct RateLimitResultPayload: Decodable, Sendable {
    let rateLimits: RateLimitBucketPayload
    let rateLimitsByLimitId: [String: RateLimitBucketPayload]?

    var codexBucket: RateLimitBucketPayload {
        rateLimitsByLimitId?["codex"] ?? rateLimits
    }
}

struct RPCErrorPayload: Decodable, Sendable {
    let code: Int?
    let message: String
}

struct RateLimitResponseEnvelope: Decodable, Sendable {
    let result: RateLimitResultPayload?
    let error: RPCErrorPayload?
}

struct RPCNotificationEnvelope: Decodable, Sendable {
    struct Parameters: Decodable, Sendable {
        let rateLimits: RateLimitBucketPayload?
    }

    let method: String
    let params: Parameters?
}
