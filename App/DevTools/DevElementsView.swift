import BrowserKit
import SwiftUI

struct DevElementsView: View {
    @Bindable var model: DevPanelModel
    let record: DevToolsRecord
    var body: some View {
        VStack(spacing: 0) {
            DevToolbar {
                Button(record.isPicking ? "Cancel picking" : "Pick an element", systemImage: "scope") {
                    if record.isPicking { model.stopPicking() } else { model.pickElement() }
                }
                if record.isPicking { Text("Click an element on the page · Escape cancels").foregroundStyle(devSecondary) }
                else { Text("Main document and open shadow roots").foregroundStyle(devSecondary) }
            }
            DevRule()
            if let element = record.element {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(element.tag).font(.system(size: 13, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                            Spacer()
                            Text(String(format: "%.1f × %.1f px", element.width, element.height)).font(.system(size: 12, design: .monospaced)).foregroundStyle(devSecondary)
                        }
                        Text(element.ancestors.joined(separator: " › ")).font(.system(size: 11, design: .monospaced)).foregroundStyle(devSecondary).textSelection(.enabled)
                        DevHeading(title: "Selector", action: "Copy selector", copy: element.selector)
                        DevCode(text: element.selector)
                        Text("Selectors inside shadow roots are relative to that root. Iframe documents and closed shadow roots are not inspected.")
                            .font(.system(size: 11)).foregroundStyle(devSecondary)
                        DevRule()
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 32) { styles(element); attributes(element) }
                            VStack(alignment: .leading, spacing: 20) { styles(element); attributes(element) }
                        }
                        DevRule()
                        DisclosureGroup("Element HTML (up to 32,000 characters)") {
                            VStack(alignment: .leading, spacing: 10) {
                                DevHeading(title: "Outer HTML", copy: element.html)
                                DevCode(text: element.html)
                            }.padding(.top, 8)
                        }.font(.system(size: 12))
                    }.padding(16)
                }
            } else { DevEmpty(title: record.isPicking ? "Choose an element on the page" : "Inspect an element",
                             detail: "Pick an element to read its box dimensions, computed styles and accessibility attributes.", symbol: "scope") }
        }
    }
    private func styles(_ element: ElementSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) { DevHeading(title: "Computed styles"); DevPairs(rows: element.styles.map { ($0.name, $0.value) }) }
            .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
    }
    private func attributes(_ element: ElementSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DevHeading(title: "Identity & accessibility attributes")
            if element.attributes.isEmpty { Text("No identity or accessibility attributes").font(.system(size: 12)).foregroundStyle(devSecondary) }
            else { DevPairs(rows: element.attributes.map { ($0.name, $0.value) }) }
            Text("Attributes are a snapshot, not a computed accessible-name or accessibility audit.").font(.system(size: 11)).foregroundStyle(devSecondary)
        }.frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
    }
}
