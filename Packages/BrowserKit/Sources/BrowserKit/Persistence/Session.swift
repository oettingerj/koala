import Foundation

public struct TabSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var url: URL?
    public var title: String
    public var isPinned: Bool
    public var openerID: UUID?
    /// WebKit's opaque back/forward state; restores history without reloading every entry.
    public var interactionState: Data?

    public init(id: UUID, url: URL?, title: String, isPinned: Bool, openerID: UUID?, interactionState: Data?) {
        self.id = id
        self.url = url
        self.title = title
        self.isPinned = isPinned
        self.openerID = openerID
        self.interactionState = interactionState
    }
}

public struct WindowSnapshot: Codable, Equatable, Sendable {
    public var frame: CGRect?
    public var tabs: [TabSnapshot]
    public var selectedIndex: Int?

    public init(frame: CGRect?, tabs: [TabSnapshot], selectedIndex: Int?) {
        self.frame = frame
        self.tabs = tabs
        self.selectedIndex = selectedIndex
    }
}

/// Something the user closed and can bring back with ⇧⌘T.
public enum ClosedItem: Codable, Equatable, Sendable {
    case tab(TabSnapshot, index: Int)
    case window(WindowSnapshot)

    public var title: String {
        switch self {
        case .tab(let tab, _): tab.title.isEmpty ? (tab.url?.absoluteString ?? "Tab") : tab.title
        case .window(let window): "Window with \(window.tabs.count) tab\(window.tabs.count == 1 ? "" : "s")"
        }
    }
}

public struct Session: Codable, Equatable, Sendable {
    public var windows: [WindowSnapshot]
    public var recentlyClosed: [ClosedItem]

    public init(windows: [WindowSnapshot] = [], recentlyClosed: [ClosedItem] = []) {
        self.windows = windows
        self.recentlyClosed = recentlyClosed
    }
}

/// Persists the session as one JSON file, replaced atomically so a crash mid-write
/// never leaves a torn file.
public final class SessionStore: Sendable {
    public let fileURL: URL
    private let queue = DispatchQueue(label: "nano.session", qos: .utility)

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore() throws -> SessionStore {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Nano", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SessionStore(fileURL: directory.appendingPathComponent("session.json"))
    }

    public func load() -> Session? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    /// Writes on a background queue; `sync` blocks until written (used at quit).
    public func save(_ session: Session, sync: Bool = false) {
        let work = { [fileURL] in
            guard let data = try? JSONEncoder().encode(session) else { return }
            try? data.write(to: fileURL, options: [.atomic])
        }
        if sync { queue.sync(execute: work) } else { queue.async(execute: work) }
    }
}
