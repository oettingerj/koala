import SwiftUI

/// One label and value in a preview pane's facts grid.
struct PreviewFact: Identifiable {
    let label: String
    let value: Text
    var help: String?
    /// What VoiceOver reads for the value when its symbols and layout don't speak for themselves.
    var accessibilityLabel: String?
    var id: String { label }
}

/// The facts grid shared by the command bar's preview and the Reviews detail pane: 11pt tertiary
/// labels, 12pt primary values, aligned on their first baselines.
struct PreviewFactGrid: View {
    let facts: [PreviewFact]
    var lineLimit = 2

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
            ForEach(facts) { fact in
                GridRow {
                    Text(fact.label)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: Theme.textTertiary))
                        .gridColumnAlignment(.leading)
                    fact.value
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: Theme.textPrimary))
                        .lineLimit(lineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(fact.help ?? "")
                }
                .accessibilityElement(children: .combine)
                .modifier(SpokenValue(text: fact.accessibilityLabel.map { "\(fact.label), \($0)" }))
            }
        }
    }
}

/// Replaces the combined label only when a fact gives its own words.
private struct SpokenValue: ViewModifier {
    let text: String?
    func body(content: Content) -> some View {
        if let text { content.accessibilityLabel(text) } else { content }
    }
}
