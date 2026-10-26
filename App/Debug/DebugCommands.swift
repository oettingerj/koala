#if DEBUG
import AppKit

/// Debug-only: lets review scripts drive window states without UI scripting permissions.
/// Post `com.joshoettinger.nano.debug` with an object like "appearance dark",
/// "action newTab:", "open https://example.com", or "resize 1280x820".
@MainActor
enum DebugCommands {
    static func install() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.joshoettinger.nano.debug"), object: nil, queue: .main
        ) { note in
            let command = (note.object as? String) ?? ""
            MainActor.assumeIsolated { perform(command) }
        }
    }

    private static func perform(_ command: String) {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = parts.first else { return }
        let argument = parts.count > 1 ? parts[1] : ""
        let window = NSApp.orderedWindows.first { $0.windowController is BrowserWindowController }
        switch verb {
        case "appearance":
            NSApp.appearance = argument == "dark" ? NSAppearance(named: .darkAqua)
                : argument == "light" ? NSAppearance(named: .aqua) : nil
        case "action":
            NSApp.sendAction(NSSelectorFromString(argument), to: nil, from: nil)
        case "open":
            if let url = URL(string: argument) { NSApp.delegate?.application?(NSApp, open: [url]) }
        case "resize":
            let size = argument.split(separator: "x").compactMap { Double($0) }
            if size.count == 2 { window?.setContentSize(NSSize(width: size[0], height: size[1])) }
        default:
            break
        }
    }
}
#endif
