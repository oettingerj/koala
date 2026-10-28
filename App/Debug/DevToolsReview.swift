#if DEBUG
import AppKit
import SwiftUI

/// Captures the real native tools view for repeatable visual review, without screen-recording access.
@MainActor enum DevToolsReview {
    static func saveSnapshot() {
        func find(_ view: NSView) -> NSHostingView<DevPanel>? {
            if let host = view as? NSHostingView<DevPanel>, !host.isHiddenOrHasHiddenAncestor { return host }
            for child in view.subviews { if let host = find(child) { return host } }
            return nil
        }
        guard let content = NSApp.keyWindow?.contentView, let host = find(content),
              let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let model = host.rootView.model
        let dark = host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let name = "\(model.section.rawValue.lowercased())-\(dark ? "dark" : "light")-\(model.isDetached ? "detached" : "docked")-\(Int(host.bounds.width))"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(".impeccable/review/devtools")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        } catch { model.status = "Could not save review snapshot: \(error.localizedDescription)" }
    }
}
#endif
