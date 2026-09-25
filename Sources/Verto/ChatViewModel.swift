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

    /// Appelé pour fermer le panneau (après une copie).
    var onClose: (() -> Void)?

    private static let actionKey = "selectedAction"
    /// Ajouté à chaque prompt d'action pour éviter les préambules des petits modèles.
    private static let outputRule = """

    Règle stricte : réponds uniquement avec le texte final, prêt à être copié-collé. \
    Aucune introduction (« Voici… »), aucune alternative, aucune explication, aucun guillemet autour. \
    Si l'utilisateur demande ensuite un ajustement, applique-le et renvoie à nouveau uniquement le texte final complet.
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
        if let _ = originalText {
            messages.append(ChatMessage(role: "user", content: action.prompt.isEmpty ? text : Self.adjustment(text)))
            run()
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
        Ajuste ta dernière réponse selon cette consigne : \(request)
        Garde la même tâche et la même langue de sortie que ta dernière réponse. Renvoie uniquement le texte final complet.
        """
    }

    private func start(with text: String) {
        originalText = text
        messages = []
        if !action.prompt.isEmpty {
            messages.append(ChatMessage(role: "system", content: action.prompt + Self.outputRule))
        }
        messages.append(ChatMessage(role: "user", content: text))
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
                    self?.result = acc
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

    private func finish(with text: String) {
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
        guard messages.last?.role == "user", let last = messages.popLast() else { return }
        if input.isEmpty { input = last.content }
        if !messages.contains(where: { $0.role == "assistant" }) {
            messages = []
            originalText = nil
        }
    }
}
