import BrowserKit
import SwiftUI

struct DevNetworkView: View {
    @Bindable var model: DevPanelModel
    let record: DevToolsRecord

    private var requests: [NetworkRequest] {
        let rows = record.requests.filter {
            (model.networkFilter.isEmpty || ($0.url + " " + $0.method).localizedCaseInsensitiveContains(model.networkFilter)) &&
            (!model.networkFailures || ($0.status ?? 0) >= 400 || !$0.error.isEmpty) && (model.networkKind == "All types" || $0.kind == model.networkKind)
        }
        switch model.networkSorting {
        case "Name": return rows.sorted { $0.url < $1.url }
        case "Status": return rows.sorted { ($0.status ?? 0) > ($1.status ?? 0) }
        case "Duration": return rows.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
        default: return rows.reversed()
        }
    }
    private var resources: [ResourceEntry] {
        let rows = record.resources.filter {
            (model.networkFilter.isEmpty || $0.url.localizedCaseInsensitiveContains(model.networkFilter)) &&
            (!model.networkFailures || $0.status >= 400) && (model.networkKind == "All types" || $0.type == model.networkKind)
        }
        switch model.networkSorting {
        case "Name": return rows.sorted { $0.url < $1.url }
        case "Status": return rows.sorted { $0.status > $1.status }
        case "Duration": return rows.sorted { $0.duration > $1.duration }
        default: return rows.reversed()
        }
    }
    private var types: [String] { Array(Set(model.networkSource == "Resources" ? record.resources.map(\.type) : record.requests.map(\.kind))).sorted() }

