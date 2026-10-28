#if DEBUG
import AppKit
import SwiftUI

/// Captures real native views for repeatable visual review, without screen-recording access.
@MainActor enum ReviewSnapshot {
    /// Writes `view` as `<name>.png` under `.impeccable/review/<folder>` in the repository.
    static func save(_ view: NSView, folder: String, name: String) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(".impeccable/review/\(folder)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
    }

    static func find<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View, !match.isHiddenOrHasHiddenAncestor { return match }
        for child in view.subviews { if let match = find(type, in: child) { return match } }
        return nil
    }

    static func appearanceName(_ view: NSView) -> String {
        let match = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
        return switch match {
        case .darkAqua: "dark"
        case .accessibilityHighContrastAqua: "light-contrast"
        case .accessibilityHighContrastDarkAqua: "dark-contrast"
        default: "light"
        }
    }
}

@MainActor enum DevToolsReview {
    static func saveSnapshot() {
        guard let content = NSApp.keyWindow?.contentView, let host = ReviewSnapshot.find(NSHostingView<DevPanel>.self, in: content) else { return }
        let model = host.rootView.model
        let name = "\(model.section.rawValue.lowercased())-\(ReviewSnapshot.appearanceName(host))-\(model.isDetached ? "detached" : "docked")-\(Int(host.bounds.width))"
        do { try ReviewSnapshot.save(host, folder: "devtools", name: name) }
        catch { model.status = "Could not save review snapshot: \(error.localizedDescription)" }
    }
}

@MainActor enum SettingsReview {
    /// The whole browser window around the Settings tab, so the page reads in its chrome.
    static func saveSnapshot(suffix: String = "") {
        let window = NSApp.orderedWindows.first { $0.windowController is BrowserWindowController }
        guard let content = window?.contentView, let host = ReviewSnapshot.find(SettingsHostingView.self, in: content) else { return }
        let name = "settings-\(ReviewSnapshot.appearanceName(host))-\(Int(content.bounds.width))" + (suffix.isEmpty ? "" : "-\(suffix)")
        try? ReviewSnapshot.save(content, folder: "settings", name: name)
    }

    /// Types into the visible Settings page's search field.
    static func search(_ query: String) { model?.query = query }

    /// Opens a new, empty keyword in the editor, showing its validation.
    static func addKeyword() { model?.addKeyword() }

    private static var model: SettingsModel? {
        let window = NSApp.orderedWindows.first { $0.windowController is BrowserWindowController }
        guard let content = window?.contentView else { return nil }
        return ReviewSnapshot.find(SettingsHostingView.self, in: content)?.rootView.model
    }
}
#endif
