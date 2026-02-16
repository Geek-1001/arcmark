import AppKit
import Carbon.HIToolbox

final class ShortcutRecorderView: NSView {
    var onShortcutChanged: ((KeyboardShortcut?) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Show or Hide Window")
    private let recorderBox = RecorderBoxView()

    private var currentShortcut: KeyboardShortcut?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    func configure(shortcut: KeyboardShortcut?) {
        currentShortcut = shortcut
        recorderBox.configure(shortcut: shortcut)
    }

    private func setupUI() {
        titleLabel.font = ThemeConstants.Fonts.systemFont(size: 13, weight: .regular)
        titleLabel.textColor = ThemeConstants.Colors.darkGray
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        recorderBox.translatesAutoresizingMaskIntoConstraints = false
        recorderBox.onShortcutRecorded = { [weak self] shortcut in
            self?.currentShortcut = shortcut
            self?.onShortcutChanged?(shortcut)
        }

        addSubview(titleLabel)
        addSubview(recorderBox)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            recorderBox.trailingAnchor.constraint(equalTo: trailingAnchor),
            recorderBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            recorderBox.widthAnchor.constraint(equalToConstant: 100),
            recorderBox.heightAnchor.constraint(equalToConstant: 28),

            heightAnchor.constraint(equalToConstant: 28),
        ])
    }
}

// MARK: - Recorder Box View

private final class RecorderBoxView: BaseView {
    var onShortcutRecorded: ((KeyboardShortcut?) -> Void)?

    private let shortcutLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton()

    private var currentShortcut: KeyboardShortcut?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    func configure(shortcut: KeyboardShortcut?) {
        currentShortcut = shortcut
        updateDisplay()
    }

    private func setupUI() {
        layer?.backgroundColor = ThemeConstants.Colors.darkGray.withAlphaComponent(0.08).cgColor
        layer?.cornerRadius = ThemeConstants.CornerRadius.medium

        shortcutLabel.font = ThemeConstants.Fonts.systemFont(size: 12, weight: .medium)
        shortcutLabel.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.high)
        shortcutLabel.alignment = .center
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear shortcut")
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isHidden = true
        clearButton.contentTintColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.low)

        addSubview(shortcutLabel)
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            shortcutLabel.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -ThemeConstants.Spacing.medium),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ThemeConstants.Spacing.small),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),
        ])

        updateDisplay()
    }

    private func updateDisplay() {
        if isRecording {
            shortcutLabel.stringValue = "Type shortcut..."
            shortcutLabel.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(0.5)
            clearButton.isHidden = true
            layer?.borderWidth = 1.5
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else if let shortcut = currentShortcut {
            shortcutLabel.stringValue = shortcut.displayString
            shortcutLabel.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.high)
            clearButton.isHidden = false
            layer?.borderWidth = 0
        } else {
            shortcutLabel.stringValue = "Click to set"
            shortcutLabel.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.low)
            clearButton.isHidden = true
            layer?.borderWidth = 0
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Don't enter recording if click was on clear button
        let point = convert(event.locationInWindow, from: nil)
        if clearButton.frame.contains(point) && !clearButton.isHidden {
            return
        }

        if !isRecording {
            isRecording = true
            window?.makeFirstResponder(self)
            updateDisplay()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escape cancels recording
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            updateDisplay()
            window?.makeFirstResponder(nil)
            return
        }

        // Ignore modifier-only presses
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let significantModifiers = modifiers.intersection([.command, .option, .control, .shift])
        if significantModifiers.isEmpty {
            return
        }

        let carbonModifiers = KeyboardShortcut.carbonModifiers(from: modifiers)
        let shortcut = KeyboardShortcut(keyCode: UInt32(event.keyCode), modifierFlags: carbonModifiers)

        // Validate: requires Cmd, Option, or Control
        guard shortcut.isValid else { return }

        currentShortcut = shortcut
        isRecording = false
        updateDisplay()
        window?.makeFirstResponder(nil)
        onShortcutRecorded?(shortcut)
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't process modifier-only events, just let them pass
        if isRecording { return }
        super.flagsChanged(with: event)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            updateDisplay()
        }
        return super.resignFirstResponder()
    }

    @objc private func clearShortcut() {
        currentShortcut = nil
        isRecording = false
        updateDisplay()
        onShortcutRecorded?(nil)
    }

    override func handleHoverStateChanged() {
        if !isRecording {
            layer?.backgroundColor = ThemeConstants.Colors.darkGray.withAlphaComponent(isHovered ? 0.12 : 0.08).cgColor
        }
    }
}
