import BrowserKit
import SwiftUI

private struct StorageRow: Identifiable {
    let id: String
    let key: String
    let value: String
    var item: StorageItem?
    var cookie: HTTPCookie?
}

private struct StorageEdit: Identifiable {
    let id = UUID()
    let area: String
    let item: StorageItem?
}

struct DevStorageView: View {
    @Bindable var model: DevPanelModel
    @State private var editor: StorageEdit?
    @State private var deleting = false

    private var rows: [StorageRow] {
        let all: [StorageRow]
        if model.storageArea == "Cookies" {
            all = model.cookies.map { StorageRow(id: $0.domain + "\n" + $0.path + "\n" + $0.name, key: $0.name, value: $0.value, cookie: $0) }
        } else {
            all = (model.storageArea == "Local Storage" ? model.localStorage : model.sessionStorage).map { StorageRow(id: $0.key, key: $0.key, value: $0.value, item: $0) }
        }
        return all.filter { model.storageFilter.isEmpty || ($0.key + " " + $0.value).localizedCaseInsensitiveContains(model.storageFilter) }
    }
    private var selected: StorageRow? { rows.first { $0.id == model.selectedStorage } }
    private var storageArea: String { model.storageArea == "Local Storage" ? "local" : "session" }

    var body: some View {
        VStack(spacing: 0) {
            DevToolbar {
                Picker("Storage area", selection: $model.storageArea) {
                    ForEach(["Cookies", "Local Storage", "Session Storage"], id: \.self) { Text($0).tag($0) }
                }.frame(width: 150)
                DevSearch(text: $model.storageFilter, prompt: "Search keys and values")
                    .onSubmit { model.storageFocusRequest += 1 }.help("Press Return to move into the storage list.")
                Button("Refresh", systemImage: "arrow.clockwise") { model.refreshStorage() }.disabled(model.storageLoading)
                if model.storageArea != "Cookies" { Button("Add entry", systemImage: "plus") { editor = StorageEdit(area: storageArea, item: nil) }.disabled(model.storageLoading) }
                Menu {
                    Button("Clear Site Data…", role: .destructive) { model.perform(.clearSiteData) }
                } label: { Label("Site data", systemImage: "ellipsis.circle") }
                if model.storageLoading { ProgressView().controlSize(.mini) }
            }
            DevRule()
            if let error = model.storageError {
                HStack { Text(error).textSelection(.enabled); Spacer() }.font(.system(size: 11)).foregroundStyle(Color(nsColor: Theme.fail)).padding(12)
                DevRule()
            }
            DevSplit(hasSelection: selected != nil, clearSelection: { model.selectedStorage = nil }) {
                DevRows(rows: rows, selection: $model.selectedStorage, focusRequest: model.storageFocusRequest) {
                    storageColumns(key: Text("Name"), value: Text("Value"))
                } cell: { row in
                    storageColumns(key: Text(row.key).foregroundStyle(devPrimary), value: Text(row.value).foregroundStyle(devSecondary))
                        .font(.system(size: 12, design: .monospaced))
                }
                    .overlay { if rows.isEmpty && !model.storageLoading { DevEmpty(title: model.storageFilter.isEmpty ? "No entries" : "No matching entries",
                        detail: model.storageFilter.isEmpty ? "\(model.storageArea) for this site will appear here. Refresh after the page changes storage." : "Try another key or value.", symbol: "externaldrive") } }
            } detail: {
                if let row = selected { details(row) }
                else { DevEmpty(title: "Select an entry", detail: "Read and copy full values. Local and session entries can be edited.", symbol: "key") }
            }
            DevRule()
            HStack { Text("\(rows.count) entries"); Spacer(); Text(model.storageArea == "Cookies" ? "Matching cookie domains · includes HttpOnly" : "Current origin · up to 500 entries · values up to 64K characters") }
                .font(.system(size: 10)).foregroundStyle(devSecondary).padding(.horizontal, 12).frame(height: 24)
        }
        .onAppear { model.refreshStorage() }
        .onChange(of: model.storageArea) { _, _ in model.selectedStorage = nil; model.storageError = nil }
        .onChange(of: model.tab?.devTools.navigationID) { _, _ in model.selectedStorage = nil; editor = nil; deleting = false }
        .sheet(item: $editor) { request in StorageEditor(model: model, area: request.area, item: request.item) }
        .confirmationDialog("Delete \(selected?.key ?? "entry")?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                guard let row = selected else { return }
                if let cookie = row.cookie { model.delete(cookie) }
                else if let item = row.item { model.writeStorage(area: storageArea, key: item.key, value: nil, expected: item.value) { _ in } }
                model.selectedStorage = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the selected value from the inspected site.") }
    }

    private func storageColumns(key: some View, value: some View) -> some View {
        HStack(spacing: 12) {
            key.lineLimit(1).truncationMode(.middle).frame(width: 160, alignment: .leading)
            value.lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func details(_ row: StorageRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DevHeading(title: row.key, action: "Copy value", copy: row.value)
                HStack {
                    if let item = row.item {
                        Button("Edit value") { editor = StorageEdit(area: storageArea, item: item) }.disabled(item.truncated)
                    }
                    Button("Delete…", role: .destructive) { deleting = true }.disabled(row.item?.truncated == true)
                }.controlSize(.small)
                if row.item?.truncated == true { Text("This value is truncated. Editing and deletion are disabled to protect the original data.").font(.system(size: 11)).foregroundStyle(devSecondary) }
                if let cookie = row.cookie {
                    DevPairs(rows: [("Domain", cookie.domain), ("Path", cookie.path), ("Secure", cookie.isSecure ? "Yes" : "No"),
                                    ("HttpOnly", cookie.isHTTPOnly ? "Yes" : "No"), ("Expires", cookie.expiresDate?.formatted() ?? "Session")])
                    DevRule()
                }
                DevCode(text: devPretty(row.value))
            }.padding(16)
        }
    }
}

private struct StorageEditor: View {
    @Bindable var model: DevPanelModel
    let area: String
    let item: StorageItem?
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var value = ""
    @State private var saving = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item == nil ? "Add storage entry" : "Edit storage value").font(.system(size: 15, weight: .semibold))
            TextField("Key", text: $key).textFieldStyle(.roundedBorder).disabled(item != nil).accessibilityLabel("Storage key")
            TextEditor(text: $value).font(.system(size: 12, design: .monospaced)).frame(minHeight: 220)
                .border(Color(nsColor: Theme.hairline)).accessibilityLabel("Storage value")
            if let error = model.storageError { Text(error).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.fail)) }
            HStack {
                Text("Changes apply to the current origin.").font(.system(size: 11)).foregroundStyle(devSecondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    saving = true
                    model.writeStorage(area: area, key: key, value: value, expected: item?.value, creating: item == nil) { success in
                        saving = false; if success { dismiss() }
                    }
                }.keyboardShortcut(.defaultAction).disabled(saving || key.isEmpty).tint(Color(nsColor: Theme.controlSelectionTint))
            }
        }.padding(20).frame(width: 540).onAppear { key = item?.key ?? ""; value = item?.value ?? ""; model.storageError = nil }
    }
}