    var body: some View {
        VStack(spacing: 0) {
            DevToolbar {
                Picker("Capture source", selection: $model.networkSource) { Text("Resources").tag("Resources"); Text("Fetch / XHR").tag("Fetch / XHR") }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 174).tint(Color(nsColor: Theme.controlSelectionTint))
                DevSearch(text: $model.networkFilter, prompt: "Search requests")
                    .onSubmit { model.networkFocusRequest += 1 }.help("Press Return to move into the request list.")
                Menu {
                    Toggle("Failures only", isOn: $model.networkFailures)
                    Picker("Type", selection: $model.networkKind) { Text("All types").tag("All types"); ForEach(types, id: \.self) { Text($0).tag($0) } }
                } label: { Text(model.networkFailures ? "Failures" : model.networkKind) }
                Menu { Picker("Sort requests", selection: $model.networkSorting) {
                    ForEach(["Newest", "Name", "Status", "Duration"], id: \.self) { Text($0).tag($0) }
                } } label: { Label(model.networkSorting, systemImage: "arrow.up.arrow.down") }
                Button(record.captureID == nil ? "Resume capture" : "Pause capture", systemImage: record.captureID == nil ? "record.circle" : "pause.circle") {
                    if record.captureID == nil { model.networkSource = "Fetch / XHR"; model.startCapture() } else { model.pauseCapture() }
                }.disabled(model.origin == nil)
                Button("Clear") { model.clearNetwork() }
            }
            DevRule()
            if model.networkSource == "Fetch / XHR" { apiContent } else { resourceContent }
            DevRule()
            HStack {
                Text(model.networkSource == "Resources" ? "\(resources.count) resources · \(devBytes(resources.reduce(0) { $0 + $1.bytesTransferred })) reported transfer" : "\(requests.count) captured requests")
                Spacer()
                Text(record.captureID != nil ? "Capture on · this origin only" : "Detailed capture paused")
                    .foregroundStyle(record.captureID != nil ? Color(nsColor: Theme.accentText) : devSecondary)
            }.font(.system(size: 10)).foregroundStyle(devSecondary).padding(.horizontal, 12).frame(height: 24)
        }
        .onChange(of: model.networkSource) { _, _ in model.networkKind = "All types" }
    }

    private var apiContent: some View {
        DevSplit(hasSelection: model.selectedRequest != nil, clearSelection: { model.selectedRequest = nil }) {
            DevRows(rows: requests, selection: $model.selectedRequest, focusRequest: model.networkFocusRequest) {
                apiColumns(method: Text("Method"), name: Text("Name"), status: Text("Status"), time: Text("Time"))
            } cell: { row in
                apiColumns(method: Text(row.method).foregroundStyle(devSecondary),
                           name: Text(name(row.url)).foregroundStyle(devPrimary),
                           status: Text(row.status.map(String.init) ?? (row.error.isEmpty ? "…" : "Failed"))
                            .foregroundStyle(row.id == model.selectedRequest ? devPrimary : (row.status ?? 0) >= 400 || !row.error.isEmpty ? Color(nsColor: Theme.fail) : devSecondary),
                           time: Text(row.duration.map(devMS) ?? "…").foregroundStyle(devSecondary))
                    .font(.system(size: 12, design: .monospaced)).help(row.url)
            }
                .overlay { if requests.isEmpty { DevEmpty(title: record.requests.isEmpty ? "Capture an API request" : "No matching requests",
                    detail: record.captureID == nil ? "Resume capture, then reproduce the request. Headers and bounded text payloads stay in memory." : "Fetch and XHR requests from this page appear here while the tools are open. Reload to include requests made during page load.", symbol: "network") } }
        } detail: {
            if let row = record.requests.first(where: { $0.id == model.selectedRequest }) { requestDetail(row) }
            else { DevEmpty(title: "Select a request", detail: "Inspect its headers, payload and response. Browser-managed credentials and iframe requests are unavailable.", symbol: "network") }
        }
    }

    private var resourceContent: some View {
        let rows = resources
        let end = max(1, rows.map { $0.start + $0.duration }.max() ?? 1)
        return DevSplit(hasSelection: model.selectedResource != nil, clearSelection: { model.selectedResource = nil }) {
            GeometryReader { geometry in
                DevRows(rows: rows, selection: $model.selectedResource, focusRequest: model.networkFocusRequest) {
                    resourceColumns(name: Text("Name"), status: Text("Status"), type: Text("Type"), time: Text("Time"),
                                    wide: geometry.size.width >= 620) { Text("Timing") }
                } cell: { row in
                    resourceColumns(name: Text(name(row.url)).foregroundStyle(devPrimary),
                                    status: Text(row.status == 0 ? "—" : "\(row.status)").foregroundStyle(devSecondary),
                                    type: Text(row.type).foregroundStyle(devSecondary),
                                    time: Text(devMS(row.duration)).foregroundStyle(devSecondary), wide: geometry.size.width >= 620) {
                        GeometryReader { geo in
                            Rectangle().fill(Color(nsColor: row.status >= 400 ? Theme.fail : Theme.neutral(6)))
                                .frame(width: max(1, geo.size.width * row.duration / end), height: 5)
                                .offset(x: geo.size.width * row.start / end, y: 5)
                        }.frame(height: 16)
                    }.font(.system(size: 11, design: .monospaced)).help(row.url)
                }
            }
                .overlay { if rows.isEmpty { DevEmpty(title: record.resources.isEmpty ? "Waiting for resources" : "No matching resources",
                    detail: "Reload or interact with the page to collect resource timings.", symbol: "network") } }
        } detail: {
            if let row = record.resources.first(where: { $0.id == model.selectedResource }) {
                ScrollView { VStack(alignment: .leading, spacing: 14) {
                    DevHeading(title: "Resource", action: "Copy URL", copy: row.url)
                    DevCode(text: row.url)
                    DevPairs(rows: [("Type", row.type), ("Status", row.status == 0 ? "Unavailable" : "\(row.status)"),
                                    ("Start", devMS(row.start) + " after navigation"), ("Duration", devMS(row.duration)),
                                    ("Delivery", delivery(row)), ("Transfer", row.transferSize > 0 ? devBytes(row.transferSize) : "Not reported"),
                                    ("Encoded body", row.encodedSize > 0 ? devBytes(row.encodedSize) : "Not reported")])
                    DevRule()
                    Text("WebKit may withhold cross-origin timing and size data. Bars share a navigation-relative scale. Fetch / XHR captures headers and payloads while the tools are open.")
                        .font(.system(size: 11)).foregroundStyle(devSecondary)
                }.padding(16) }
            } else { DevEmpty(title: "Select a resource", detail: "Read its URL, timing and available delivery information.", symbol: "chart.bar.xaxis") }
        }
    }

    private func apiColumns(method: some View, name: some View, status: some View, time: some View) -> some View {
        HStack(spacing: 12) {
            method.frame(width: 64, alignment: .leading)
            name.lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            status.frame(width: 60, alignment: .trailing)
            time.frame(width: 66, alignment: .trailing)
        }
    }

    private func resourceColumns<Timing: View>(name: some View, status: some View, type: some View, time: some View,
                                               wide: Bool, @ViewBuilder timing: () -> Timing) -> some View {
        HStack(spacing: 12) {
            name.lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            status.frame(width: 60, alignment: .trailing)
            if wide { type.lineLimit(1).frame(width: 60, alignment: .leading) }
            time.frame(width: 66, alignment: .trailing)
            if wide { timing().frame(width: 100, alignment: .leading) }
        }
    }

    private func requestDetail(_ row: NetworkRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DevHeading(title: row.method + " " + name(row.url), action: "Copy as cURL", copy: row.curl)
                Picker("Request details", selection: $model.networkDetail) {
                    ForEach(["Overview", "Headers", "Payload", "Response"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize(horizontal: false, vertical: true)
                    .tint(Color(nsColor: Theme.controlSelectionTint))
                switch model.networkDetail {
                case "Headers":
                    headerSection("Request headers", rows: row.requestHeaders)
                    Text("Only script-visible headers are captured. Browser-added cookies and credentials are not included in cURL.").font(.system(size: 11)).foregroundStyle(devSecondary)
                    DevRule()
                    headerSection("Response headers", rows: row.responseHeaders)
                case "Payload": bodyDetail(row.requestBody)
                case "Response": bodyDetail(row.responseBody)
                default:
                    DevHeading(title: "Request URL", copy: row.url)
                    DevCode(text: row.url)
                    DevPairs(rows: [("Method", row.method), ("Status", row.status.map(String.init) ?? (row.error.isEmpty ? "Pending" : "Failed")),
                                    ("Duration", row.duration.map(devMS) ?? "Pending"), ("Source", row.kind)])
                    if !row.error.isEmpty { DevCode(text: row.error).foregroundStyle(Color(nsColor: Theme.fail)) }
                    let query = URLComponents(string: row.url)?.queryItems ?? []
                    if !query.isEmpty { DevRule(); DevHeading(title: "Query parameters"); DevPairs(rows: query.map { ($0.name, $0.value ?? "") }) }
                }
            }.padding(16)
        }
    }

    @ViewBuilder private func bodyDetail(_ body: CapturedBody) -> some View {
        HStack {
            Text(body.mimeType.isEmpty ? "Text payload" : body.mimeType).font(.system(size: 11)).foregroundStyle(devSecondary)
            Spacer()
            Toggle("Raw", isOn: $model.networkRawBody).toggleStyle(.checkbox).font(.system(size: 11)).tint(Color(nsColor: Theme.controlSelectionTint))
            Button("Copy") { devCopy(body.text) }.buttonStyle(.borderless).disabled(body.text.isEmpty)
        }
        if !body.note.isEmpty { Text(body.note).font(.system(size: 11)).foregroundStyle(devSecondary) }
        if !body.text.isEmpty { DevCode(text: model.networkRawBody ? body.text : body.formattedText) }
    }
    @ViewBuilder private func headerSection(_ title: String, rows: [DebugHeader]) -> some View {
        DevHeading(title: title, copy: rows.map { $0.name + ": " + $0.value }.joined(separator: "\n"))
        if rows.isEmpty { Text("No headers available").font(.system(size: 11)).foregroundStyle(devSecondary) }
        else { DevPairs(rows: rows.map { ($0.name, $0.value) }) }
    }
    private func name(_ value: String) -> String {
        guard let url = URL(string: value) else { return value }
        return (url.path.isEmpty ? "/" : url.path) + (url.query.map { "?" + $0 } ?? "")
    }
    private func delivery(_ row: ResourceEntry) -> String {
        switch row.delivery { case .cached: "Cached"; case .revalidated: "Revalidated"; case .network: "Network"; case .unknown: "Unknown" }
    }
}
