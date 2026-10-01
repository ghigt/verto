import AppKit
import SwiftUI

/// Brouillon de config édité par la fenêtre de réglages. Rien n'est appliqué avant « Enregistrer ».
/// `ObservableObject` plutôt que `@State` : voir la note dans `ContentView`.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var config = Config()
    /// config.json illisible : la fenêtre affiche les valeurs par défaut, et enregistrer écrasera le fichier.
    @Published var loadError: String?
    @Published var saveError: String?
    @Published var tab = 0
    @Published var selectedAction: Int? = 0 { didSet { syncLanguageDrafts() } }
    @Published var selectedAdjustment: Int? = 0
    @Published var models: [String] = []
    @Published var modelsError: String?
    @Published var fetchingModels = false
    /// Texte brut des champs de langues : reformater la liste à chaque frappe empêcherait de taper « fr, en ».
    @Published var languagesDraft = ""
    @Published var targetsDraft = ""

    var onSave: ((Config) -> Void)?
    var onClose: (() -> Void)?

    func load() {
        let (config, error) = Config.load()
        self.config = config
        loadError = error
        saveError = nil
        models = []
        modelsError = nil
        selectedAction = config.actions.isEmpty ? nil : 0
        selectedAdjustment = config.adjustments.isEmpty ? nil : 0
    }

    var validationError: String? {
        let url = config.baseURL.trimmingCharacters(in: .whitespaces)
        if URL(string: url)?.scheme?.hasPrefix("http") != true { return "URL du serveur invalide." }
        if HotKey.parse(config.hotkey) == nil { return "Raccourci invalide (ex. option+space, ctrl+option+t)." }
        if config.actions.isEmpty { return "Il faut au moins une action." }
        if config.actions.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Chaque action doit avoir un nom."
        }
        if config.adjustments.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Chaque ajustement doit avoir un nom."
        }
        return nil
    }

    func save() {
        guard validationError == nil else { return }
        config.baseURL = config.baseURL.trimmingCharacters(in: .whitespaces)
        config.model = config.model.trimmingCharacters(in: .whitespaces)
        do {
            try config.save()
            loadError = nil
            onSave?(config)
            onClose?()
        } catch {
            saveError = "Impossible d'enregistrer : \(error.localizedDescription)"
        }
    }

    func fetchModels() {
        fetchingModels = true
        modelsError = nil
        let config = self.config
        Task {
            do {
                let list = try await LLMClient.listModels(config)
                models = list
                if list.isEmpty { modelsError = "Aucun modèle sur le serveur." }
            } catch {
                modelsError = error.localizedDescription
            }
            fetchingModels = false
        }
    }

    // MARK: - Langues de l'action sélectionnée

    private func syncLanguageDrafts() {
        guard let i = selectedAction, config.actions.indices.contains(i) else {
            languagesDraft = ""; targetsDraft = ""; return
        }
        languagesDraft = config.actions[i].languages?.joined(separator: ", ") ?? ""
        targetsDraft = config.actions[i].targets?.joined(separator: ", ") ?? ""
    }

    func languagesBinding(_ keyPath: WritableKeyPath<Action, [String]?>, draft: ReferenceWritableKeyPath<SettingsModel, String>) -> Binding<String> {
        Binding(
            get: { self[keyPath: draft] },
            set: { text in
                self[keyPath: draft] = text
                guard let i = self.selectedAction, self.config.actions.indices.contains(i) else { return }
                let codes = text.split(whereSeparator: { $0 == "," || $0 == " " }).map { $0.lowercased() }
                self.config.actions[i][keyPath: keyPath] = codes.isEmpty ? nil : codes
            })
    }
}

@MainActor
final class SettingsWindowController {
    let model = SettingsModel()
    private var window: NSWindow?

    func show() {
        model.load()
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Réglages de Verto"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.setContentSize(NSSize(width: 720, height: 540))
        window.contentMinSize = NSSize(width: 640, height: 460)
        model.onClose = { [weak window] in window?.close() }
        return window
    }
}

