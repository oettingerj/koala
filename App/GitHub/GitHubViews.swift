import AppKit
import BrowserKit
import SwiftUI

/// Colors and glyphs for GitHub state, shared by the tab strip, chip, and popovers.
enum GitHubStyle {
    static func glyph(_ state: GitHubStatus.State) -> (symbol: String, color: NSColor, label: String) {
        switch state {
        case .open: ("arrow.triangle.pull", Theme.pass, "Pull request open")
        case .draft: ("arrow.triangle.pull", Theme.textTertiary, "Draft pull request")
        case .merged: ("arrow.triangle.merge", Theme.merged, "Pull request merged")
        case .closed: ("arrow.triangle.pull", Theme.fail, "Pull request closed")
        case .issueOpen: ("smallcircle.filled.circle", Theme.pass, "Issue open")
        case .issueClosed(let completed): completed ? ("checkmark.circle", Theme.merged, "Issue closed")
            : ("slash.circle", Theme.textTertiary, "Issue closed as not planned")
        }
    }

    static func color(_ checks: GitHubStatus.Checks) -> NSColor? {
        switch checks {
        case .passing: Theme.pass
        case .failing: Theme.fail
        case .pending: Theme.pending
        case .none: nil
        }
    }

    static func label(_ checks: GitHubStatus.Checks) -> String? {
        switch checks {
        case .passing: "checks passing"
        case .failing: "checks failing"
        case .pending: "checks running"
        case .none: nil
        }
    }

    static func image(_ state: GitHubStatus.State, size: CGFloat = 12) -> NSImage? {
        let glyph = glyph(state)
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(.init(paletteColors: [glyph.color]))
        return NSImage(systemSymbolName: glyph.symbol, accessibilityDescription: glyph.label)?.withSymbolConfiguration(config)
    }
}

// MARK: Context chip popover

struct GitHubContextPopover: View {
    let github: GitHubURL
    let status: GitHubStatus?
    let isSignedIn: Bool
    let hasClone: Bool
    var perform: (Action) -> Void

    enum Action { case copyBranch(String), copyCheckout(Int), copyPermalink, openInEditor, signIn, open(URL) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(github.slug).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(nsColor: Theme.textSecondary))
                if let number = github.number {
                    Text(verbatim: "#\(number)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(nsColor: Theme.textTertiary))
                }
            }
            if let status {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let image = GitHubStyle.image(status.state, size: 13) { Image(nsImage: image) }
                    Text(status.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(nsColor: Theme.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let head = status.headRef, let base = status.baseRef {
                    HStack(spacing: 6) {
                        Text(head).font(.system(size: 12, design: .monospaced))
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(Color(nsColor: Theme.textTertiary))
                        Text(base).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(nsColor: Theme.textSecondary))
                        Spacer()
                        Button("Copy Branch") { perform(.copyBranch(head)) }.controlSize(.small)
                    }
                }
                if !status.checkRuns.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(status.checkRuns.prefix(12)) { check in
                            Button { if let url = check.url { perform(.open(url)) } } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(nsColor: GitHubStyle.color(check.result) ?? Theme.textTertiary)).frame(width: 7, height: 7)
                                    Text(check.name).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.textPrimary)).lineLimit(1)
                                    Spacer()
                                    Text(GitHubStyle.label(check.result) ?? "").font(.system(size: 11))
                                        .foregroundStyle(Color(nsColor: Theme.textTertiary))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if status.checkRuns.count > 12 {
                            Text("\(status.checkRuns.count - 12) more checks").font(.system(size: 11)).foregroundStyle(Color(nsColor: Theme.textTertiary))
                        }
                    }
                }
                if !status.reviewers.isEmpty || status.reviewDecision != nil {
                    Divider()
                    HStack(spacing: 6) {
                        Text(reviewText(status)).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.textSecondary))
                        Spacer()
                    }
                }
            } else if !isSignedIn, github.number != nil {
                Text("Sign in to GitHub to see state, checks, and reviewers here and in the tab strip.")
                    .font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Sign In to GitHub…") { perform(.signIn) }.controlSize(.small)
            }
            Divider()
            HStack(spacing: 6) {
                if let number = github.number, case .pullRequest = github.kind {
                    Button("Copy Checkout") { perform(.copyCheckout(number)) }.help("gh pr checkout \(number)")
                }
                if case .blob = github.kind { Button("Copy Permalink") { perform(.copyPermalink) } }
                Button("Open in Editor") { perform(.openInEditor) }
                    .disabled(!hasClone)
                    .help(hasClone ? "Open the local clone" : "No local clone found. Choose your code folder in Settings › GitHub.")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .tint(Color(nsColor: Theme.accent))
    }

    private func reviewText(_ status: GitHubStatus) -> String {
        var parts: [String] = []
        switch status.reviewDecision {
        case "APPROVED": parts.append("Approved")
        case "CHANGES_REQUESTED": parts.append("Changes requested")
        case "REVIEW_REQUIRED": parts.append("Review required")
        default: break
        }
        if !status.reviewers.isEmpty { parts.append("waiting on " + status.reviewers.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Review queue popover

struct ReviewQueuePopover: View {
    let items: [GitHubQueueItem]
    let isSignedIn: Bool
    var open: (URL) -> Void
    var signIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Review queue").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if !isSignedIn {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in to see pull requests waiting on your review and your own PRs with failing checks.")
                        .font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Sign In to GitHub…", action: signIn).controlSize(.small)
                }
                .padding(14)
            } else if items.isEmpty {
                Text("Nothing waiting on you.").font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.textTertiary)).padding(14)
            } else {
                ForEach(items) { item in
                    Button { open(item.url) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.reason == .reviewRequested ? "eye" : "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: item.reason == .reviewRequested ? Theme.textSecondary : Theme.fail))
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(nsColor: Theme.textPrimary)).lineLimit(2)
                                Text(verbatim: "\(item.repo)#\(item.number)").font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color(nsColor: Theme.textTertiary))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 360, alignment: .leading)
        .tint(Color(nsColor: Theme.accent))
    }
}

