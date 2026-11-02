import AppKit
import BrowserKit
import SwiftUI

/// Beside the Reviews list on wide pages: what the previewed pull request is about, where it
/// changes the codebase, and where its review stands. Swaps instantly with the preview; nothing
/// in it animates.
struct PullDetailPane: View {
    let pull: GitHubPull
    let tab: ReviewsModel.Tab
    let now: Date
    private var summarizer: PullSummarizer { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.bottom, 16)
                    about
                    hairline.padding(.vertical, 14)
                    PreviewFactGrid(facts: facts, lineLimit: 6)
                }
                .padding(.leading, 16).padding(.trailing, 8).padding(.top, 16).padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Details")
    }

    private var hairline: some View {
        Rectangle().fill(Color(nsColor: Theme.hairline)).frame(height: 1)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let image = GitHubStyle.image(pull.isDraft ? .draft : .open, size: 12) {
                    Image(nsImage: image).accessibilityLabel(pull.isDraft ? "Draft" : "Open")
                }
                Text(pull.title)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(settingsPrimary)
                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: 0) {
                Text(pull.repo).foregroundStyle(settingsSecondary)
                Text(verbatim: "#\(pull.number)").foregroundStyle(settingsTertiary)
            }
            .font(.mono(size: 11)).lineLimit(1)
            .padding(.leading, 20)
            if let author = pull.author {
                HStack(spacing: 6) {
                    AvatarView(url: pull.authorAvatarURL)
                    Text(author).font(.mono(size: 11)).foregroundStyle(settingsSecondary).lineLimit(1)
                    if let created = pull.createdAt {
                        Text("opened \(RelativeAge.long(since: created, now: now))")
                            .font(.system(size: 11)).foregroundStyle(settingsTertiary).lineLimit(1)
                            .help(created.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .padding(.leading, 20).padding(.top, 4)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: About

    /// The written overview, then the author's own words; without an overview, the author's words alone.
    @ViewBuilder private var about: some View {
        let summary = summarizer.summary(for: pull.id)
        VStack(alignment: .leading, spacing: 12) {
            if let summary {
                block(title: "Summary", generated: true) {
                    Text(summary.overview).font(.system(size: 12)).foregroundStyle(settingsPrimary)
                }
                if let excerpt = pull.excerpt {
                    block(title: "Description") {
                        Text(excerpt).font(.system(size: 12)).foregroundStyle(settingsSecondary).lineLimit(6)
                    }
                }
            } else if let excerpt = pull.excerpt {
                block(title: "Description") {
                    Text(excerpt).font(.system(size: 12)).foregroundStyle(settingsPrimary).lineLimit(8)
                }
            } else if summarizer.isPending(pull.id) {
                block(title: "Summary", generated: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach([248, 272, 180], id: \.self) { width in
                            RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: Theme.fieldFill)).frame(width: CGFloat(width), height: 8)
                        }
                    }
                    .padding(.top, 2)
                    .accessibilityLabel("Writing a summary")
                }
            } else {
                block(title: "Description") {
                    Text("No description.").font(.system(size: 12)).foregroundStyle(settingsTertiary)
                }
            }
        }
    }

    private func block<Content: View>(title: String, generated: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11)).foregroundStyle(settingsTertiary)
                if generated {
                    Image(systemName: "apple.intelligence").font(.system(size: 10)).foregroundStyle(settingsTertiary)
                        .accessibilityLabel("written by Apple Intelligence")
                }
            }
            .help(generated ? "Summarized on this Mac by Apple Intelligence" : "")
            content()
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Facts

    private var facts: [PreviewFact] {
        var rows: [PreviewFact] = []
        if let head = pull.headRef, let base = pull.baseRef {
            rows.append(PreviewFact(label: "Branch", value: Text("""
                \(Text(head).font(.mono(size: 11)))\
                \(Text("  →  ").foregroundStyle(settingsTertiary))\
                \(Text(base).font(.mono(size: 11)).foregroundStyle(settingsSecondary))
                """), help: "\(head) into \(base)"))
        }
        var changes = Text("\(Text(verbatim: "+\(pull.additions) −\(pull.deletions)").font(.mono(size: 11)))")
        if pull.changedFiles > 0 {
            changes = Text("\(changes)\(Text("  ·  \(pull.changedFiles == 1 ? "1 file" : "\(pull.changedFiles) files")").foregroundStyle(settingsSecondary))")
        }
        rows.append(PreviewFact(label: "Changes", value: changes))
        if !pull.areas.isEmpty {
            let shown = pull.areas.prefix(5)
            var lines = shown.map { area in
                Text("\(Text(area.name).font(.mono(size: 11)))\(Text("  \(area.count)").font(.mono(size: 11)).foregroundStyle(settingsTertiary))")
            }
            if pull.areas.count > shown.count {
                lines.append(Text("\(pull.areas.count - shown.count) more").foregroundStyle(settingsTertiary))
            }
            rows.append(PreviewFact(label: "Areas", value: lines.dropFirst().reduce(lines[0]) { Text("\($0)\n\($1)") },
                                    accessibilityLabel: pull.areas.map { "\($0.name), \($0.count == 1 ? "1 file" : "\($0.count) files")" }.joined(separator: "; ")))
        }
        if let color = GitHubStyle.color(pull.checks), let label = GitHubStyle.label(pull.checks) {
            rows.append(PreviewFact(label: "Checks", value: Text("""
                \(Text(Image(systemName: "circle.fill")).font(.system(size: 7)).foregroundStyle(Color(nsColor: color)))\
                \(Text("  " + label.prefix(1).uppercased() + label.dropFirst()))
                """), accessibilityLabel: label.prefix(1).uppercased() + label.dropFirst()))
        }
        if let reviews = reviewLines { rows.append(PreviewFact(label: "Reviews", value: reviews, accessibilityLabel: reviewSpeech)) }
        if !pull.labels.isEmpty {
            rows.append(PreviewFact(label: "Labels", value: Text(pull.labels.joined(separator: ", "))))
        }
        if pull.commentCount > 0 {
            rows.append(PreviewFact(label: "Comments", value: Text("\(pull.commentCount)").font(.system(size: 12).monospacedDigit())))
        }
        if let updated = pull.updatedAt {
            rows.append(PreviewFact(label: "Updated", value: Text(RelativeAge.long(since: updated, now: now)),
                                    help: updated.formatted(date: .abbreviated, time: .shortened)))
        }
        return rows
    }

    private var reviewSpeech: String {
        var parts: [String] = []
        let approved = pull.reviews.filter { $0.state == .approved }.map(\.login)
        let changes = pull.reviews.filter { $0.state == .changesRequested }.map(\.login)
        if !approved.isEmpty { parts.append("approved by \(approved.joined(separator: ", "))") }
        if !changes.isEmpty { parts.append("changes requested by \(changes.joined(separator: ", "))") }
        if !pull.pendingReviewers.isEmpty { parts.append("waiting on \(pull.pendingReviewers.joined(separator: ", "))") }
        return parts.isEmpty ? "No reviews yet" : parts.joined(separator: "; ")
    }

    /// Each reviewer's latest decision as a convention glyph and login, then who hasn't reviewed yet.
    private var reviewLines: Text? {
        var lines: [Text] = pull.reviews.compactMap { review in
            let mark: (String, NSColor)? = switch review.state {
            case .approved: ("checkmark", Theme.pass)
            case .changesRequested: ("exclamationmark", Theme.fail)
            case .commented: nil
            }
            guard let mark else { return nil }
            return Text("""
                \(Text(Image(systemName: mark.0)).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color(nsColor: mark.1)))\
                \(Text("  " + review.login).font(.mono(size: 11)))
                """)
        }
        let waiting = pull.pendingReviewers
        if !waiting.isEmpty {
            lines.append(Text("Waiting on \(Text(waiting.joined(separator: ", ")).font(.mono(size: 11)))").foregroundStyle(settingsSecondary))
        }
        if lines.isEmpty, tab == .mine, pull.reviewDecision == "REVIEW_REQUIRED" {
            lines.append(Text("No reviews yet").foregroundStyle(settingsSecondary))
        }
        guard let first = lines.first else { return nil }
        return lines.dropFirst().reduce(first) { Text("\($0)\n\($1)") }
    }
}
