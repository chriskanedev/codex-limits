import Foundation

actor CodexAppServerClient: RateLimitProviding {
    nonisolated let updates: AsyncStream<UsageSnapshot>

    private let executableURL: URL
    private let arguments: [String]
    private let updateContinuation: AsyncStream<UsageSnapshot>.Continuation
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var readBuffer = Data()
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var requestID = 0
    private var initialized = false
    private var latestBucket: RateLimitBucketPayload?
    private var pendingRateLimitUpdate: RateLimitBucketPayload?
    private var restartAttempt = 0

    init(executableURL: URL, arguments: [String] = ["app-server"]) {
        self.executableURL = executableURL
        self.arguments = arguments
        let stream = AsyncStream.makeStream(of: UsageSnapshot.self)
        updates = stream.stream
        updateContinuation = stream.continuation
    }

    func read() async throws -> UsageSnapshot {
        try await ensureConnected()
        let data = try await request(method: "account/rateLimits/read", params: nil)
        let envelope = try JSONDecoder().decode(RateLimitResponseEnvelope.self, from: data)
        if let error = envelope.error {
            throw classifyServerError(error.message)
        }
        guard var bucket = envelope.result?.codexBucket else {
            throw UsageError.incompatibleResponse
        }
        let hadPendingUpdate = pendingRateLimitUpdate != nil
        if let pendingRateLimitUpdate {
            bucket = bucket.merged(with: pendingRateLimitUpdate)
            self.pendingRateLimitUpdate = nil
        }
        latestBucket = bucket
        restartAttempt = 0
        let snapshot = try bucket.snapshot()
        if hadPendingUpdate {
            updateContinuation.yield(snapshot)
        }
        return snapshot
    }

    func stop() async {
        let process = process
        resetConnection(with: UsageError.appServerStopped)
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        updateContinuation.finish()
    }

    private func ensureConnected() async throws {
        if initialized, process?.isRunning == true { return }

        if restartAttempt > 0 {
            let delay = min(8, 1 << (restartAttempt - 1))
            try await Task.sleep(for: .seconds(delay))
        }

        try startProcess()
        let initializeParams: [String: Any] = [
            "clientInfo": [
                "name": "codex-limits",
                "title": "Codex Limits",
                "version": "1.0.0",
            ],
            "capabilities": ["experimentalApi": true],
        ]
        _ = try await request(method: "initialize", params: initializeParams, requireInitialization: false)
        try send(["method": "initialized", "params": [:]])
        initialized = true
    }

    private func startProcess() throws {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw UsageError.codexExecutableMissing
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { await self?.processDidTerminate() }
        }

        output = stdoutPipe.fileHandleForReading
        input = stdinPipe.fileHandleForWriting
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.consume(data) }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            resetConnection(with: error)
            throw error
        }
    }

    private func request(
        method: String,
        params: [String: Any]?,
        requireInitialization: Bool = true
    ) async throws -> Data {
        if requireInitialization {
            try await ensureConnected()
        }

        requestID += 1
        let id = requestID
        var message: [String: Any] = ["id": id, "method": method]
        if let params {
            message["params"] = params
        }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try send(message)
            } catch {
                pending.removeValue(forKey: id)?.resume(throwing: error)
            }
        }
    }

    private func send(_ object: [String: Any]) throws {
        guard let input else { throw UsageError.appServerStopped }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        readBuffer.append(data)

        while let newline = readBuffer.firstIndex(of: 0x0A) {
            let line = Data(readBuffer[..<newline])
            readBuffer.removeSubrange(...newline)
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        guard
            !data.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
            continuation.resume(returning: data)
            return
        }

        guard
            object["method"] as? String == "account/rateLimits/updated",
            let notification = try? JSONDecoder().decode(RPCNotificationEnvelope.self, from: data),
            let newer = notification.params?.rateLimits
        else { return }

        guard latestBucket != nil else {
            pendingRateLimitUpdate = pendingRateLimitUpdate?.merged(with: newer) ?? newer
            return
        }
        let merged = latestBucket?.merged(with: newer) ?? newer
        latestBucket = merged
        if let snapshot = try? merged.snapshot() {
            updateContinuation.yield(snapshot)
        }
    }

    private func processDidTerminate() async {
        resetConnection(with: UsageError.appServerStopped)
    }

    private func resetConnection(with error: Error) {
        output?.readabilityHandler = nil
        input = nil
        output = nil
        process = nil
        initialized = false
        readBuffer.removeAll(keepingCapacity: true)
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
        restartAttempt = min(restartAttempt + 1, 4)
    }

    private func classifyServerError(_ message: String) -> Error {
        let lowercased = message.lowercased()
        if lowercased.contains("login") || lowercased.contains("auth") || lowercased.contains("unauthorized") {
            return UsageError.notSignedIn(message)
        }
        return UsageError.server(message)
    }
}