// MARK: Sign-in sheet

@MainActor
@Observable
final class GitHubSignIn {
    enum Phase: Equatable { case needsClientID, requesting, waiting(GitHubDeviceFlow.Code), failed(String), done }
    var phase: Phase = .requesting
    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        let clientID = GitHubService.shared.clientID
        guard !clientID.isEmpty else { phase = .needsClientID; return }
        phase = .requesting
        task = Task {
            let flow = GitHubDeviceFlow(clientID: clientID)
            do {
                let code = try await flow.requestCode()
                phase = .waiting(code)
                let token = try await flow.waitForToken(code)
                GitHubService.shared.didSignIn(token: token)
                phase = .done
            } catch is CancellationError {
            } catch GitHubDeviceFlow.Failure.denied {
                phase = .failed("Access was denied on GitHub.")
            } catch GitHubDeviceFlow.Failure.expired {
                phase = .failed("The code expired. Try again.")
            } catch GitHubDeviceFlow.Failure.misconfigured(let message) {
                phase = .failed("GitHub rejected the request: \(message). Check the client ID and that device flow is enabled for the OAuth app.")
            } catch {
                phase = .failed("Couldn’t reach GitHub. Check your connection and try again.")
            }
        }
    }

    func cancel() { task?.cancel() }
}

struct GitHubSignInView: View {
    @Bindable var model: GitHubSignIn
    var openURL: (URL) -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in to GitHub").font(.system(size: 15, weight: .semibold))
            switch model.phase {
            case .needsClientID:
                Text("Add your GitHub OAuth app’s client ID in Settings › GitHub first. Device flow must be enabled on the app.")
                    .font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.textSecondary)).fixedSize(horizontal: false, vertical: true)
            case .requesting:
                ProgressView().controlSize(.small)
            case .waiting(let code):
                Text("Enter this code on GitHub to let Nano read pull request and issue status.")
                    .font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.textSecondary)).fixedSize(horizontal: false, vertical: true)
                Text(code.userCode).font(.system(size: 28, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    .tracking(2)
                HStack {
                    Button("Copy Code and Open GitHub") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code.userCode, forType: .string)
                        openURL(code.verificationURI)
                    }
                    .keyboardShortcut(.defaultAction)
                    ProgressView().controlSize(.small)
                    Text("Waiting for approval").font(.system(size: 11)).foregroundStyle(Color(nsColor: Theme.textTertiary))
                }
            case .failed(let message):
                Text(message).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.fail)).fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { model.start() }
            case .done:
                Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(Color(nsColor: Theme.pass))
            }
            HStack {
                Spacer()
                Button(model.phase == .done ? "Done" : "Cancel") {
                    model.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .tint(Color(nsColor: Theme.accent))
        .onAppear { model.start() }
    }
}

@MainActor
enum GitHubHosting {
    static func contextPopover(_ view: GitHubContextPopover) -> NSViewController { NSHostingController(rootView: view) }
    static func queuePopover(_ view: ReviewQueuePopover) -> NSViewController { NSHostingController(rootView: view) }
    static func signInSheet(_ view: GitHubSignInView) -> NSViewController { NSHostingController(rootView: view) }
}
