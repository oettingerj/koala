import BrowserKit
import Foundation
import os

/// One running native messaging host: Koala launches it the way Chrome does, with the extension's
/// origin as its argument, and relays framed JSON over its stdin and stdout.
final class NativeMessagingConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    /// Writes can block while the host is busy, so they happen off the main thread, in order.
    private let writes = DispatchQueue(label: "com.joshoettinger.koala.native-messaging")
    private var reader = NativeMessaging.Reader()
    private let log = Logger(subsystem: "com.joshoettinger.koala", category: "native-messaging")
    private var isClosed = false

    var onMessage: ((Any) -> Void)?
    /// Called once, when the host exits or sends something unreadable.
    var onClose: ((Error?) -> Void)?

    init(host: NativeMessaging.HostManifest, chromeID: String) throws {
        process.executableURL = URL(fileURLWithPath: host.path)
        process.arguments = [NativeMessaging.origin(of: chromeID)]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // Both handlers run on background threads; the main queue keeps chunks in order.
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        process.terminationHandler = { [weak self] process in
            self?.log.info("Host exited with status \(process.terminationStatus)")
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finish(nil) } }
        }
        try process.run()
    }

    func send(_ message: Any) {
        guard !isClosed else { return }
        let data: Data
        do { data = try NativeMessaging.frame(message) } catch { return finish(error) }
        log.debug("Extension -> host: \(Self.shape(of: message), privacy: .public)")
        let handle = input.fileHandleForWriting
        writes.async { try? handle.write(contentsOf: data) }
    }

    /// Top-level keys and any string under `type`/`action`/`name`, never values.
    private static func shape(of message: Any) -> String {
        guard let dict = message as? [String: Any] else { return "\(type(of: message))" }
        let tags = ["type", "action", "name"].compactMap { key in (dict[key] as? String).map { "\(key)=\($0)" } }
        return "{\(dict.keys.sorted().joined(separator: ","))}" + (tags.isEmpty ? "" : " " + tags.joined(separator: " "))
    }

    /// Stops the host. Its exit doesn't call `onClose`; the caller already knows.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        teardown()
    }

    private func receive(_ data: Data) {
        guard !isClosed else { return }
        // An empty read is end of file: the host closed its stdout.
        guard !data.isEmpty else { return finish(nil) }
        do {
            for message in try reader.append(data) {
                // Only the shape of the message: hosts carry secrets.
                log.debug("Host -> extension: \(Self.shape(of: message), privacy: .public)")
                onMessage?(message)
            }
        } catch {
            finish(error)
        }
    }

    private func finish(_ error: Error?) {
        guard !isClosed else { return }
        isClosed = true
        teardown()
        onClose?(error)
    }

    private func teardown() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        let handle = input.fileHandleForWriting
        writes.async { try? handle.close() }
    }
}
