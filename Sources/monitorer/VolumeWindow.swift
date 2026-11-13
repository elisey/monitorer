import AppKit
import MonitorerCore

/// Pushes slider values to the monitor from a background queue.
///
/// Each DDC write takes a few hundred milliseconds, far longer than the gap between slider
/// events while dragging. Only the most recent value is kept while a write is in flight,
/// so the monitor follows the slider instead of replaying every intermediate position.
final class VolumeWriter: @unchecked Sendable {
    private let controller: VolumeController
    private let onResult: @MainActor @Sendable (Result<Volume, DDCError>) -> Void
    private let queue = DispatchQueue(label: "monitorer.volume")
    private let lock = NSLock()
    private var pending: Int?
    private var draining = false

    init(
        controller: VolumeController,
        onResult: @escaping @MainActor @Sendable (Result<Volume, DDCError>) -> Void
    ) {
        self.controller = controller
        self.onResult = onResult
    }

    func submit(_ level: Int) {
        lock.lock()
        pending = level
        let startDrain = !draining
        draining = true
        lock.unlock()
        if startDrain { queue.async { self.drain() } }
    }

    /// Blocks until every submitted value has reached the monitor.
    func waitUntilIdle() {
        queue.sync {}
    }

    private func drain() {
        while true {
            lock.lock()
            guard let level = pending else {
                draining = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()

            let result: Result<Volume, DDCError>
            do {
                result = .success(try controller.set(level))
            } catch {
                result = .failure(error)
            }
            let onResult = onResult
            DispatchQueue.main.async { MainActor.assumeIsolated { onResult(result) } }
        }
    }
}

/// A floating panel with a single volume slider. It closes on Escape, when it stops being
/// the key window (a click anywhere else) or on any click outside it, and ends the process
/// when it closes.
@MainActor
final class VolumePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
final class VolumeApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let initial: Volume
    private var writer: VolumeWriter!
    private var panel: VolumePanel!
    private var valueLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var clickMonitor: Any?
    private var confirmed: Volume
    private var closing = false

    /// Shows the window and runs the event loop; exits the process when the window closes.
    static func run(controller: VolumeController, initial: Volume) -> Never {
        let app = NSApplication.shared
        let delegate = VolumeApp(controller: controller, initial: initial)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        exit(0)
    }

    private init(controller: VolumeController, initial: Volume) {
        self.initial = initial
        self.confirmed = initial
        super.init()
        writer = VolumeWriter(controller: controller) { [weak self] result in
            self?.didWrite(result)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = makePanel()
        panel.delegate = self
        panel.center()
        if let screen = screenUnderMouse() {
            let frame = panel.frame
            panel.setFrameOrigin(
                NSPoint(
                    x: screen.visibleFrame.midX - frame.width / 2,
                    y: screen.visibleFrame.midY - frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.close() }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Terminating closes the window once more; report and exit only on the first pass.
        guard !closing else { return }
        closing = true
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        writer.waitUntilIdle()
        print("Volume: \(confirmed.level)")
        NSApp.terminate(nil)
    }

    private func didWrite(_ result: Result<Volume, DDCError>) {
        switch result {
        case .success(let volume):
            confirmed = volume
            statusLabel.stringValue = ""
        case .failure(let error):
            statusLabel.stringValue = "error: \(error)"
        }
    }

    @objc private func sliderMoved(_ slider: NSSlider) {
        let level = slider.integerValue
        valueLabel.stringValue = "\(level)"
        writer.submit(level)
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func makePanel() -> VolumePanel {
        let panel = VolumePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        panel.contentView = background

        let title = NSTextField(labelWithString: "Monitor volume")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        valueLabel = NSTextField(labelWithString: "\(initial.level)")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.alignment = .right

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed
        statusLabel.lineBreakMode = .byTruncatingTail

        let slider = NSSlider(
            value: Double(initial.level), minValue: 0, maxValue: Double(initial.maximum),
            target: self, action: #selector(sliderMoved))
        slider.isContinuous = true

        let header = NSStackView(views: [title, valueLabel])
        header.orientation = .horizontal
        header.distribution = .fill
        let stack = NSStackView(views: [header, slider, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 14),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            slider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        panel.initialFirstResponder = slider
        return panel
    }
}
