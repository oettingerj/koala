import AppKit
import BrowserKit
import Eucalyptus

Perf.app = Perf.App(subsystem: "com.joshoettinger.koala", name: "Koala")
MonoFont.register()
NSScroller.makeAllSmall()

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
