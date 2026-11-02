import AppKit
import BrowserKit

MonoFont.register()
NSScroller.makeAllSmall()

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
