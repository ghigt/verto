import Foundation

struct Action: Codable, Hashable {
    var name: String
    /// Instruction envoyée en message système. Vide = le texte saisi est le prompt lui-même.
    var prompt: String
}

struct Config: Codable {
    /// Endpoint OpenAI-compatible (Ollama, LM Studio, llama.cpp server…)
    var baseURL = "http://localhost:11434/v1"
    var apiKey = ""
    /// Vide = premier modèle renvoyé par `GET {baseURL}/models`.
    var model = ""
    var temperature: Double? = nil
    var hotkey = "option+space"
    /// Pré-remplit le champ avec le contenu du presse-papiers à l'ouverture.
    var prefillFromClipboard = false
    var actions: [Action] = Config.defaultActions

    static let defaultActions: [Action] = [
        Action(name: "Traduire EN", prompt: "Translate the user's text into English. Output only the translation, nothing else."),
        Action(name: "Traduire FR", prompt: "Traduis le texte de l'utilisateur en français. Réponds uniquement avec la traduction, sans commentaire."),
        Action(name: "Reformuler", prompt: "Reformule le texte de l'utilisateur pour qu'il soit clair, fluide et naturel, dans la même langue. Réponds uniquement avec le texte reformulé."),
        Action(name: "Corriger", prompt: "Corrige l'orthographe, la grammaire et la ponctuation du texte de l'utilisateur sans changer son style ni sa langue. Réponds uniquement avec le texte corrigé."),
        Action(name: "Libre", prompt: ""),
    ]

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/verto")
    }
    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? d.baseURL
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? d.apiKey
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? d.hotkey
        prefillFromClipboard = try c.decodeIfPresent(Bool.self, forKey: .prefillFromClipboard) ?? d.prefillFromClipboard
        let actions = try c.decodeIfPresent([Action].self, forKey: .actions) ?? []
        self.actions = actions.isEmpty ? d.actions : actions
    }

    /// Charge la config, en créant le fichier avec les valeurs par défaut s'il n'existe pas.
    static func load() -> (Config, error: String?) {
        let url = fileURL
        migrateLegacyConfig()
        guard let data = try? Data(contentsOf: url) else {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? defaultJSON.write(to: url, atomically: true, encoding: .utf8)
            return (Config(), nil)
        }
        do {
            return (try JSONDecoder().decode(Config.self, from: data), nil)
        } catch {
            return (Config(), "config.json invalide : \(error.localizedDescription)")
        }
    }

    /// Reprend la config de l'ancien nom de l'app (~/.config/ai-helper).
    private static func migrateLegacyConfig() {
        let fm = FileManager.default
        let legacy = fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/ai-helper/config.json")
        guard !fm.fileExists(atPath: fileURL.path), fm.fileExists(atPath: legacy.path) else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fm.copyItem(at: legacy, to: fileURL)
    }

    /// Écrit à la main pour garder un ordre de clés lisible.
    private static var defaultJSON: String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let d = Config()
        let actions = d.actions
            .map { "    { \"name\": \"\(esc($0.name))\", \"prompt\": \"\(esc($0.prompt))\" }" }
            .joined(separator: ",\n")
        return """
        {
          "baseURL": "\(d.baseURL)",
          "apiKey": "",
          "model": "",
          "temperature": 0.3,
          "hotkey": "\(d.hotkey)",
          "prefillFromClipboard": false,
          "actions": [
        \(actions)
          ]
        }

        """
    }
}
