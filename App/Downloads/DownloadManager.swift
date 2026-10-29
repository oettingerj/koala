import AppKit
import BrowserKit
import Observation
import WebKit

/// Every download this session, newest first, for the toolbar button and its popover.
@MainActor
@Observable
final class DownloadManager: NSObject {
    static let shared = DownloadManager()

    @MainActor
    @Observable
    final class Item: Identifiable {
        enum State: Equatable { case running, finished, failed(String), cancelled }

        let id = UUID()
        let source: URL?
        fileprivate(set) var filename = ""
        fileprivate(set) var destination: URL?
        fileprivate(set) var fraction: Double = 0
        fileprivate(set) var totalBytes: Int64 = 0
        fileprivate(set) var state: State = .running
        @ObservationIgnored fileprivate var download: WKDownload?
        @ObservationIgnored fileprivate var resumeData: Data?
        @ObservationIgnored fileprivate var progressObservation: NSKeyValueObservation?

        init(source: URL?) { self.source = source }
        var canRetry: Bool { if case .failed = state { true } else { state == .cancelled } }
    }

    private(set) var items: [Item] = []
    var activeCount: Int { items.filter { $0.state == .running }.count }

    static var folder: URL { Preferences.downloadFolder }

    func track(_ download: WKDownload) {
        let item = Item(source: download.originalRequest?.url)
        item.download = download
        download.delegate = self
        item.progressObservation = download.progress.observe(\.fractionCompleted) { [weak item] progress, _ in
            let fraction = progress.fractionCompleted
            let total = progress.totalUnitCount
            Task { @MainActor in
                item?.fraction = fraction
                item?.totalBytes = total
            }
        }
        items.insert(item, at: 0)
    }

    /// Bytes WebKit already holds, such as a PDF the viewer shows; written straight to the folder.
    func save(_ data: Data, suggestedFilename: String, from source: URL?) {
        let item = Item(source: source)
        let url = DownloadNaming.uniqueURL(for: DownloadNaming.sanitize(suggestedFilename), in: Self.folder)
        item.filename = url.lastPathComponent
        item.destination = url
        item.totalBytes = Int64(data.count)
        items.insert(item, at: 0)
        do {
            try data.write(to: url, options: .withoutOverwriting)
            item.fraction = 1
            item.state = .finished
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: url.path)
        } catch {
            item.state = .failed(error.localizedDescription)
        }
    }

    func cancel(_ item: Item) {
        item.download?.cancel { [weak item] data in
            Task { @MainActor in item?.resumeData = data }
        }
        item.state = .cancelled
    }

    func retry(_ item: Item, in webView: WKWebView?) {
        guard item.canRetry, let webView else { return }
        Task {
            let download: WKDownload
            if let data = item.resumeData {
                download = await webView.resumeDownload(fromResumeData: data)
            } else if let source = item.source {
                download = await webView.startDownload(using: URLRequest(url: source))
            } else {
                return
            }
            items.removeAll { $0 === item }
            track(download)
        }
    }

    func reveal(_ item: Item) {
        guard let destination = item.destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func open(_ item: Item) {
        guard let destination = item.destination, item.state == .finished else { return }
        NSWorkspace.shared.open(destination)
    }

    func clearFinished() {
        items.removeAll { $0.state != .running }
    }

    private func item(for download: WKDownload) -> Item? {
        items.first { $0.download === download }
    }
}

extension DownloadManager: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let name = DownloadNaming.sanitize(suggestedFilename)
        let url = DownloadNaming.uniqueURL(for: name, in: Self.folder)
        if let item = item(for: download) {
            item.filename = url.lastPathComponent
            item.destination = url
            item.totalBytes = response.expectedContentLength
        }
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = item(for: download) else { return }
        item.state = .finished
        item.fraction = 1
        item.progressObservation = nil
        if let destination = item.destination {
            // Bounces the Downloads stack in the Dock, as Safari does.
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: destination.path)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let item = item(for: download) else { return }
        item.resumeData = resumeData
        item.progressObservation = nil
        if item.state != .cancelled { item.state = .failed(error.localizedDescription) }
    }
}