// MARK: - Vues

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.loadError {
                banner(error + " — enregistrer remplacera le fichier.")
            }
            TabView(selection: $model.tab) {
                GeneralSettings(model: model)
                    .tabItem { Text("Général") }.tag(0)
                ActionListEditor(items: $model.config.actions, selection: $model.selectedAction,
                                 minCount: 1, shortcut: "⌘", newName: "Nouvelle action",
                                 help: "Prompt vide = le texte saisi est envoyé tel quel (comme « Libre »).") {
                    languageFields
                }
                .tabItem { Text("Actions") }.tag(1)
                ActionListEditor(items: $model.config.adjustments, selection: $model.selectedAdjustment,
                                 minCount: 0, shortcut: "⌥", newName: "Nouvel ajustement",
                                 help: "Consigne appliquée au dernier résultat (palette ⇥ ou ⌥1…⌥9).") {
                    EmptyView()
                }
                .tabItem { Text("Ajustements") }.tag(2)
            }
            .padding([.horizontal, .top], 12)
            footer
        }
        .frame(minWidth: 640, minHeight: 460)
    }

    private var languageFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Traduction auto") {
                TextField("ex. fr, en", text: model.languagesBinding(\.languages, draft: \.languagesDraft))
            }
            LabeledContent("Cibles proposées") {
                TextField("ex. en, fr, es, de", text: model.languagesBinding(\.targets, draft: \.targetsDraft))
            }
            Text("Codes de langue. La langue du texte est détectée et la cible est l'autre langue de la paire ; "
                 + "« {target} » dans le prompt est remplacé par la langue cible. Vide = pas de traduction.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.orange)
    }

    private var footer: some View {
        HStack {
            Button("Ouvrir config.json") {
                // `open -t` : éditeur de texte par défaut, plutôt que l'app associée aux .json.
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-t", Config.fileURL.path]
                try? process.run()
            }
                .help(Config.fileURL.path)
            Spacer()
            if let error = model.saveError ?? model.validationError {
                Text(error).font(.callout).foregroundStyle(.red).lineLimit(2)
            }
            Button("Annuler") { model.onClose?() }
            Button("Enregistrer") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.validationError != nil)
        }
        .padding(12)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Serveur LLM (compatible OpenAI)") {
                TextField("URL", text: $model.config.baseURL, prompt: Text("http://localhost:11434/v1"))
                SecureField("Clé d'API", text: $model.config.apiKey, prompt: Text("facultative"))
                HStack {
                    TextField("Modèle", text: $model.config.model, prompt: Text("vide = premier modèle du serveur"))
                    Menu {
                        ForEach(model.models, id: \.self) { name in
                            Button(name) { model.config.model = name }
                        }
                        if !model.models.isEmpty { Divider() }
                        Button(model.fetchingModels ? "Chargement…" : "Lister les modèles du serveur") { model.fetchModels() }
                            .disabled(model.fetchingModels)
                        Button("Premier modèle du serveur") { model.config.model = "" }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Choisir parmi les modèles du serveur")
                }
                if let error = model.modelsError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Toggle("Température personnalisée", isOn: Binding(
                    get: { model.config.temperature != nil },
                    set: { model.config.temperature = $0 ? 0.1 : nil }))
                if let temperature = model.config.temperature {
                    LabeledContent("Température") {
                        HStack {
                            Slider(value: Binding(
                                get: { temperature },
                                set: { model.config.temperature = ($0 * 20).rounded() / 20 }), in: 0...1.5)
                            Text(String(format: "%.2f", temperature)).monospacedDigit().frame(width: 36)
                        }
                    }
                    Text("Plus haut = plus varié, moins fidèle au texte.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Fenêtre") {
                TextField("Raccourci global", text: $model.config.hotkey, prompt: Text("option+space"))
                Text("Modificateurs cmd, option, ctrl, shift + une touche (lettre, chiffre, space, f1…f12), ex. ctrl+option+t.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Pré-remplir avec le presse-papiers", isOn: $model.config.prefillFromClipboard)
            }
            Section("Historique") {
                // HStack centré plutôt que LabeledContent : celui-ci aligne sur la ligne de base et le stepper déborde.
                HStack {
                    TextField("Conversations gardées", value: $model.config.historyLimit, format: .number)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $model.config.historyLimit, in: 0...10_000, step: 50).labelsHidden()
                }
                Text("0 = historique désactivé. Stocké en clair dans ~/.config/verto/history.json.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Liste éditable d'actions ou d'ajustements : liste à gauche, détail à droite.
private struct ActionListEditor<Extra: View>: View {
    @Binding var items: [Action]
    @Binding var selection: Int?
    let minCount: Int
    let shortcut: String
    let newName: String
    let help: String
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Text(item.name.isEmpty ? "Sans nom" : item.name)
                                .foregroundStyle(item.name.isEmpty ? .secondary : .primary)
                            Spacer()
                            if index < 9 {
                                Text("\(shortcut)\(index + 1)").foregroundStyle(.tertiary).monospacedDigit()
                            }
                        }
                        .tag(index)
                    }
                }
                Divider()
                HStack(spacing: 2) {
                    toolButton("plus", "Ajouter") {
                        let at = selection.map { $0 + 1 } ?? items.count
                        items.insert(Action(name: newName, prompt: ""), at: at)
                        selection = at
                    }
                    toolButton("minus", "Supprimer", disabled: selection == nil || items.count <= minCount) {
                        guard let i = selection, items.indices.contains(i) else { return }
                        items.remove(at: i)
                        selection = items.isEmpty ? nil : min(i, items.count - 1)
                    }
                    Spacer()
                    toolButton("chevron.up", "Monter", disabled: (selection ?? 0) == 0) { move(-1) }
                    toolButton("chevron.down", "Descendre", disabled: selection.map { $0 >= items.count - 1 } ?? true) { move(1) }
                }
                .padding(4)
            }
            .frame(width: 200)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))

            if let i = selection, items.indices.contains(i) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Nom") { TextField("Nom", text: field(\.name)).labelsHidden() }
                    Text("Prompt").font(.headline)
                    TextEditor(text: field(\.prompt))
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
                    Text(help).font(.caption).foregroundStyle(.secondary)
                    extra()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(items.isEmpty ? "Aucun élément — ajoute-en un avec +." : "Sélectionne un élément.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
    }

    private func field(_ keyPath: WritableKeyPath<Action, String>) -> Binding<String> {
        Binding(
            get: { selection.flatMap { items.indices.contains($0) ? items[$0][keyPath: keyPath] : nil } ?? "" },
            set: { value in
                guard let i = selection, items.indices.contains(i) else { return }
                items[i][keyPath: keyPath] = value
            })
    }

    private func move(_ offset: Int) {
        guard let i = selection, items.indices.contains(i + offset) else { return }
        items.swapAt(i, i + offset)
        selection = i + offset
    }

    private func toolButton(_ icon: String, _ help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 20, height: 18) }
            .buttonStyle(.borderless)
            .disabled(disabled)
            .help(help)
    }
}
