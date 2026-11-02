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
    /// Folded away by default: with one section the sidebar has nothing to choose between.
    var showsSidebar = UserDefaults.standard.bool(forKey: "HomeSidebarShown") {
        didSet { UserDefaults.standard.set(showsSidebar, forKey: "HomeSidebarShown") }
    }
    let reviews: ReviewsModel

    init(open: @escaping (URL, PageOpenTarget) -> Void) { reviews = ReviewsModel(open: open) }

    /// The count a section shows in the sidebar, if any.
    func count(_ section: Section) -> Int? {
        switch section {
        case .reviews:
            let github = GitHubService.shared
            return github.isSignedIn && github.pullsUpdatedAt != nil ? github.pulls.reviewRequested.count : nil
        }
    }
}

/// Where a link on the home page opens. Pull requests open in a new tab by default, so Reviews stays put.
enum PageOpenTarget {
    /// A new tab, brought to the front.
    case newTab
    /// A new tab behind this one: ⌘-click and ⌘Return.
    case backgroundTab
    /// This tab, replacing the home page.
    case here

    /// A plain click or Return opens a new tab; holding ⌘ opens it in the background.
    static func forClick(command: Bool) -> PageOpenTarget { command ? .backgroundTab : .newTab }

    /// For a click handler, from the event being handled.
    static var forCurrentEvent: PageOpenTarget { forClick(command: NSApp.currentEvent?.modifierFlags.contains(.command) ?? false) }
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

    static func make(open: @escaping (URL, PageOpenTarget) -> Void) -> HomeHostingView {
        let view = HomeHostingView(rootView: HomePage(model: HomePageModel(open: open)))
        // The window sets the frame; the page scrolls rather than sizing the window.
        view.sizingOptions = []
        return view
    }
}

struct HomePage: View {
    @Bindable var model: HomePageModel
    @State private var width: CGFloat = 0

    /// Below this the sidebar folds away, its toggle with it, and the section takes the page.
    private static let sidebarMinimumPageWidth: CGFloat = 900

    private var fitsSidebar: Bool { width >= Self.sidebarMinimumPageWidth }

    var body: some View {
        HStack(spacing: 0) {
            if fitsSidebar && model.showsSidebar {
                sidebar
                VerticalRule()
            }
            switch model.section {
            case .reviews: ReviewsSection(model: model.reviews, sidebarShown: fitsSidebar ? $model.showsSidebar : nil)
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
                            Text("\(count)").font(.mono(size: 10, weight: .medium)).foregroundStyle(settingsTertiary)
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

/// Shows and hides the home page's sidebar; a section puts it before its title.
struct SidebarToggle: View {
    @Binding var isShown: Bool

    var body: some View {
        let label = isShown ? "Hide Sidebar" : "Show Sidebar"
        Button { isShown.toggle() } label: {
            Image(systemName: "sidebar.left").font(.system(size: 13, weight: .medium)).foregroundStyle(settingsSecondary)
                .frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverFillButtonStyle(radius: Theme.controlRadius))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A one-pixel vertical hairline.
struct VerticalRule: View {
    @Environment(\.pixelLength) private var pixel
    var body: some View { Rectangle().fill(Color(nsColor: Theme.hairline)).frame(width: pixel) }
}
