import AppKit
import BrowserKit
import Eucalyptus
import SwiftUI

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
    @Environment(\.settingsFilter) private var filter
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
                ShortcutKeys(shortcut: command.shortcut, isRecording: isRecording, filter: filter) {
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
