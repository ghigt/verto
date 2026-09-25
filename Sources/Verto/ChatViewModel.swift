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
    private var messages: [ChatMessage] = []
    private var task: Task<Void, Never>?
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
    }

    var action: Action { config.actions[selectedAction] }
    var hasConversation: Bool { originalText != nil }

    func apply(config: Config) {
        cancel()
        self.config = config
        modelName = config.model
        selectedAction = min(selectedAction, config.actions.count - 1)
    }

    // MARK: - Actions

    func submit() {
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

    /// Applique un ajustement prédéfini (ton, longueur…) au dernier résultat.
    func adjust(_ index: Int) {
        guard config.adjustments.indices.contains(index), hasConversation, !isStreaming, !result.isEmpty else { return }
        typedAdjustment = nil
        sendAdjustment(config.adjustments[index].prompt)
    }

    private func sendAdjustment(_ request: String) {
        messages.append(ChatMessage(role: "user", content: action.prompt.isEmpty ? request : Self.adjustment(request)))
        run()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func reset() {
        cancel()
        messages = []
        originalText = nil
        result = ""
        error = nil
        input = ""
        isStreaming = false
    }

    func copyResult() {
        guard !result.isEmpty, !isStreaming else { return }
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
        messages = []
        if !action.prompt.isEmpty {
            messages.append(ChatMessage(role: "system", content: action.prompt + Self.outputRule))
        }
        messages.append(ChatMessage(role: "user", content: action.prompt.isEmpty ? text : "<text>\n\(text)\n</text>"))
        run()
    }

    private func run() {
        error = nil
        isStreaming = true
        let config = self.config
        let messages = self.messages
        task = Task { [weak self] in
            var acc = ""
            do {
                if config.model.isEmpty, let model = try? await LLMClient.resolveModel(config) {
                    self?.modelName = model
                }
                for try await chunk in LLMClient.stream(config: config, messages: messages) {
                    acc += chunk
                    self?.result = Self.clean(acc, streaming: true)
                }
                self?.finish(with: acc)
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                    self?.finish(with: acc)
                } else {
                    self?.fail(error)
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

    private func finish(with raw: String) {
        let text = Self.clean(raw)
        if !text.isEmpty { result = text }
        isStreaming = false
        if text.isEmpty {
            rollbackLastUserMessage()
        } else {
            messages.append(ChatMessage(role: "assistant", content: text))
        }
    }

    private func fail(_ error: Error) {
        isStreaming = false
        if let urlError = error as? URLError,
           [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut].contains(urlError.code) {
            self.error = "Impossible de joindre \(config.baseURL) — le serveur LLM est-il lancé ?"
        } else {
            self.error = error.localizedDescription
        }
        rollbackLastUserMessage()
    }

    /// Remet le dernier message utilisateur dans le champ pour pouvoir réessayer.
    private func rollbackLastUserMessage() {
        guard messages.last?.role == "user" else { return }
        messages.removeLast()
        if !messages.contains(where: { $0.role == "assistant" }) {
            if input.isEmpty { input = originalText ?? "" }
            messages = []
            originalText = nil
        } else if input.isEmpty, let typed = typedAdjustment {
            input = typed
        }
        typedAdjustment = nil
    }
}
