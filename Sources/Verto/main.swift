import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: PanelController!
    private var vm: ChatViewModel!
    private let hotKey = HotKey()
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let (config, error) = Config.load()
        vm = ChatViewModel(config: config)
        vm.error = error
        panel = PanelController(vm: vm)

        HotKey.onPress = { [weak self] in self?.panel.toggle() }
        registerHotKey()
        setupMenus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
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
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Verto")
        statusItem.button?.toolTip = "Verto — \(vm.config.hotkey)"

        let menu = NSMenu()
        menu.addItem(withTitle: "Ouvrir (\(vm.config.hotkey))", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Éditer la config…", action: #selector(editConfig), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Recharger la config", action: #selector(reloadConfig), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

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

    @objc private func openPanel() { panel.show() }

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
        if let item = statusItem.menu?.items.first { item.title = "Ouvrir (\(config.hotkey))" }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
