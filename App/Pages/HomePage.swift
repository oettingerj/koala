import AppKit
import BrowserKit
import SwiftUI

/// What a blank tab shows: a sidebar of sections beside the selected one. The address field keeps
/// the caret, so typing an address on a new tab still goes straight there.
@MainActor
@Observable
final class HomePageModel {
    enum Section: String, CaseIterable, Identifiable {
        case reviews
        var id: String { rawValue }
        var title: String { "Reviews" }
        var symbol: String { "arrow.triangle.pull" }
    }

    var section: Section = .reviews
    let reviews: ReviewsModel

    init(open: @escaping (URL, Bool) -> Void) { reviews = ReviewsModel(open: open) }

    /// The count a section shows in the sidebar, if any.
    func count(_ section: Section) -> Int? {
        switch section {
        case .reviews:
            let github = GitHubService.shared
            return github.isSignedIn && github.pullsUpdatedAt != nil ? github.pulls.reviewRequested.count : nil
        }
    }
}

final class HomeHostingView: NSHostingView<HomePage>, SearchablePage, RefreshablePage {
    func focusSearch() {
        switch rootView.model.section {
        case .reviews: rootView.model.reviews.focusRequest += 1
        }
    }

    func refresh() {
        switch rootView.model.section {
        case .reviews: GitHubService.shared.refreshPulls()
        }
    }

    static func make(open: @escaping (URL, Bool) -> Void) -> HomeHostingView {
        let view = HomeHostingView(rootView: HomePage(model: HomePageModel(open: open)))
        // The window sets the frame; the page scrolls rather than sizing the window.
        view.sizingOptions = []
        return view
    }
}

struct HomePage: View {
    @Bindable var model: HomePageModel
    @State private var width: CGFloat = 0

    /// Below this the sidebar folds away and the section takes the page.
    private static let sidebarMinimumPageWidth: CGFloat = 900

    var body: some View {
        HStack(spacing: 0) {
            if width >= Self.sidebarMinimumPageWidth {
                sidebar
                VerticalRule()
            }
            switch model.section {
            case .reviews: ReviewsSection(model: model.reviews)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: Theme.chromeSurface))
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(HomePageModel.Section.allCases) { section in
                let isCurrent = model.section == section
                Button { model.section = section } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.symbol).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isCurrent ? settingsPrimary : settingsTertiary)
                            .frame(width: 16).accessibilityHidden(true)
                        Text(section.title)
                        Spacer(minLength: 4)
                        if let count = model.count(section), count > 0 {
                            Text("\(count)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(settingsTertiary)
                        }
                    }
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? settingsPrimary : settingsSecondary)
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 5).fill(isCurrent ? Color(nsColor: Theme.hoverFill) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                .accessibilityValue(model.count(section).map { "\($0) waiting" } ?? "")
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.top, 24)
        .frame(width: 200)
    }
}

/// A one-pixel vertical hairline.
private struct VerticalRule: View {
    @Environment(\.pixelLength) private var pixel
    var body: some View { Rectangle().fill(Color(nsColor: Theme.hairline)).frame(width: pixel) }
}
