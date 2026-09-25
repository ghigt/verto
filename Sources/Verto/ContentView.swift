import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var vm: ChatViewModel
    @State private var inputHeight: CGFloat = 24
    @State private var resultHeight: CGFloat = 0

    private let width: CGFloat = 640
    private let maxResultHeight: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            input
            if !vm.result.isEmpty || vm.isStreaming {
                Divider().opacity(0.5)
                resultView
            }
            if let error = vm.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: width)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(Array(vm.config.actions.enumerated()), id: \.offset) { index, action in
                Button { vm.selectAction(index) } label: {
                    HStack(spacing: 4) {
                        Text(action.name)
                        if index < 9 {
                            Text("⌘\(index + 1)").foregroundStyle(.secondary).font(.system(size: 10))
                        }
                    }
                    .font(.system(size: 12, weight: index == vm.selectedAction ? .semibold : .regular))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(index == vm.selectedAction ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            if !vm.modelName.isEmpty {
                Text(vm.modelName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var input: some View {
        ZStack(alignment: .topLeading) {
            if vm.input.isEmpty {
                Text(vm.hasConversation ? "Ajustement… (ex : plus formel, plus court)" : "Colle ou tape ton texte…")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
            InputTextView(text: $vm.input, height: $inputHeight, onSubmit: vm.submit)
                .frame(height: inputHeight)
        }
    }

    private var resultView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(vm.result.isEmpty ? " " : vm.result)
                        .font(.system(size: 15))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                })
            }
            .scrollIndicators(.automatic)
            .frame(height: min(max(resultHeight, 20), maxResultHeight))
            .onPreferenceChange(HeightKey.self) { resultHeight = $0 }
            .onChange(of: vm.result) {
                if vm.isStreaming { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .overlay(alignment: .topTrailing) {
                if !vm.isStreaming && !vm.result.isEmpty {
                    Button(action: vm.copyResult) {
                        Image(systemName: vm.copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(vm.copied ? Color.green : Color.secondary)
                            .padding(6)
                            .background(Circle().fill(.background.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .help("Copier (⌘⏎)")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if vm.isStreaming {
                ProgressView().controlSize(.mini)
                hint("⌘.", "stop")
            } else if vm.copied {
                Label("Copié", systemImage: "checkmark").foregroundStyle(.green)
            } else if !vm.result.isEmpty {
                hint("⌘⏎", "copier")
                hint("⏎", "ajuster")
                hint("⌘N", "nouveau")
            } else {
                hint("⏎", "envoyer")
                hint("⇧⏎", "nouvelle ligne")
            }
            Spacer()
            hint("esc", "fermer")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key).fontWeight(.medium)
            Text(label).foregroundStyle(.tertiary)
        }
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - AppKit bridges

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// NSTextView multi-ligne : ⏎ envoie, ⇧⏎ / ⌥⏎ insère un retour à la ligne, hauteur auto.
struct InputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onSubmit: () -> Void

    static let identifier = NSUserInterfaceItemIdentifier("VertoInput")
    private static let minHeight: CGFloat = 24
    private static let maxHeight: CGFloat = 200

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = scroll.documentView as! NSTextView
        textView.identifier = InputTextView.identifier
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.delegate = context.coordinator
        textView.string = text

        // Recalcule la hauteur quand la largeur change (retour à la ligne).
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.frameChanged),
                                               name: NSView.frameDidChangeNotification, object: textView)
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            context.coordinator.recalcHeight()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InputTextView
        weak var textView: NSTextView?

        init(_ parent: InputTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            recalcHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            }
            return false
        }

        @objc func frameChanged() { recalcHeight() }

        func recalcHeight() {
            guard let textView, let lm = textView.layoutManager, let tc = textView.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = ceil(lm.usedRect(for: tc).height + textView.textContainerInset.height * 2)
            let clamped = min(max(h, InputTextView.minHeight), InputTextView.maxHeight)
            DispatchQueue.main.async { [parent] in
                if parent.height != clamped { parent.height = clamped }
            }
        }
    }
}
