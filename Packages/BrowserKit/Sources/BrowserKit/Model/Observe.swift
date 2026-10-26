import Observation

/// Re-runs `body` whenever an observable property it read changes, until cancelled.
/// Bridges `@Observable` models to AppKit views without Combine.
@MainActor
public final class ObservationLoop {
    private var isCancelled = false

    public init(_ body: @escaping @MainActor () -> Void) {
        run(body)
    }

    public func cancel() { isCancelled = true }

    private func run(_ body: @escaping @MainActor () -> Void) {
        guard !isCancelled else { return }
        withObservationTracking(body) { [weak self] in
            Task { @MainActor in self?.run(body) }
        }
    }
}
