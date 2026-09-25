import AppKit
import SwiftUI

/// Fenêtre sans bordure ni boutons, façon Spotlight. Le bord haut reste fixe quand la hauteur change.
final class FloatingPanel: NSPanel {
    var anchorTop: CGFloat?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 120),
                   styleMask: [.borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if let top = anchorTop { frame.origin.y = top - frame.height }
        super.setFrame(frame, display: flag)
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel = FloatingPanel()
    let vm: ChatViewModel
    private var keyMonitor: Any?

    init(vm: ChatViewModel) {
        self.vm = vm
        super.init()
        let hosting = NSHostingController(rootView: ContentView(vm: vm))
        hosting.sizingOptions = [.preferredContentSize]
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear
        panel.contentViewController = hosting
        panel.delegate = self
        vm.onClose = { [weak self] in self?.hide() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    var isShown: Bool { panel.isVisible && NSApp.isActive }

    func toggle() { isShown ? hide() : show() }

    func show() {
        vm.prefillFromClipboardIfNeeded()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.anchorTop = visible.maxY - visible.height * 0.2
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: 0, width: size.width, height: size.height), display: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusInput()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        // Rend le focus à l'application précédente.
        NSApp.hide(nil)
    }

    private func focusInput() {
        guard let textView = Self.findInput(in: panel.contentView) else { return }
        panel.makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    private static func findInput(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView, tv.identifier == InputTextView.identifier { return tv }
        for sub in view.subviews { if let match = findInput(in: sub) { return match } }
        return nil
    }

    // MARK: - Raccourcis internes

    private static let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.keyCode == 53 { // esc
            if vm.isStreaming { vm.cancel() } else if vm.showingHistory { vm.toggleHistory() } else { hide() }
            return true
        }
        if vm.showingHistory {
            switch (event.keyCode, flags.contains(.command)) {
            case (126, false): vm.moveHistorySelection(-1); return true      // ↑
            case (125, false): vm.moveHistorySelection(1); return true       // ↓
            case (36, true), (76, true): vm.copyHistorySelection(); return true  // ⌘⏎
            case (51, true): vm.deleteHistorySelection(); return true        // ⌘⌫
            default: break
            }
        }
        // ⌥1…⌥9 : ajustements prédéfinis (keyCode pour marcher en AZERTY).
        if flags == .option, vm.hasConversation, !vm.result.isEmpty, let index = Self.digitKeyCodes.firstIndex(of: event.keyCode) {
            vm.adjust(index)
            return true
        }
        guard flags.contains(.command) else { return false }

        if event.keyCode == 36 || event.keyCode == 76 { // ⌘⏎
            vm.copyResult()
            return true
        }
        // ⌘1…⌘9 : utilise le keyCode pour fonctionner aussi en AZERTY.
        if let index = Self.digitKeyCodes.firstIndex(of: event.keyCode) {
            vm.selectAction(index)
            return true
        }
        switch chars {
        case ".":
            vm.cancel(); return true
        case "n":
            vm.reset(); focusInput(); return true
        case "y":
            vm.toggleHistory(); return true
        case "q":
            NSApp.terminate(nil); return true
        case "w":
            hide(); return true
        case "c":
            // Copie la sélection si elle existe, sinon le résultat.
            if let tv = panel.firstResponder as? NSTextView, tv.selectedRange().length > 0 { return false }
            vm.copyResult(); return true
        default:
            return false
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { panel.orderOut(nil) }
    }

    func windowDidMove(_ notification: Notification) {
        panel.anchorTop = panel.frame.maxY
    }

    func windowDidResize(_ notification: Notification) {
        panel.invalidateShadow()
    }
}
