import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: PanelController!
    private var vm: ChatViewModel!
    private let hotKey = HotKey()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var toggleIconItem: NSMenuItem!

    private static let hideIconKey = "hideMenuBarIcon"
    private var iconHidden: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hideIconKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hideIconKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIcon.make()
        let (config, error) = Config.load()
        vm = ChatViewModel(config: config)
        vm.error = error
        panel = PanelController(vm: vm)

        HotKey.onPress = { [weak self] in self?.panel.toggle() }
        registerHotKey()
        setupMenus()
    }

    /// Relancer Verto.app alors qu'il tourne déjà : ouvre la fenêtre et réaffiche l'icône si elle était masquée.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if iconHidden { setIconHidden(false) }
        panel.show()
        return false
    }

    private func registerHotKey() {
        if !hotKey.register(vm.config.hotkey) {
            vm.error = "Raccourci « \(vm.config.hotkey) » invalide ou déjà utilisé."
        }
        statusItem?.button?.toolTip = "Verto — \(vm.config.hotkey)"
    }

    private func setupMenus() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.make()
        statusItem.button?.toolTip = "Verto — \(vm.config.hotkey)"
        statusItem.isVisible = !iconHidden

        menu.delegate = self
        menu.addItem(withTitle: "Ouvrir", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Éditer la config…", action: #selector(editConfig), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Recharger la config", action: #selector(reloadConfig), keyEquivalent: "").target = self
        menu.addItem(.separator())
        toggleIconItem = menu.addItem(withTitle: "", action: #selector(toggleIcon), keyEquivalent: "")
        toggleIconItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        // Le même menu est accessible depuis la fenêtre (⌘,), même quand l'icône est masquée.
        panel.onShowMenu = { [weak self] view, point in
            guard let self else { return }
            self.menu.popUp(positioning: nil, at: point, in: view)
        }

        // Menu Édition invisible : active ⌘V / ⌘X / ⌘A / ⌘Z dans le champ de saisie.
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first?.title = "Ouvrir (\(vm.config.hotkey))"
        toggleIconItem.title = iconHidden ? "Afficher l'icône dans la barre de menus"
                                          : "Masquer l'icône de la barre de menus"
    }

    @objc private func openPanel() { panel.show() }

    @objc private func toggleIcon() {
        let hide = !iconHidden
        setIconHidden(hide)
        if hide {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Icône masquée"
            alert.informativeText = """
            Verto reste actif : ouvre-le avec \(vm.config.hotkey).

            Pour réafficher l'icône : ⌘, dans la fenêtre de Verto → « Afficher l'icône », \
            ou relance simplement Verto.app.
            """
            alert.runModal()
        }
    }

    private func setIconHidden(_ hidden: Bool) {
        iconHidden = hidden
        statusItem.isVisible = !hidden
    }

    @objc private func editConfig() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-t", Config.fileURL.path]
        try? process.run()
    }

    @objc private func reloadConfig() {
        let (config, error) = Config.load()
        vm.apply(config: config)
        vm.error = error
        registerHotKey()
    }
}

// `Verto --export-iconset <dossier>` : utilisé par build.sh pour générer l'icône de l'app.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--export-iconset" {
    try MainActor.assumeIsolated {
        try AppIcon.exportIconset(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
