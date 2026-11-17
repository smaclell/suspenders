import AppKit
import SwiftUI

/// A warm, click-through tint across every screen.
final class TintOverlay {
    private var windows: [NSWindow] = []
    private(set) var opacity: Double = 0

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self, self.opacity > 0 else { return }
            let o = self.opacity
            self.hide()
            self.show(opacity: o)
        }
    }

    func show(opacity: Double) {
        if windows.isEmpty {
            windows = NSScreen.screens.map { screen in
                let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                w.setFrame(screen.frame, display: false)
                w.isOpaque = false
                w.hasShadow = false
                w.ignoresMouseEvents = true
                w.level = .screenSaver
                w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                w.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.15, alpha: 1)
                w.alphaValue = 0
                w.orderFrontRegardless()
                return w
            }
        }
        self.opacity = opacity
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 20 // deepen slowly so it's never jarring
            windows.forEach { $0.animator().alphaValue = opacity }
        }
    }

    func hide() {
        opacity = 0
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }
}

// MARK: - Wind-down card

struct WindDownView: View {
    let time: String
    let question: String
    let activeTonight: String
    let deferrals: Int
    let onSignOff: (String) -> Void
    let onDefer: (String) -> Void
    @State private var answer = ""
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.02, blue: 0.06), Color(red: 0.08, green: 0.07, blue: 0.2),
                                    Color(red: 0.25, green: 0.13, blue: 0.2)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.9, green: 0.5, blue: 0.3).opacity(0.35), .clear],
                           center: .bottom, startRadius: 10, endRadius: 700)

            VStack(spacing: 18) {
                Circle()
                    .fill(Color(red: 0.99, green: 0.95, blue: 0.84))
                    .frame(width: 66, height: 66)
                    .mask {
                        ZStack {
                            Circle()
                            Circle().offset(x: 18, y: -12).blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                    .shadow(color: Color(red: 0.99, green: 0.95, blue: 0.84).opacity(0.6), radius: 24)
                    .padding(.bottom, 12)

                Text(time.uppercased())
                    .font(.system(size: 14, weight: .semibold)).tracking(2.4)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Time to sign off.")
                    .font(.system(size: 56, weight: .semibold)).tracking(-1.2)
                    .foregroundStyle(.white)
                Text("You've been on the laptop for \(activeTonight) tonight.")
                    .font(.system(size: 19)).foregroundStyle(.white.opacity(0.7))

                VStack(alignment: .leading, spacing: 10) {
                    Text(question)
                        .font(.system(size: 20, weight: .medium, design: .serif)).italic()
                        .foregroundStyle(.white.opacity(0.9))
                    TextField("", text: $answer, prompt: Text("A sentence is plenty…").foregroundColor(.white.opacity(0.35)), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .lineLimit(2...4)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15)))
                }
                .frame(width: 520)
                .padding(.top, 26)

                HStack(spacing: 14) {
                    Button { onSignOff(answer) } label: {
                        Text("Sign off & sleep the display")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 24).padding(.vertical, 13)
                            .background(Capsule().fill(Color(red: 1, green: 0.98, blue: 0.95)))
                            .foregroundStyle(Color(red: 0.08, green: 0.07, blue: 0.16))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)

                    Button { onDefer(answer) } label: {
                        Text(deferrals == 0 ? "15 more minutes" : "15 more minutes (again)")
                            .font(.system(size: 16, weight: .medium))
                            .padding(.horizontal, 22).padding(.vertical, 13)
                            .background(Capsule().strokeBorder(.white.opacity(0.25)))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 22)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { appeared = true } }
    }
}

final class WindDownWindow {
    private var window: NSWindow?

    var isShowing: Bool { window != nil }

    func show(view: WindDownView) {
        close()
        guard let screen = NSScreen.main else { return }
        let w = KeyableWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        w.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.contentView = NSHostingView(rootView: view)
        w.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.8; w.animator().alphaValue = 1 }
        window = w
    }

    func close() {
        guard let w = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; w.animator().alphaValue = 0 }, completionHandler: { w.orderOut(nil) })
    }
}

/// Borderless windows can't become key by default, which would block typing.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
