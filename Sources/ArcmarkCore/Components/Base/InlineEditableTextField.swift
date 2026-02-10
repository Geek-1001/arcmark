import AppKit

/// A text field wrapper that provides inline editing behavior with commit/cancel
@MainActor
final class InlineEditableTextField: NSView {

    // MARK: - Properties

    let textField = NSTextField(string: "")

    private var isEditingTitle = false
    private var editingOriginalTitle: String?
    private var onEditCommit: ((String) -> Void)?
    private var onEditCancel: (() -> Void)?

    // MARK: - Configuration

    var font: NSFont {
        get { textField.font ?? ThemeConstants.Fonts.bodyRegular }
        set { textField.font = newValue }
    }

    var textColor: NSColor {
        get { textField.textColor ?? .black }
        set { textField.textColor = newValue }
    }

    var text: String {
        get { textField.stringValue }
        set { textField.stringValue = newValue }
    }

    var isEditing: Bool {
        isEditingTitle
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTextField()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextField()
    }

    private func setupTextField() {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingTail
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.delegate = self

        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Inline Editing

    func beginInlineRename(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        guard !isEditingTitle else { return }
        isEditingTitle = true
        editingOriginalTitle = textField.stringValue
        onEditCommit = onCommit
        onEditCancel = onCancel
        textField.isEditable = true
        textField.isSelectable = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.textField)
            if let editor = self.textField.currentEditor() {
                let length = (self.textField.stringValue as NSString).length
                editor.selectedRange = NSRange(location: 0, length: length)
            }
        }
    }

    func cancelInlineRename() {
        guard isEditingTitle else { return }
        textField.stringValue = editingOriginalTitle ?? textField.stringValue
        finishInlineRename(commit: false)
        if window?.firstResponder == textField.currentEditor() {
            window?.makeFirstResponder(nil)
        }
    }

    private func finishInlineRename(commit: Bool) {
        let commitHandler = onEditCommit
        let cancelHandler = onEditCancel
        let finalValue = textField.stringValue
        isEditingTitle = false
        editingOriginalTitle = nil
        onEditCommit = nil
        onEditCancel = nil
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.drawsBackground = false
        if commit {
            commitHandler?(finalValue)
        } else {
            cancelHandler?()
        }
    }
}

// MARK: - NSTextFieldDelegate

extension InlineEditableTextField: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard isEditingTitle else { return }
        let movement = obj.userInfo?["NSTextMovement"] as? Int ?? NSOtherTextMovement
        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if movement == NSReturnTextMovement, !trimmed.isEmpty {
            textField.stringValue = trimmed
            finishInlineRename(commit: true)
        } else {
            textField.stringValue = editingOriginalTitle ?? textField.stringValue
            finishInlineRename(commit: false)
        }
    }
}
