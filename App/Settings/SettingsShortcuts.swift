import AppKit
import BrowserKit
import SwiftUI

/// Records a new shortcut for one command: the next key press with ⌘, ⌃, or ⌥, or an F-key alone, becomes its shortcut.
/// While recording, key presses go nowhere else, so ⌘W names a shortcut instead of closing the tab.
@MainActor
@Observable
final class ShortcutRecording {
    private(set) var commandID: String?
    /// Why the last key press was not taken, shown under the command's title.
    private(set) var issue: String?
    /// Called with the recorded shortcut, or `.none` for Delete.
    @ObservationIgnored private var onRecord: ((MenuShortcut) -> Void)?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var resignObserver: NSObjectProtocol?

    func start(_ id: String, onRecord: @escaping (MenuShortcut) -> Void) {
        stop()
        commandID = id
        self.onRecord = onRecord
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return nil
        } as Any)
        // A click anywhere ends recording; a click on the recorder itself starts it again.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.stop() }
            return event
        } as Any)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        commandID = nil
        issue = nil
        onRecord = nil
    }

    private func handle(_ event: NSEvent) {
        guard let id = commandID else { return }
        // The key without ⇧ or ⌥ applied, so ⇧⌘] is "]" with ⇧, the menu's convention.
        var key = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
        if key == "\u{7f}" { key = "\u{8}" } // menus name the Delete key by backspace
        let shortcut = MenuShortcut(key: key, modifiers: event.modifierFlags)
        switch (event.keyCode, shortcut.modifierFlags.isEmpty) {
        case (53, true): return stop() // Esc
        case (51, true), (117, true): // Delete, Forward Delete
            onRecord?(.none)
            return stop()
        default: break
        }
        if event.modifierFlags.contains(.function), !Self.isFunctionRange(key) {
            issue = "fn can't be part of a shortcut."
        } else if !shortcut.isAssignable {
            issue = "Add ⌘, ⌃, or ⌥ to the keys."
        } else if let owner = MenuShortcuts.owner(of: shortcut, excluding: id) {
            issue = "\(shortcut.display) is already the shortcut for \(owner)."
        } else {
            onRecord?(shortcut)
            stop()
        }
    }

    /// F-keys, arrows, and navigation keys, which AppKit always flags with fn whether or not fn is held.
    private static func isFunctionRange(_ key: String) -> Bool {
        guard let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 else { return false }
        return (0xF700...0xF8FF).contains(scalar.value)
    }
}

struct ShortcutSettings: View {
    @Bindable var model: SettingsModel
    @Environment(\.settingsFilter) private var filter

    static func entry(for command: MenuShortcuts.Command) -> SettingEntry {
        SettingEntry(id: "shortcut-\(command.id)", section: .shortcuts, title: command.title, detail: command.menu,
                     terms: [command.shortcut.display, command.defaultShortcut.display, "keyboard shortcut hotkey key binding"])
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.shortcuts) { command in
                ShortcutRow(command: command, recording: model.shortcutRecording) { shortcut in
                    model.setShortcut(shortcut, for: command.id)
                }
            }
            if !filter.isActive {
                HStack {
                    Spacer()
                    Button("Restore Defaults", action: model.resetShortcuts)
                        .disabled(!model.shortcuts.contains(where: \.isCustomized))
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { SettingsRule() }
            }
        }
        .onDisappear { model.shortcutRecording.stop() }
    }
}

private struct ShortcutRow: View {
    let command: MenuShortcuts.Command
    let recording: ShortcutRecording
    /// nil restores the built-in shortcut.
    let onChange: (MenuShortcut?) -> Void

    private var isRecording: Bool { recording.commandID == command.id }

    var body: some View {
        SettingRow(ShortcutSettings.entry(for: command)) {
            if isRecording, let issue = recording.issue {
                Text(issue).font(.system(size: 11)).foregroundStyle(settingsFail)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SettingDetail(text: command.menu)
            }
        } control: {
            HStack(spacing: 6) {
                if command.isCustomized {
                    Button { onChange(nil) } label: {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(settingsTertiary).frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(resetLabel)
                    .accessibilityLabel(resetLabel)
                }
                ShortcutKeys(shortcut: command.shortcut, isRecording: isRecording) {
                    if isRecording { recording.stop() } else { recording.start(command.id) { onChange($0) } }
                }
                .accessibilityLabel("Shortcut for \(command.title)")
                .accessibilityValue(isRecording ? "Recording. Escape cancels, Delete removes the shortcut."
                                                : command.shortcut.isNone ? "None" : command.shortcut.display)
                .accessibilityHint(isRecording ? "" : "Records a new shortcut")
            }
        }
    }

    private var resetLabel: String {
        command.defaultShortcut.isNone ? "Remove shortcut, as by default" : "Reset to \(command.defaultShortcut.display)"
    }
}

/// The shortcut in a field-well chip, or the prompt while recording. Teal outlines it while it listens.
private struct ShortcutKeys: View {
    let shortcut: MenuShortcut
    let isRecording: Bool
    let action: () -> Void
    @Environment(\.settingsFilter) private var filter

    var body: some View {
        Button(action: action) {
            Group {
                if isRecording {
                    Text("Press keys").foregroundStyle(settingsSecondary)
                } else if shortcut.isNone {
                    Text("None").foregroundStyle(settingsTertiary)
                } else {
                    Text(filter.highlight(shortcut.display, size: 12)).foregroundStyle(settingsPrimary)
                }
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .padding(.horizontal, 8).frame(minWidth: 72, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: Theme.fieldFill)))
            .overlay {
                if isRecording {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: Theme.accent), lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}
