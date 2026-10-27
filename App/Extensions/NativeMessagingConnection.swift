import BrowserKit
import Foundation

/// One running native messaging host: Nano launches it the way Chrome does, with the extension's
/// origin as its argument, and relays framed JSON over its stdin and stdout.
final class NativeMessagingConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    /// Writes can block while the host is busy, so they happen off the main thread, in order.
    private let writes = DispatchQueue(label: "com.joshoettinger.nano.native-messaging")
    private var reader = NativeMessaging.Reader()
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
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finish(nil) } }
        }
        try process.run()
    }

    func send(_ message: Any) {
        guard !isClosed else { return }
        let data: Data
        do { data = try NativeMessaging.frame(message) } catch { return finish(error) }
        let handle = input.fileHandleForWriting
        writes.async { try? handle.write(contentsOf: data) }
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
            for message in try reader.append(data) { onMessage?(message) }
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
