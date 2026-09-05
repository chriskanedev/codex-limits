import Foundation
import Testing
@testable import CodexLimits

struct AppServerClientTests {
    @Test func clientInitializesReadsAndReceivesLiveUpdate() async throws {
        let script = #"""
        IFS= read -r initialize
        printf '%s\n' '{"id":1,"result":{"userAgent":"fake","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}'
        IFS= read -r initialized
        IFS= read -r request
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","planType":"plus","primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1800100000}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","planType":"plus","primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1800100000}}}}}'
        sleep 0.1
        printf '%s\n' '{"method":"account/rateLimits/updated","params":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25}}}}'
        while IFS= read -r line; do :; done
        """#

        let client = CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )
        var updates = client.updates.makeAsyncIterator()

        let initial = try await client.read()
        #expect(initial.windows.map(\.remainingPercent) == [80, 90])

        let live = await updates.next()
        #expect(live?.windows.map(\.remainingPercent) == [75, 90])
        #expect(live?.windows.map(\.durationLabel) == ["5h", "7d"])

        await client.stop()
    }
}
