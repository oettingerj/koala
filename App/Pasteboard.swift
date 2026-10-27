import AppKit

enum Pasteboard {
    /// Copies a page link as a URL (with its title for rich paste targets) and plain text.
    static func copy(url: URL, title: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.absoluteString, forType: .string)
        if !title.isEmpty {
            pasteboard.setString(title, forType: NSPasteboard.PasteboardType("public.url-name"))
        }
    }
}
