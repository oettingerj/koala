import Foundation
import os

/// Signposts for the input-latency budgets (view in Instruments › os_signpost). With the
/// `NanoPerfLog` default set, durations also go to tmp/nano-perf.log for checks without Instruments.
enum Perf {
    static let signposter = OSSignposter(subsystem: "com.joshoettinger.nano", category: .pointsOfInterest)
    private static let log = Logger(subsystem: "com.joshoettinger.nano", category: "perf")

    @discardableResult
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = ContinuousClock.now
        defer {
            signposter.endInterval(name, state)
            record(name, ContinuousClock.now - start)
        }
        return try work()
    }

    static func record(_ name: StaticString, _ duration: Duration) {
        let ms = Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000
        log.debug("\(name, privacy: .public) \(ms, format: .fixed(precision: 2), privacy: .public) ms")
        if UserDefaults.standard.bool(forKey: "NanoPerfLog") {
            append("\(name) \(String(format: "%.2f", ms))\n")
        }
    }

    /// Time since the process started, for the launch budget.
    static var sinceProcessStart: Duration {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let start = info.kp_proc.p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return .milliseconds(Int((Date().timeIntervalSince1970 - started) * 1000))
    }

    private static let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("nano-perf.log")

    private static func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL)
        }
    }
}
