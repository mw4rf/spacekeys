import AppKit
import Carbon
import ServiceManagement

private let digits: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]

@MainActor
final class SpaceKeys: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var hotkeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var timer: Timer?
    private var running = false
    private var busy = false
    private var pending: (display: String, target: UInt64)?
    private var generation = 0
    private var lastMessage = "Prêt"
    private var lastApp: NSRunningApplication?
    private var statusWindow: StatusWindow?
    private var diagnosticsWindow: NSWindow?
    private var diagnosticsText: NSTextView?
    private var testWindow: NSWindow?
    private var testing = false
    private var heartbeats = 0
    private let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SpaceKeys.log")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "SK"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        installHandler()
        if CommandLine.arguments.contains("--lifecycle-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
                let alive = (self?.heartbeats ?? 0) >= 1
                print(alive ? "PASS: app controller survives and its timer responds" : "FAIL: app controller lifecycle")
                exit(alive ? 0 : 1)
            }
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            print(diagnostics())
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--native-move-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.testMove(nil) }
            return
        }
        if AXIsProcessTrusted() { start() }
        else { lastMessage = "Autorisation Accessibilité nécessaire" }
        refresh()
        showDiagnostics(nil)
    }

    @objc private func activated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != getpid(), app.activationPolicy == .regular else { return }
        lastApp = app
    }

    private func displays() -> [DisplaySpaces] {
        DisplaySpaces.decode(SKCopyDisplays() as? [[String: Any]] ?? [])
    }

    private func pointerDisplay() throws -> DisplaySpaces {
        let available = displays()
        guard !available.isEmpty else { throw Failure("macOS ne fournit pas la liste des Spaces.") }
        if available.count == 1 { return available[0] }
        let point = CGEvent(source: nil)?.location ?? .zero
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  CGDisplayBounds(id).contains(point), let uuid = CGDisplayCreateUUIDFromDisplayID(id) else { continue }
            let name = CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
            if let found = available.first(where: { $0.identifier == name }) { return found }
        }
        throw Failure("Impossible d’identifier l’écran sous le pointeur.")
    }

    private func installHandler() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr else { return status }
            let controller = Unmanaged<SpaceKeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { controller.handle(Int(key.id)) }
            return noErr
        }
        let result = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &event,
                                         Unmanaged.passUnretained(self).toOpaque(), &handler)
        if result != noErr { report("Impossible d’installer les raccourcis (\(result)).") }
    }

    @objc private func toggle(_ sender: Any?) {
        running ? stop() : start()
        refresh()
    }

    private func start() {
        guard !running else { return }
        guard AXIsProcessTrusted() else { requestPermission(nil); return }
        guard #available(macOS 27, *) else { report("Cette version de SpaceKeys nécessite macOS 27."); return }
        guard handler != nil else { report("Le gestionnaire de raccourcis n’est pas disponible."); return }
        for move in [false, true] {
            for (index, code) in digits.enumerated() {
                var reference: EventHotKeyRef?
                let id = EventHotKeyID(signature: 0x53504b59, id: UInt32(index + 1 + (move ? 10 : 0)))
                let modifiers = UInt32(cmdKey | (move ? shiftKey : 0))
                let result = RegisterEventHotKey(code, modifiers, id, GetApplicationEventTarget(), 0, &reference)
                guard result == noErr, let reference else {
                    stop()
                    report("⌘\(move ? "⇧" : "")\(index == 9 ? 0 : index + 1) est déjà pris. Libérez ce raccourci dans l’autre application, puis activez SpaceKeys.")
                    return
                }
                hotkeys.append(reference)
            }
        }
        running = true
        lastMessage = "Actif — ⌘1…0 / ⌘⇧1…0"
        log("hotkeys registered: 20")
    }

    private func stop() {
        hotkeys.forEach { UnregisterEventHotKey($0) }
        hotkeys.removeAll()
        running = false
        pending = nil
        // An already-posted native gesture is allowed to finish.
        lastMessage = "En pause"
    }

    private func handle(_ id: Int) {
        guard running, !testing else { return }
        if !AXIsProcessTrusted() { stop(); report("Autorisation Accessibilité retirée."); return }
        log("key: \(id)")
        do {
            if id <= 10 {
                let display = try pointerDisplay()
                let target = try display.destination(number: id)
                requestSwitch(display: display.identifier, target: target.id)
            } else {
                guard !busy else { throw Failure("Attendez la fin du changement de bureau avant d’envoyer une fenêtre.") }
                try sendFocusedWindow(number: id - 10)
            }
        } catch { report(error.localizedDescription) }
    }

    private func requestSwitch(display: String, target: UInt64) {
        generation += 1
        if busy { pending = (display, target); return }
        beginSwitch(display: display, target: target)
    }

    /// Serialize native gestures; only the latest requested destination waits.
    /// Read actual WindowServer state, never a preference-file snapshot or a predicted desktop number.
    private func beginSwitch(display identifier: String, target: UInt64) {
        do {
            guard let display = displays().first(where: { $0.identifier == identifier }) else {
                throw Failure("L’écran du bureau demandé a été déconnecté.")
            }
            let steps = try display.steps(to: target)
            if steps == 0 { drain(); return }
            // Every step has fresh timestamps and event identities; never replay the same swipe.
            let gestures = try (0..<abs(steps)).map { _ in
                try DockGesture.events(right: steps > 0, steps: abs(steps))
            }
            busy = true
            let start = ProcessInfo.processInfo.systemUptime
            log("switch: \(display.current) -> \(target), steps=\(steps)")
            gestures.forEach { phases in phases.forEach { $0.post(tap: .cgSessionEventTap) } }
            poll(timeout: 0.65, condition: { [weak self] in
                self?.displays().first(where: { $0.identifier == identifier })?.current == target
            }) { [weak self] success in
                guard let self else { return }
                let elapsed = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
                self.log("switch result: success=\(success), target=\(target), elapsed_ms=\(elapsed)")
                if !success {
                    self.report("Le saut instantané n’a pas atteint le bureau demandé. Aucune transition animée n’a été lancée. Vérifiez le geste « Balayer entre les applications en plein écran » du Trackpad.")
                } else { self.lastMessage = "Bureau atteint en \(elapsed) ms" }
                // Dock still finishes the gesture after reporting the new Space.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.drain() }
            }
        } catch { report(error.localizedDescription); drain() }
    }

    private func drain() {
        busy = false
        guard let next = pending else { return }
        pending = nil
        beginSwitch(display: next.display, target: next.target)
    }

    private func membership(_ window: UInt32) -> [UInt64] {
        (SKCopyWindowSpaces(window) as? [NSNumber] ?? []).map(\.uint64Value)
    }

    private func focusedWindow() throws -> UInt32 {
        let front = NSWorkspace.shared.frontmostApplication
        let owner = front?.processIdentifier == getpid() ? lastApp : front
        guard let owner, owner.activationPolicy == .regular, owner.processIdentifier != getpid() else {
            throw Failure("Aucune fenêtre d’application active à envoyer.")
        }
        let app = AXUIElementCreateApplication(owner.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw Failure("L’application ne fournit pas sa fenêtre active.")
        }
        let window = value as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.25)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success,
              role as? String == kAXWindowRole else {
            throw Failure("Fermez la boîte de dialogue active avant d’envoyer la fenêtre.")
        }
        var fullscreen: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreen)
        guard fullscreen as? Bool != true else { throw Failure("Une fenêtre en plein écran macOS ne peut pas être envoyée.") }
        var id: UInt32 = 0
        guard SKGetWindowID(window, &id) == .success, id != 0 else { throw Failure("Impossible d’identifier la fenêtre active.") }
        return id
    }

    private func sendFocusedWindow(number: Int) throws {
        let window = try focusedWindow()
        let spaces = membership(window)
        guard spaces.count == 1,
              let display = displays().first(where: { $0.order.contains(where: { $0.id == spaces[0] }) }),
              let origin = display.order.first(where: { $0.id == spaces[0] }), origin.kind == 0 else {
            throw Failure("Cette fenêtre n’appartient pas à un seul bureau ordinaire.")
        }
        let target = try display.destination(number: number)
        if origin.id == target.id { return }
        try move(window: window, to: target.id) { [weak self] success in
            self?.lastMessage = success ? "Fenêtre envoyée au bureau \(number)" : "Échec de l’envoi de la fenêtre"
        }
    }

    private func move(window: UInt32, to target: UInt64, completion: @escaping (Bool) -> Void) throws {
        guard WSMoveBridgedIsAvailable(), WSMoveBridged(window, target) else {
            throw Failure("L’opération de déplacement n’est pas disponible sur cette version de macOS.")
        }
        busy = true
        let start = ProcessInfo.processInfo.systemUptime
        poll(timeout: 0.8, condition: { [weak self] in self?.membership(window) == [target] }) { [weak self] success in
            guard let self else { return }
            self.log("move: window=\(window), target=\(target), success=\(success), elapsed_ms=\(Int((ProcessInfo.processInfo.systemUptime - start)*1000))")
            if !success { self.report("macOS n’a pas confirmé le déplacement de la fenêtre.") }
            completion(success)
            self.drain()
        }
    }

    private func poll(timeout: TimeInterval, condition: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        func tick() {
            if condition() { completion(true) }
            else if ProcessInfo.processInfo.systemUptime >= deadline { completion(false) }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { tick() } }
        }
        tick()
    }

    @objc private func requestPermission(_ sender: Any?) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showDiagnostics(_ sender: Any?) {
        if statusWindow == nil {
            statusWindow = StatusWindow(toggle: { [weak self] in self?.toggle(nil) },
                                        authorize: { [weak self] in self?.requestPermission(nil) },
                                        details: { [weak self] in self?.showTechnicalDetails() })
        }
        updateStatusWindow()
        statusWindow?.show()
    }

    private func updateStatusWindow() {
        statusWindow?.update(trusted: AXIsProcessTrusted(), running: running,
                             nativeMove: WSMoveBridgedIsAvailable(), display: try? pointerDisplay(),
                             message: lastMessage)
    }

    private func showTechnicalDetails() {
        if diagnosticsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 470),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "SpaceKeys — Détails techniques"
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: NSRect(x: 15, y: 65, width: 620, height: 390))
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds)
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.autoresizingMask = [.width]
            scroll.documentView = text
            window.contentView!.addSubview(scroll)
            let permission = NSButton(title: "Autoriser l’Accessibilité…", target: self, action: #selector(requestPermission(_:)))
            permission.frame = NSRect(x: 15, y: 18, width: 230, height: 32)
            permission.bezelStyle = .rounded
            permission.autoresizingMask = [.maxYMargin, .maxXMargin]
            window.contentView!.addSubview(permission)
            let enable = NSButton(title: "Activer / mettre en pause", target: self, action: #selector(toggle(_:)))
            enable.frame = NSRect(x: 260, y: 18, width: 230, height: 32)
            enable.bezelStyle = .rounded
            enable.autoresizingMask = [.maxYMargin, .maxXMargin]
            window.contentView!.addSubview(enable)
            diagnosticsWindow = window
            diagnosticsText = text
            window.center()
        }
        diagnosticsText?.string = diagnostics()
        NSApp.activate()
        diagnosticsWindow?.makeKeyAndOrderFront(nil)
    }

    private func diagnostics() -> String {
        var lines = ["SpaceKeys 1.1 — macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
                     "Accessibilité : \(AXIsProcessTrusted() ? "accordée" : "à autoriser")",
                     "Raccourcis : \(running ? "actifs" : "en pause")",
                     "Déplacement natif : \(WSMoveBridgedIsAvailable() ? "disponible" : "indisponible")",
                     "État : \(lastMessage)", "", "⌘1…9,0 : changer de bureau",
                     "⌘⇧1…9,0 : envoyer la fenêtre, sans la suivre",
                     "Sur AZERTY : touches de la rangée numérique ; Maj sert à envoyer.",
                     "", "Activer le geste Trackpad « Balayer entre les applications en plein écran ».",
                     ""]
        for display in displays() {
            lines.append("Écran \(display.identifier) — Space actif : \(display.current)")
            for (index, space) in display.desktops.enumerated() {
                lines.append("  Bureau \(index + 1) → identifiant \(space.id)\(space.id == display.current ? "  ●" : "")")
            }
        }
        lines += ["", "Journal : \(logURL.path)",
                  "Une seule app ; aucun tiling, redimensionnement, réseau ou changement de SIP.",
                  "Les mécanismes privés utilisés peuvent évoluer avec macOS."]
        return lines.joined(separator: "\n")
    }

    private func refresh() {
        heartbeats += 1
        if running && !AXIsProcessTrusted() { stop(); lastMessage = "Autorisation Accessibilité retirée" }
        let number = (try? pointerDisplay()).flatMap { display in display.desktops.firstIndex(where: { $0.id == display.current }) }.map { String($0 + 1) } ?? "?"
        item.button?.title = running ? "▣ \(number)" : "SK ⏸"
        item.button?.toolTip = lastMessage
        if statusWindow?.window.isVisible == true { updateStatusWindow() }
        if diagnosticsWindow?.isVisible == true { diagnosticsText?.string = diagnostics() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, "SpaceKeys — \(lastMessage)", nil)
        menu.addItem(.separator())
        add(menu, running ? "Mettre les raccourcis en pause" : "Activer les raccourcis", #selector(toggle(_:)))
        add(menu, "Autoriser l’Accessibilité…", #selector(requestPermission(_:)))
        add(menu, "État et raccourcis…", #selector(showDiagnostics(_:)))
        add(menu, "Tester avec une fenêtre temporaire…", #selector(testMove(_:)))
        menu.addItem(.separator())
        let login = add(menu, "Ouvrir à la connexion", #selector(toggleLogin(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        add(menu, "Quitter SpaceKeys", #selector(quit(_:)))
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    @objc private func toggleLogin(_ sender: Any?) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { report("Ouverture à la connexion : \(error.localizedDescription)") }
    }

    /// Native qualification uses only our own disposable window and restores its original Space.
    @objc private func testMove(_ sender: Any?) {
        guard !busy, !testing else { report("Une opération est déjà en cours."); return }
        do {
            let display = try pointerDisplay()
            guard let target = display.desktops.last(where: { $0.id != display.current }) else {
                throw Failure("Il faut au moins deux bureaux pour ce test.")
            }
            let window = NSWindow(contentRect: NSRect(x: 200, y: 180, width: 420, height: 180),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "SpaceKeys — Fenêtre temporaire de test"
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            testWindow = window
            testing = true
            let id = UInt32(window.windowNumber)
            let origin = display.current
            try move(window: id, to: target.id) { [weak self] moved in
                guard let self else { return }
                guard moved else {
                    self.testing = false; window.close(); self.testWindow = nil
                    self.finishTest(false)
                    return
                }
                do {
                    try self.move(window: id, to: origin) { restored in
                        self.testing = false
                        window.close()
                        self.testWindow = nil
                        self.lastMessage = restored ? "Test natif réussi : fenêtre envoyée puis rétablie" : "Retour de la fenêtre de test non confirmé"
                        self.log(self.lastMessage)
                        self.finishTest(restored)
                    }
                } catch {
                    self.testing = false; window.close(); self.testWindow = nil
                    self.report(error.localizedDescription); self.finishTest(false)
                }
            }
        } catch { testing = false; report(error.localizedDescription); finishTest(false) }
    }

    private func finishTest(_ success: Bool) {
        if CommandLine.arguments.contains("--native-move-test") {
            print(success ? "PASS: native owned-window move and restore" : "FAIL: native window move")
            exit(success ? 0 : 1)
        }
    }

    private func report(_ message: String) {
        lastMessage = message
        log("ERROR: \(message)")
        NSSound.beep()
        refresh()
    }

    private func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch { fputs("SpaceKeys log: \(error.localizedDescription)\n", stderr) }
    }

    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        stop()
        timer?.invalidate()
        testWindow?.close()
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let controller = SpaceKeys()
    application.delegate = controller
    // NSApplication.delegate, menu delegates and control targets do not own the controller.
    withExtendedLifetime(controller) { application.run() }
}
