import AppKit

/// Native presentation only. All Space operations remain owned by the application controller.
@MainActor
final class StatusWindow: NSObject {
    let window: NSWindow
    private let state = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let permission = NSTextField(labelWithString: "")
    private let backend = NSTextField(labelWithString: "")
    private let desktopTitle = NSTextField(labelWithString: "")
    private let desktopRow = NSStackView()
    private let enable = NSButton()
    private let authorize = NSButton()
    private let onToggle: () -> Void
    private let onAuthorize: () -> Void
    private let onDetails: () -> Void

    init(toggle: @escaping () -> Void, authorize authorizationAction: @escaping () -> Void, details: @escaping () -> Void) {
        onToggle = toggle
        onAuthorize = authorizationAction
        onDetails = details
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 636),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "SpaceKeys"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -26)
        ])

        let icon = NSImageView()
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") {
            icon.image = NSImage(contentsOf: url)
        }
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 66).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 66).isActive = true
        let title = label("SpaceKeys", size: 27, weight: .bold)
        let subtitle = label("Vos bureaux macOS, au clavier.", size: 13, secondary: true)
        let identity = column([title, subtitle], spacing: 4)
        let header = NSStackView(views: [icon, identity])
        header.spacing = 12
        root.addArrangedSubview(header)

        state.font = .systemFont(ofSize: 18, weight: .semibold)
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 3
        message.heightAnchor.constraint(equalToConstant: 44).isActive = true
        permission.font = .systemFont(ofSize: 12, weight: .medium)
        backend.font = .systemFont(ofSize: 12)
        backend.textColor = .secondaryLabelColor
        let checks = NSStackView(views: [permission, backend])
        checks.spacing = 20
        addCard(column([state, message, checks], spacing: 10), to: root)

        desktopTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        desktopRow.heightAnchor.constraint(equalToConstant: 32).isActive = true
        desktopRow.orientation = .horizontal
        desktopRow.spacing = 8
        desktopRow.distribution = .fillEqually
        let desktopHint = label("Numéros de Mission Control · écran sous le pointeur", size: 11, secondary: true)
        addCard(column([desktopTitle, desktopRow, desktopHint], spacing: 12), to: root)

        let shortcuts = column([
            label("Raccourcis", size: 13, weight: .semibold),
            shortcut("Changer de bureau", keys: "⌘  1…9, 0"),
            shortcut("Envoyer la fenêtre", keys: "⌘ ⇧  1…9, 0"),
            label("0 = bureau 10 · la fenêtre est envoyée sans la suivre.", size: 11, secondary: true),
            label("AZERTY : positions de la rangée numérique ( &  é  \" … ).", size: 11, secondary: true)
        ], spacing: 10)
        addCard(shortcuts, to: root)

        enable.target = self
        enable.action = #selector(toggleAction)
        enable.bezelStyle = .rounded
        enable.controlSize = .large
        authorize.title = "Réglages d’accessibilité…"
        authorize.target = self
        authorize.action = #selector(authorizeAction)
        authorize.bezelStyle = .rounded
        let actions = NSStackView(views: [enable, authorize])
        actions.spacing = 12
        root.addArrangedSubview(actions)
        let detailsButton = NSButton(title: "Détails techniques…", target: self, action: #selector(detailsAction))
        detailsButton.bezelStyle = .inline
        detailsButton.font = .systemFont(ofSize: 11)
        let footer = NSStackView(views: [label("Spaces natifs · SIP conservé", size: 11, secondary: true), NSView(), detailsButton])
        footer.distribution = .fill
        root.addArrangedSubview(footer)
        for view in root.arrangedSubviews where view !== header {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        window.contentView!.layoutSubtreeIfNeeded()
        // Fit the actual AppKit control metrics, including localization and system font sizing.
        let height = root.fittingSize.height + 44
        window.setContentSize(NSSize(width: 660, height: height))
        window.center()
    }

    func update(trusted: Bool, running: Bool, nativeMove: Bool, display: DisplaySpaces?, message text: String) {
        state.stringValue = !trusted ? "●  Autorisation nécessaire" : running ? "●  Raccourcis actifs" : "●  En pause"
        state.textColor = !trusted ? .systemOrange : running ? .systemGreen : .secondaryLabelColor
        message.stringValue = text
        permission.stringValue = trusted ? "✓ Accessibilité autorisée" : "! Accessibilité à autoriser"
        backend.stringValue = nativeMove ? "✓ Déplacement disponible" : "! Déplacement indisponible"
        enable.title = running ? "Mettre en pause" : "Activer les raccourcis"
        enable.isEnabled = trusted
        authorize.title = trusted ? "Accessibilité…" : "Autoriser l’accessibilité…"
        let desktops = display?.desktops ?? []
        let current = desktops.firstIndex(where: { $0.id == display?.current }).map { $0 + 1 }
        desktopTitle.stringValue = current.map { "Bureau \($0) actif   /   \(desktops.count) bureaux" } ?? "Bureau actif non disponible"
        let signature = desktops.map { "\($0.id)\($0.id == display?.current ? "*" : "")" }.joined(separator: ",")
        guard desktopRow.identifier?.rawValue != signature else { return }
        desktopRow.identifier = NSUserInterfaceItemIdentifier(signature)
        for view in desktopRow.arrangedSubviews { desktopRow.removeArrangedSubview(view); view.removeFromSuperview() }
        // Keep the ten shortcut destinations legible; other Spaces remain listed in technical details.
        for number in 1...10 {
            let chip = NSTextField(labelWithString: String(number))
            chip.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
            chip.alignment = .center
            chip.drawsBackground = true
            chip.backgroundColor = current == number ? .controlAccentColor : .quaternaryLabelColor
            chip.textColor = current == number ? .white : number <= desktops.count ? .labelColor : .tertiaryLabelColor
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 7
            chip.layer?.masksToBounds = true
            chip.heightAnchor.constraint(equalToConstant: 32).isActive = true
            chip.setAccessibilityLabel("Bureau \(number)\(current == number ? ", actif" : number > desktops.count ? ", absent" : "")")
            desktopRow.addArrangedSubview(chip)
        }
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        return field
    }

    private func column(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    private func shortcut(_ title: String, keys: String) -> NSStackView {
        let key = label(keys, size: 15, weight: .semibold)
        key.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        let row = NSStackView(views: [label(title, size: 13), NSView(), key])
        row.distribution = .fill
        return row
    }

    private func addCard(_ content: NSStackView, to root: NSStackView) {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0
        box.fillColor = .controlBackgroundColor
        box.cornerRadius = 12
        box.contentViewMargins = .zero
        content.translatesAutoresizingMaskIntoConstraints = false
        box.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: box.contentView!.topAnchor, constant: 15),
            content.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor, constant: -15)
        ])
        for view in content.arrangedSubviews { view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        root.addArrangedSubview(box)
    }

    @objc private func toggleAction() { onToggle() }
    @objc private func authorizeAction() { onAuthorize() }
    @objc private func detailsAction() { onDetails() }
}
