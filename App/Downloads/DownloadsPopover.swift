import AppKit
import SwiftUI

struct DownloadsPopover: View {
    let manager: DownloadManager
    var retry: (DownloadManager.Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Clear") { manager.clearFinished() }.controlSize(.small)
                    .disabled(!manager.items.contains { $0.state != .running })
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if manager.items.isEmpty {
                Text("No downloads yet.").font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.textTertiary)).padding(14)
            }
            ForEach(manager.items) { item in
                DownloadRow(item: item, manager: manager, retry: retry)
                if item.id != manager.items.last?.id { Divider().padding(.leading, 40) }
            }
        }
        .frame(width: 340)
        .tint(Color(nsColor: Theme.accent))
    }
}

private struct DownloadRow: View {
    let item: DownloadManager.Item
    let manager: DownloadManager
    var retry: (DownloadManager.Item) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename.isEmpty ? (item.source?.lastPathComponent ?? "Download") : item.filename)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                switch item.state {
                case .running:
                    ProgressView(value: item.fraction).progressViewStyle(.linear).controlSize(.small)
                case .finished:
                    Text(size).font(.system(size: 11).monospacedDigit()).foregroundStyle(Color(nsColor: Theme.textTertiary))
                case .failed(let message):
                    Text(message).font(.system(size: 11)).foregroundStyle(Color(nsColor: Theme.fail)).lineLimit(2)
                case .cancelled:
                    Text("Cancelled").font(.system(size: 11)).foregroundStyle(Color(nsColor: Theme.textTertiary))
                }
            }
            Spacer(minLength: 4)
            switch item.state {
            case .running:
                Button { manager.cancel(item) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).help("Cancel")
            case .finished:
                Button { manager.reveal(item) } label: { Image(systemName: "magnifyingglass.circle.fill") }
                    .buttonStyle(.borderless).help("Show in Finder")
            case .failed, .cancelled:
                Button { retry(item) } label: { Image(systemName: "arrow.clockwise.circle.fill") }
                    .buttonStyle(.borderless).help("Retry")
            }
        }
        .foregroundStyle(Color(nsColor: Theme.textPrimary))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { manager.open(item) }
    }

    private var icon: NSImage {
        if let destination = item.destination, item.state == .finished { return NSWorkspace.shared.icon(forFile: destination.path) }
        return NSWorkspace.shared.icon(for: .data)
    }

    private var size: String {
        item.totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file) : "Done"
    }
}

@MainActor
enum DownloadsHosting {
    static func show(_ view: DownloadsPopover, in popover: PopoverPresenter, from anchor: NSView) { popover.show(view, from: anchor) }
}
