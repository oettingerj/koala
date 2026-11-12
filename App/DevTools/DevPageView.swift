import BrowserKit
import Eucalyptus
import SwiftUI

struct DevPageView: View {
    @Bindable var model: DevPanelModel
    @Bindable var tab: BrowserKit.Tab
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DevHeading(title: "Page tools")
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                    GridRow {
                        Text("Appearance")
                        Picker("Appearance", selection: $tab.colorSchemeOverride) {
                            Text("System").tag(String?.none); Text("Light").tag(String?.some("light")); Text("Dark").tag(String?.some("dark"))
                        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 240).tint(Color(nsColor: Theme.controlSelectionTint))
                    }
                    GridRow {
                        Text("Viewport width")
                        Picker("Viewport width", selection: $tab.viewportWidth) {
                            Text("Window").tag(CGFloat?.none)
                            ForEach([390, 768, 1024, 1440], id: \.self) { Text("\($0) pt").tag(CGFloat?.some(CGFloat($0))) }
                        }.labelsHidden().frame(maxWidth: 240)
                    }
                    GridRow {
                        Text("JavaScript")
                        Toggle("Enable JavaScript (reloads page)", isOn: Binding(get: { tab.javaScriptEnabled }, set: { tab.javaScriptEnabled = $0; tab.reload() }))
                            .toggleStyle(.checkbox).tint(Color(nsColor: Theme.controlSelectionTint))
                    }
                }.font(.system(size: 12)).foregroundStyle(devSecondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { pageActions }
                    VStack(alignment: .leading, spacing: 10) { pageActions }
                }.controlSize(.small)
                DevRule()
                DevHeading(title: "Observed performance")
                DevPairs(rows: [("TTFB", tab.devTools.vitals.ttfb.map(devMS) ?? "Unavailable"),
                                ("LCP", tab.devTools.vitals.lcp.map(devMS) ?? "Unavailable"),
                                ("Layout shift (CLS)", tab.devTools.vitals.cls.map { String(format: "%.3f", $0) } ?? "Unavailable"),
                                ("Max interaction", tab.devTools.vitals.inp.map(devMS) ?? "Unavailable"),
                                ("Load event", tab.devTools.vitals.load.map(devMS) ?? "Unavailable")])
                Text("Page-local observations depend on WebKit support. Max interaction is the longest observed interaction, not an INP percentile. Layout shift uses session windows. These values are not field performance scores.")
                    .font(.system(size: 11)).foregroundStyle(devSecondary).frame(maxWidth: 660, alignment: .leading)
                DevRule()
                if let response = tab.devTools.mainResponse {
                    DevHeading(title: "Document response", action: "Copy headers", copy: response.headers.map { $0.0 + ": " + $0.1 }.joined(separator: "\n"))
                    DevPairs(rows: [("URL", response.url?.absoluteString ?? "Unavailable"), ("Status", response.statusCode == 0 ? "Unavailable" : "\(response.statusCode)"),
                                    ("Content type", response.mimeType ?? "Unavailable")])
                    DevPairs(rows: response.headers)
                } else { Text("Load an HTTP page to see its document response.").font(.system(size: 12)).foregroundStyle(devSecondary) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var pageActions: some View {
        Button("Reload from Origin", systemImage: "arrow.clockwise") { model.perform(.hardReload) }
        Button("View Source", systemImage: "chevron.left.forwardslash.chevron.right") { model.perform(.viewSource) }
        Button("Copy Screenshot", systemImage: "camera") { model.perform(.copyScreenshot) }
        Button("Save PDF…", systemImage: "doc") { model.perform(.savePDF) }
    }
}
