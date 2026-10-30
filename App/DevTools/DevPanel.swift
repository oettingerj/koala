import AppKit
import BrowserKit
import SwiftUI

struct DevPanel: View {
    @Bindable var model: DevPanelModel

    static func host(model: DevPanelModel) -> NSHostingView<DevPanel> { NSHostingView(rootView: DevPanel(model: model)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            DevRule()
            if let tab = model.tab {
                Group {
                    switch model.section {
                    case .console: DevConsoleView(model: model, record: tab.devTools)
                    case .network: DevNetworkView(model: model, record: tab.devTools)
                    case .storage: DevStorageView(model: model)
                    case .page: DevPageView(model: model, tab: tab)
                    }
                }
                .id(tab.id)
            } else {
                DevEmpty(title: "No inspected page", detail: "Open a page to use developer tools.", symbol: "globe")
            }
            if let status = model.status {
                DevRule()
                HStack {
                    Image(systemName: "info.circle")
                    Text(status).textSelection(.enabled)
                    Spacer()
                    DevIcon("Dismiss message", symbol: "xmark") { model.status = nil }
                }.font(.system(size: 11)).foregroundStyle(devSecondary).padding(.horizontal, 12).padding(.vertical, 4)
            }
        }
        .background(Color(nsColor: Theme.chromeSurface))
        .foregroundStyle(devPrimary)
        .tint(Color(nsColor: Theme.accentText))
        .onChange(of: model.section) { _, section in
            if section == .storage { model.refreshStorage() }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) { tabs; Spacer(minLength: 8); target; windowActions }
            HStack(spacing: 2) { tabs; Spacer(minLength: 0); windowActions }
        }
        .padding(.horizontal, 8).frame(height: 36)
        .accessibilityElement(children: .contain).accessibilityLabel("Developer tools")
    }

    private var tabs: some View {
        ForEach(DevPanelModel.Section.allCases) { section in
            Button { model.section = section } label: {
                HStack(spacing: 5) {
                    Text(section.rawValue)
                    if section == .console, let count = model.tab?.devTools.errorCount, count > 0 {
                        Text("\(count)").font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(Color(nsColor: Theme.fail))
                    }
                }
                .font(.system(size: 12, weight: model.section == section ? .semibold : .regular))
                .foregroundStyle(model.section == section ? devPrimary : devSecondary)
                .padding(.horizontal, 9).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(model.section == section ? Color(nsColor: Theme.hoverFill) : .clear))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityAddTraits(model.section == section ? .isSelected : [])
        }
    }

    private var target: some View {
        HStack(spacing: 6) {
            if model.tab?.devTools.captureID != nil {
                Image(systemName: "record.circle").foregroundStyle(Color(nsColor: Theme.accent)).help("Detailed capture is active")
            }
            Text(model.origin ?? model.tab?.url?.host() ?? "No page").font(.mono(size: 11)).lineLimit(1)
                .help(model.tab?.url?.absoluteString ?? "No page")
        }.foregroundStyle(devSecondary).fixedSize()
    }

    private var windowActions: some View {
        HStack(spacing: 2) {
            DevIcon(model.isDetached ? "Dock tools in browser" : "Detach tools", symbol: model.isDetached ? "rectangle.bottomthird.inset.filled" : "arrow.up.right.square") {
                model.perform(model.isDetached ? .redock : .detach)
            }
            DevIcon("Close developer tools (⌥⌘J)", symbol: "xmark") { model.perform(.close) }
        }
    }
}
