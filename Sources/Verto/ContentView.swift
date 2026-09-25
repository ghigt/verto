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
            if !vm.hasConversation || vm.showingHistory {
                input
            }
            if vm.showingHistory {
                Divider().opacity(0.5)
                historyView
            } else if !vm.result.isEmpty || vm.isStreaming {
                Divider().opacity(0.5)
                if let original = vm.originalText {
                    Text(original)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .help(original)
                }
                if vm.versions.count > 1 {
                    versionTabs
                }
                resultView
                if vm.adjusting {
                    if !vm.config.adjustments.isEmpty {
                        adjustments
                    }
                    input
                }
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
                chip(action.name, shortcut: index < 9 ? "⌘\(index + 1)" : nil, selected: index == vm.selectedAction) {
                    vm.selectAction(index)
                }
            }
            Spacer(minLength: 8)
            Button(action: vm.toggleHistory) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(vm.showingHistory ? Color.accentColor : Color.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Historique (⌘Y)")
            if !vm.modelName.isEmpty {
                Text(vm.modelName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var adjustments: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            ForEach(Array(vm.config.adjustments.enumerated()), id: \.offset) { index, adjustment in
                chip(adjustment.name, shortcut: nil, selected: vm.selectedPreset == index) {
                    vm.adjust(index)
                }
            }
            Spacer(minLength: 0)
        }
        .disabled(vm.isStreaming)
        .opacity(vm.isStreaming ? 0.4 : 1)
    }

    /// Versions déjà générées : un clic (ou ←/→) les affiche sans regénérer.
    private var versionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(vm.versions.enumerated()), id: \.element.id) { index, version in
                    Button { vm.selectVersion(index) } label: {
                        Text(version.label)
                            .font(.system(size: 11, weight: index == vm.selectedVersion ? .semibold : .regular))
                            .foregroundStyle(index == vm.selectedVersion ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(index == vm.selectedVersion ? Color.primary.opacity(0.12) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isStreaming)
                }
            }
        }
    }

    private func chip(_ title: String, shortcut: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let shortcut {
                    Text(shortcut).foregroundStyle(.secondary).font(.system(size: 10))
                }
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var input: some View {
        ZStack(alignment: .topLeading) {
            if vm.input.isEmpty {
                Text(placeholder)
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
            InputTextView(text: $vm.input, height: $inputHeight, onSubmit: vm.submit)
                .frame(height: inputHeight)
        }
        .onChange(of: vm.input) {
            if vm.showingHistory { vm.historyQueryChanged() }
        }
    }

    private var placeholder: String {
        if vm.showingHistory { return "Rechercher dans l'historique…" }
        return vm.hasConversation ? "Ajustement… (ex : plus formel, plus court)" : "Colle ou tape ton texte…"
    }

    private var historyView: some View {
        let entries = vm.historyResults
        return Group {
            if entries.isEmpty {
                Text(vm.history.entries.isEmpty ? "Historique vide" : "Aucun résultat")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                historyRow(entry, selected: index == vm.historySelection)
                                    .id(entry.id)
                                    .onTapGesture(count: 2) { vm.openHistorySelection() }
                                    .onTapGesture { vm.moveHistorySelection(index - vm.historySelection) }
                            }
                        }
                    }
                    .frame(height: min(CGFloat(entries.count) * 62, maxResultHeight))
                    .onChange(of: vm.historySelection) {
                        let results = vm.historyResults
                        if results.indices.contains(vm.historySelection) {
                            proxy.scrollTo(results[vm.historySelection].id)
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.result)
                .font(.system(size: 13))
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(entry.original)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text("\(entry.action) · \(Self.relativeDate.localizedString(for: entry.date, relativeTo: Date()))")
                    .fixedSize()
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.2) : Color.clear))
        .contentShape(Rectangle())
    }

    private static let relativeDate: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f
    }()

    private var resultView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(vm.result.isEmpty ? " " : vm.result)
                        .font(.system(size: 15))
                        .textSelection(.enabled)
                        .padding(.trailing, 34) // place pour le bouton copier
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
            if vm.showingHistory {
                hint("↑↓", "naviguer")
                hint("⏎", "rouvrir")
                hint("⌘⏎", "copier")
                hint("⌘⌫", "supprimer")
            } else if vm.isStreaming {
                ProgressView().controlSize(.mini)
                hint("⌘.", "stop")
            } else if vm.copied {
                Label("Copié", systemImage: "checkmark").foregroundStyle(.green)
            } else if vm.adjusting {
                hint("⏎", "ajuster")
                hint("⌘⏎", "copier")
                if vm.versions.count > 1 {
                    hint("←→", "versions")
                }
                if !vm.config.adjustments.isEmpty {
                    hint("⌥1…\(min(vm.config.adjustments.count, 9))", "préréglages")
                }
            } else if !vm.result.isEmpty {
                hint("⏎", "copier")
                if vm.versions.count > 1 {
                    hint("←→", "versions")
                }
                Button(action: vm.showAdjust) { hint("tab", "ajuster") }
                    .buttonStyle(.plain)
                    .help("Ajuster le ton, la longueur…")
                hint("⌘N", "nouveau")
            } else {
                hint("⏎", "envoyer")
            }
            Spacer()
            if !vm.showingHistory && !vm.isStreaming {
                hint("⌘Y", "historique")
            }
            hint("esc", vm.showingHistory ? "retour" : vm.adjusting ? "masquer" : "fermer")
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
