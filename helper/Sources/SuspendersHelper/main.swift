import AppKit
import SwiftUI

let app = NSApplication.shared

// `SuspendersHelper --snapshot <file.png>` renders the wind-down card (for docs/screenshots).
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let view = WindDownView(time: "10:31 PM", question: SignOffController.questions[1], activeTonight: "2h 14m",
                            deferrals: 0, onSignOff: { _ in }, onDefer: { _ in })
    let host = NSHostingView(rootView: view.frame(width: 1440, height: 900))
    host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5)) // let the appear animation finish
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
