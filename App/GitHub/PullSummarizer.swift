import BrowserKit
import Foundation
import FoundationModels
import Observation
import os

/// Writes what each pull request on the Reviews page is about, on this Mac, with Apple Intelligence:
/// a one-line gist for its row and a few sentences for the detail pane. One at a time, review
/// requests first; summaries are kept across launches until the pull request's text changes.
/// Without the model, or with the setting off, the page shows the author's own first paragraph.
@MainActor
@Observable
final class PullSummarizer {
    static let shared = PullSummarizer()

    enum Availability: Equatable {
        case available
        case unavailable(String)
    }

    /// Summaries of the pull requests in the lists, by id.
    private(set) var summaries: [GitHubPull.ID: PullSummary] = [:]
    /// Pull requests waiting for a summary, so their rows can hold the space.
    private(set) var pending: Set<GitHubPull.ID> = []

    var isEnabled = UserDefaults.standard.object(forKey: "SummarizePulls") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "SummarizePulls")
            if isEnabled { update(pulls) } else { stop() }
        }
    }

    var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.appleIntelligenceNotEnabled): .unavailable("Turn on Apple Intelligence in System Settings to use this.")
        case .unavailable(.deviceNotEligible): .unavailable("This Mac doesn’t support Apple Intelligence.")
        case .unavailable(.modelNotReady): .unavailable("Apple Intelligence is still downloading. Summaries start when it’s ready.")
        case .unavailable: .unavailable("Apple Intelligence isn’t available right now.")
        }
    }

    /// The summary a view shows, nil while it's off or not yet written.
    func summary(for id: GitHubPull.ID) -> PullSummary? { isEnabled ? summaries[id] : nil }

    func isPending(_ id: GitHubPull.ID) -> Bool { isEnabled && pending.contains(id) }

    @ObservationIgnored private var pulls: [GitHubPull] = []
    @ObservationIgnored private var fingerprints: [GitHubPull.ID: String] = [:]
    @ObservationIgnored private var queue: [GitHubPull] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.joshoettinger.koala", category: "summaries")
    private var store: PullSummaryStore { AppServices.shared.pullSummaries }

    private init() {}

    /// Takes the latest lists, in the order summaries should be written, and queues each pull
    /// request whose text has no summary yet.
    func update(_ pulls: [GitHubPull]) {
        #if DEBUG
        if showsFixture { return }
        #endif
        var seen = Set<GitHubPull.ID>()
        self.pulls = pulls.filter { seen.insert($0.id).inserted }
        let current = Dictionary(uniqueKeysWithValues: self.pulls.map { ($0.id, PullContext.fingerprint($0)) })
        // Summaries of text that changed, or of pull requests that left the lists, go.
        for id in summaries.keys where current[id] != fingerprints[id] { summaries[id] = nil }
        fingerprints = current
        guard isEnabled, availability == .available else { stop(); return }
        let missing = self.pulls.filter { summaries[$0.id] == nil }
        pending = Set(missing.map(\.id))
        generation += 1
        let generation = generation
        Task {
            let stored = await store.load(missing.map(\.id))
            guard generation == self.generation else { return }
            for pull in missing {
                if let row = stored[pull.id], row.fingerprint == current[pull.id] {
                    summaries[pull.id] = row.summary
                    pending.remove(pull.id)
                }
            }
            queue = self.pulls.filter { pending.contains($0.id) }
            startWorker()
            await store.prune(keeping: self.pulls.map(\.id))
        }
    }

    /// Writes this pull request's summary next, as the detail pane shows it.
    func prioritize(_ id: GitHubPull.ID) {
        guard let index = queue.firstIndex(where: { $0.id == id }), index > 0 else { return }
        queue.insert(queue.remove(at: index), at: 0)
    }

    private func stop() {
        queue = []
        pending = []
        worker?.cancel()
        worker = nil
    }

    private func startWorker() {
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task {
            while !Task.isCancelled, !queue.isEmpty {
                let pull = queue.removeFirst()
                // A refresh while the model wrote can queue the same pull request again.
                guard let fingerprint = fingerprints[pull.id], summaries[pull.id] == nil else {
                    pending.remove(pull.id)
                    continue
                }
                let summary = await Self.summarize(pull, log: log)
                guard !Task.isCancelled else { break }
                pending.remove(pull.id)
                // Text that changed while the model wrote is queued again by `update`.
                guard let summary, fingerprints[pull.id] == fingerprint else { continue }
                summaries[pull.id] = summary
                await store.save(id: pull.id, fingerprint: fingerprint, summary: summary)
            }
            worker = nil
        }
    }

    // MARK: Model

    @Generable
    struct Gist {
        @Guide(description: "One sentence of at most 16 words saying what the pull request changes and why. Start with a verb such as Fixes, Adds, Moves, or Removes. Never start with 'This pull request'.")
        var gist: String
        @Guide(description: "Two or three short sentences for a reviewer: what changes and why, using only the description and file list. Plain text, no Markdown, no lists.")
        var overview: String
    }

    nonisolated private static let instructions = """
    You summarize GitHub pull requests for an engineer deciding which review to open next. \
    Be concrete: name the feature, component, or behavior that changes. \
    Use only what the pull request says; never guess at details it doesn't give. Write plain text without Markdown.
    """

    nonisolated private static func summarize(_ pull: GitHubPull, log: Logger) async -> PullSummary? {
        var prompt = "Title: \(pull.title)\nRepository: \(pull.repo)\n"
        if let head = pull.headRef, let base = pull.baseRef { prompt += "Branch: \(head) into \(base)\n" }
        if let body = PullContext.cleaned(markdown: pull.body) { prompt += "Description:\n\(body.prefix(1500))\n" }
        if !pull.files.isEmpty {
            prompt += "Files changed (\(max(pull.changedFiles, pull.files.count)), +\(pull.additions) −\(pull.deletions)):\n"
            prompt += pull.files.prefix(40).joined(separator: "\n")
        }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: Gist.self, options: GenerationOptions(temperature: 0.2))
            let gist = response.content.gist.trimmingCharacters(in: .whitespacesAndNewlines)
            let overview = response.content.overview.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !gist.isEmpty else { return nil }
            return PullSummary(gist: gist, overview: overview.isEmpty ? gist : overview)
        } catch {
            log.debug("Couldn’t summarize \(pull.id, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    #if DEBUG
    /// Review scripts show written summaries without the model; updates leave them alone.
    @ObservationIgnored private var showsFixture = false

    func showFixture(_ summaries: [GitHubPull.ID: PullSummary], pending: Set<GitHubPull.ID>) {
        showsFixture = true
        stop()
        self.summaries = summaries
        self.pending = pending
    }
    #endif
}
