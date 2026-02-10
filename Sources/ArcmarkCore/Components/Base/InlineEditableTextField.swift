import AppKit

/// A text field wrapper that provides inline editing behavior with commit/cancel functionality.
///
/// `InlineEditableTextField` encapsulates the complex logic for inline text editing, including:
/// - Entering edit mode with text selection
/// - Committing changes on Enter key
/// - Canceling changes on Escape or focus loss
/// - Automatic whitespace trimming
///
/// ## Features
/// - Seamless transition between display and edit modes
/// - Callback-based API for commit and cancel events
/// - Automatic text selection when editing begins
/// - Whitespace trimming on commit
/// - Focus management
///
/// ## Usage
/// ```swift
/// let editableField = InlineEditableTextField()
/// editableField.text = "Initial Title"
/// editableField.font = ThemeConstants.Fonts.bodyRegular
/// editableField.textColor = .white
///
/// // Begin editing
/// editableField.beginInlineRename(
///     onCommit: { newText in
///         // Handle the committed text
///         print("User committed: \(newText)")
///     },
///     onCancel: {
///         // Handle cancellation
///         print("User canceled editing")
///     }
/// )
/// ```
///
/// ## Behavior
/// - **Enter key**: Commits the edit if text is non-empty (after trimming)
/// - **Escape key**: Cancels the edit and restores original text
/// - **Focus loss**: Cancels the edit and restores original text
/// - **Empty text**: Treated as cancellation
///
/// - SeeAlso: `NodeRowView`, `WorkspaceRowView` for usage examples
@MainActor
final class InlineEditableTextField: NSView {

    // MARK: - Properties

    /// The underlying text field that displays and edits the text.
    let textField = NSTextField(string: "")

    /// Indicates whether the text field is currently in edit mode.
    private var isEditingTitle = false

    /// The original text value before editing began, used for cancellation.
    private var editingOriginalTitle: String?

    /// Callback invoked when the edit is committed with the new text.
    private var onEditCommit: ((String) -> Void)?

    /// Callback invoked when the edit is canceled.
    private var onEditCancel: (() -> Void)?

    // MARK: - Configuration

    /// The font used for the text field.
    var font: NSFont {
        get { textField.font ?? ThemeConstants.Fonts.bodyRegular }
        set { textField.font = newValue }
    }

    /// The text color used for the text field.
    var textColor: NSColor {
        get { textField.textColor ?? .black }
        set { textField.textColor = newValue }
    }

    /// The current text value displayed in the text field.
    var text: String {
        get { textField.stringValue }
        set { textField.stringValue = newValue }
    }

    /// Indicates whether the text field is currently in edit mode.
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

    /// Begins inline editing mode.
    ///
    /// When called, this method:
    /// 1. Stores the current text value for potential cancellation
    /// 2. Makes the text field editable and selectable
    /// 3. Gives the text field first responder status
    /// 4. Selects all text for easy replacement
    ///
    /// - Parameters:
    ///   - onCommit: Callback invoked when the edit is committed (Enter key pressed with non-empty text)
    ///   - onCancel: Callback invoked when the edit is canceled (Escape key, focus loss, or empty text)
    ///
    /// - Note: If already in edit mode, this method does nothing (guard clause).
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

    /// Cancels inline editing and restores the original text.
    ///
    /// This method:
    /// 1. Restores the text to its original value before editing
    /// 2. Exits edit mode
    /// 3. Removes first responder status from the text field
    ///
    /// - Note: If not in edit mode, this method does nothing (guard clause).
    func cancelInlineRename() {
        guard isEditingTitle else { return }
        textField.stringValue = editingOriginalTitle ?? textField.stringValue
        finishInlineRename(commit: false)
        if window?.firstResponder == textField.currentEditor() {
            window?.makeFirstResponder(nil)
        }
    }

    /// Finishes inline editing and invokes the appropriate callback.
    ///
    /// This private method handles the cleanup after editing completes:
    /// - Captures the callbacks before clearing state
    /// - Resets all editing state variables
    /// - Makes the text field non-editable
    /// - Invokes either the commit or cancel callback
    ///
    /// - Parameter commit: If true, invokes the commit callback; otherwise invokes the cancel callback.
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
    /// Handles the end of text editing in the text field.
    ///
    /// This delegate method is called when editing ends (Enter key, Escape key, or focus loss).
    /// It determines whether to commit or cancel based on:
    /// - The type of text movement (Enter vs Escape)
    /// - Whether the trimmed text is non-empty
    ///
    /// - Parameter obj: The notification containing information about how editing ended.
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
