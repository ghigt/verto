import AppKit
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var config: Config
    @Published var input = ""
    @Published private(set) var selectedAction: Int
    @Published private(set) var result = ""
    @Published private(set) var isStreaming = false
    @Published var error: String?
    @Published private(set) var copied = false
    @Published private(set) var modelName = ""

    /// Texte d'origine de la conversation en cours (nil = pas de conversation).
    @Published private(set) var originalText: String?
    /// Versions générées pour ce texte (la première = résultat par défaut). On bascule entre elles sans regénérer.
    @Published private(set) var versions: [Version] = []
    @Published private(set) var selectedVersion = 0
    private var selectionBeforeRun = 0
    private var task: Task<Void, Never>?
    private var conversationID: UUID?

    let history: HistoryStore
    @Published private(set) var showingHistory = false
    /// Zone d'ajustement (préréglages + consigne libre), affichée seulement à la demande.
    @Published private(set) var adjusting = false
    /// Demande au panneau de donner le focus au champ de saisie.
    var onFocusInput: (() -> Void)?
    /// Ouvre le menu de l'app (config, icône de barre de menus, quitter).
    var onShowMenu: (() -> Void)?
    @Published private(set) var historySelection = 0
    /// Saisie en cours mise de côté pendant que le champ sert de recherche.
    private var stashedInput = ""

    /// Dernier ajustement tapé à la main, remis dans le champ en cas d'échec.
    private var typedAdjustment: String?

    /// Appelé pour fermer le panneau (après une copie).
    var onClose: (() -> Void)?

    private static let actionKey = "selectedAction"
    /// Ajouté à chaque prompt d'action pour éviter les préambules des petits modèles.
    /// En anglais pour ne pas influencer la langue de sortie.
    private static let outputRule = """


    Output only the final text, ready to paste: no preamble (such as "Here is…"), no alternatives, \
    no explanations, no notes, no quotes or <text> tags around it.
    When the user later asks for an adjustment, apply it to your last version and again output only the complete final text.
    """

    init(config: Config) {
        self.config = config
        self.selectedAction = min(UserDefaults.standard.integer(forKey: Self.actionKey), config.actions.count - 1)
        self.modelName = config.model
        self.history = HistoryStore(limit: config.historyLimit)
    }

    var action: Action { config.actions[selectedAction] }
    var hasConversation: Bool { originalText != nil }

    func apply(config: Config) {
        cancel()
        self.config = config
        modelName = config.model
        selectedAction = min(selectedAction, config.actions.count - 1)
        history.limit = config.historyLimit
    }

    // MARK: - Actions

    func submit() {
        if showingHistory { openHistorySelection(); return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        input = ""
        if hasConversation {
            typedAdjustment = text
            sendAdjustment(text)
        } else {
            start(with: text)
        }
    }

    func selectAction(_ index: Int) {
        guard config.actions.indices.contains(index) else { return }
        selectedAction = index
        UserDefaults.standard.set(index, forKey: Self.actionKey)
        // Changer d'action sur une conversation existante relance sur le texte d'origine.
        if let text = originalText {
            cancel()
            start(with: text)
        }
    }

    /// Préréglage (ton, longueur…) appliqué au résultat par défaut.
    /// S'il a déjà été généré, on affiche simplement cette version.
    func adjust(_ index: Int) {
        guard config.adjustments.indices.contains(index), let base = versions.first, !isStreaming else { return }
        if let existing = versions.firstIndex(where: { $0.preset == index }) {
            selectVersion(existing)
            return
        }
        typedAdjustment = nil
        let preset = config.adjustments[index]
        run(label: preset.name, preset: index, request: base.messages + [adjustmentMessage(preset.prompt)])
    }

    /// Consigne libre, appliquée à la version affichée.
    private func sendAdjustment(_ request: String) {
        guard versions.indices.contains(selectedVersion) else { return }
        let label = request.count > 24 ? String(request.prefix(23)) + "…" : request
        run(label: "« \(label) »", preset: nil,
            request: versions[selectedVersion].messages + [adjustmentMessage(request)])
    }

    private func adjustmentMessage(_ request: String) -> ChatMessage {
        ChatMessage(role: "user", content: action.prompt.isEmpty ? request : Self.adjustment(request))
    }

    /// Préréglage correspondant à la version affichée (pour le mettre en évidence).
    var selectedPreset: Int? {
        versions.indices.contains(selectedVersion) ? versions[selectedVersion].preset : nil
    }

    func selectVersion(_ index: Int) {
        guard versions.indices.contains(index), !isStreaming else { return }
        selectedVersion = index
        result = versions[index].text
    }

    func moveVersion(_ delta: Int) {
        selectVersion(min(max(selectedVersion + delta, 0), versions.count - 1))
    }

    func showAdjust() {
        guard hasConversation, !showingHistory else { return }
        adjusting = true
        focusInputSoon()
    }

    /// Le champ peut changer de place : on attend que SwiftUI l'ait (re)créé.
    private func focusInputSoon() {
        DispatchQueue.main.async { [weak self] in self?.onFocusInput?() }
    }

    func hideAdjust() {
        adjusting = false
        input = ""
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func reset() {
        cancel()
        showingHistory = false
        adjusting = false
        stashedInput = ""
        versions = []
        selectedVersion = 0
        originalText = nil
        conversationID = nil
        result = ""
        error = nil
        input = ""
        isStreaming = false
    }

    func copyResult() {
        guard !result.isEmpty, !isStreaming else { return }
        saveToHistory() // mémorise la version choisie
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(result.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            self.copied = false
            self.reset()
            self.onClose?()
        }
    }

    func prefillFromClipboardIfNeeded() {
        guard config.prefillFromClipboard, !hasConversation, input.isEmpty,
              let text = NSPasteboard.general.string(forType: .string) else { return }
        input = text
    }

    // MARK: - LLM

    /// Encadre la demande d'ajustement pour que le modèle ne la traite pas comme un nouveau texte
    /// (ex : « plus formel » ne doit pas faire changer la langue d'une traduction).
    private static func adjustment(_ request: String) -> String {
        """
        Adjust your last version according to this instruction: \(request)
        Keep the same task, the same language and the same meaning as your last version: \
        do not add any new information, fact or idea that was not in the original text. \
        Output only the complete final text.
        """
    }

    private func start(with text: String) {
        originalText = text
        conversationID = UUID()
        versions = []
        selectedVersion = 0
        var request: [ChatMessage] = []
        if !action.prompt.isEmpty {
            request.append(ChatMessage(role: "system", content: action.prompt + Self.outputRule))
        }
        request.append(ChatMessage(role: "user", content: action.prompt.isEmpty ? text : "<text>\n\(text)\n</text>"))
        run(label: "Défaut", preset: nil, request: request)
    }

    /// Génère une nouvelle version et l'affiche pendant le streaming.
    private func run(label: String, preset: Int?, request: [ChatMessage]) {
        error = nil
        isStreaming = true
        selectionBeforeRun = selectedVersion
        let version = Version(id: UUID(), label: label, preset: preset, messages: request, text: "")
        versions.append(version)
        selectedVersion = versions.count - 1
        result = ""
        let config = self.config
        task = Task { [weak self] in
            var acc = ""
            do {
                if config.model.isEmpty, let model = try? await LLMClient.resolveModel(config) {
                    self?.modelName = model
                }
                for try await chunk in LLMClient.stream(config: config, messages: request) {
                    acc += chunk
                    self?.result = Self.clean(acc, streaming: true)
                }
                self?.finish(version.id, with: acc)
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                    self?.finish(version.id, with: acc)
                } else {
                    self?.fail(version.id, error)
                }
            }
        }
    }

    /// Retire les balises <text> que les petits modèles recopient parfois autour de leur réponse.
    private static func clean(_ raw: String, streaming: Bool = false) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let open = "<text>", close = "</text>"
        if streaming, open.hasPrefix(text) { return "" }
        if text.hasPrefix(open) { text.removeFirst(open.count) }
        if text.hasSuffix(close) {
            text.removeLast(close.count)
        } else if streaming, let partial = (2..<close.count).reversed().first(where: { text.hasSuffix(close.prefix($0)) }) {
            text.removeLast(partial)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finish(_ id: UUID, with raw: String) {
        isStreaming = false
        let text = Self.clean(raw)
        guard !text.isEmpty, let index = versions.firstIndex(where: { $0.id == id }) else {
            discardVersion(id)
            return
        }
        versions[index].text = text
        versions[index].messages.append(ChatMessage(role: "assistant", content: text))
        if selectedVersion == index { result = text }
        typedAdjustment = nil
        saveToHistory()
    }

    // MARK: - Historique

    var historyResults: [HistoryEntry] { history.search(input) }

    private func saveToHistory() {
        guard let id = conversationID, let original = originalText,
              versions.indices.contains(selectedVersion), !versions[selectedVersion].text.isEmpty else { return }
        let current = versions[selectedVersion]
        history.upsert(HistoryEntry(id: id, date: Date(), action: action.name, original: original,
                                    result: current.text, messages: current.messages,
                                    versions: versions.filter { !$0.text.isEmpty }, selectedVersion: selectedVersion))
    }

    func toggleHistory() {
        if showingHistory {
            showingHistory = false
            input = stashedInput
        } else {
            guard !isStreaming else { return }
            stashedInput = input
            input = ""
            historySelection = 0
            showingHistory = true
        }
        focusInputSoon()
    }

    func moveHistorySelection(_ delta: Int) {
        let count = historyResults.count
        guard count > 0 else { return }
        historySelection = min(max(historySelection + delta, 0), count - 1)
    }

    /// Recalé à chaque frappe dans la recherche.
    func historyQueryChanged() {
        historySelection = 0
    }

    private var selectedHistoryEntry: HistoryEntry? {
        let results = historyResults
        return results.indices.contains(historySelection) ? results[historySelection] : nil
    }

    /// Rouvre la conversation pour pouvoir continuer à l'ajuster.
    func openHistorySelection() {
        guard let entry = selectedHistoryEntry else { return }
        cancel()
        showingHistory = false
        stashedInput = ""
        input = ""
        error = nil
        adjusting = false
        conversationID = entry.id
        originalText = entry.original
        versions = entry.versions ?? [Version(id: UUID(), label: "Défaut", preset: nil, messages: entry.messages, text: entry.result)]
        selectedVersion = min(entry.selectedVersion ?? 0, versions.count - 1)
        result = versions[selectedVersion].text
        if let index = config.actions.firstIndex(where: { $0.name == entry.action }) {
            selectedAction = index
        }
    }

    func copyHistorySelection() {
        guard selectedHistoryEntry != nil else { return }
        openHistorySelection()
        copyResult()
    }

    func deleteHistorySelection() {
        guard let entry = selectedHistoryEntry else { return }
        history.delete(entry.id)
        objectWillChange.send()
        historySelection = min(historySelection, max(historyResults.count - 1, 0))
    }

    private func fail(_ id: UUID, _ error: Error) {
        isStreaming = false
        if let urlError = error as? URLError,
           [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut].contains(urlError.code) {
            self.error = "Impossible de joindre \(config.baseURL) — le serveur LLM est-il lancé ?"
        } else {
            self.error = error.localizedDescription
        }
        discardVersion(id)
    }

    /// Retire une version qui n'a rien produit et remet la saisie pour pouvoir réessayer.
    private func discardVersion(_ id: UUID) {
        versions.removeAll { $0.id == id }
        if versions.isEmpty {
            // Échec du premier appel : on revient à la saisie du texte.
            if input.isEmpty { input = originalText ?? "" }
            originalText = nil
            conversationID = nil
            focusInputSoon()
        } else {
            selectedVersion = min(selectionBeforeRun, versions.count - 1)
            result = versions[selectedVersion].text
            if input.isEmpty, let typed = typedAdjustment { input = typed }
        }
        typedAdjustment = nil
    }
}
