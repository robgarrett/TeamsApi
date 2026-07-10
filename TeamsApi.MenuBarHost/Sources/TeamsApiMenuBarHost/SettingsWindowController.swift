import AppKit
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController {
    var onSave: ((CommandScriptSettings) -> Void)?
    var onResetToDefaults: (() -> Void)?

    private let hostStatusValue = NSTextField(labelWithString: "Stopped")
    private let meetingStatusValue = NSTextField(labelWithString: "Out of meeting")
    private let enablePathField = NSTextField(string: "")
    private let disablePathField = NSTextField(string: "")

    private var currentHostStatus = "Stopped"
    private var currentMeetingStatus = "Out of meeting"

    override init(window: NSWindow? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)
        window.title = "TeamsApi Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = buildContentView()
        updateStatus(hostStatus: currentHostStatus, meetingStatus: currentMeetingStatus)
        apply(settings: CommandScriptSettings.current())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(settings: CommandScriptSettings) {
        enablePathField.stringValue = settings.enableTranscribeScriptPath
        disablePathField.stringValue = settings.disableTranscribeScriptPath
    }

    func updateStatus(hostStatus: String, meetingStatus: String) {
        currentHostStatus = hostStatus
        currentMeetingStatus = meetingStatus
        hostStatusValue.stringValue = hostStatus
        meetingStatusValue.stringValue = meetingStatus
    }

    func showAndActivate() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func savePressed() {
        let currentSettings = CommandScriptSettings.current()
        let settings = CommandScriptSettings(
            bundleIdentifier: currentSettings.bundleIdentifier,
            enableTranscribeScriptPath: enablePathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            disableTranscribeScriptPath: disablePathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave?(settings)
    }

    @objc private func resetPressed() {
        onResetToDefaults?()
        apply(settings: CommandScriptSettings.current())
    }

    @objc private func closePressed() {
        close()
    }

    private func buildContentView() -> NSView {
        let root = NSView()

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14

        let titleLabel = NSTextField(labelWithString: "Command Paths")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: "Edit the Audio Hijack script paths and keep an eye on the live host status.")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.preferredMaxLayoutWidth = 500

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        stack.addArrangedSubview(makeDivider())
        stack.addArrangedSubview(makeStatusSection())
        stack.addArrangedSubview(makeDivider())
        stack.addArrangedSubview(makeScriptRow(title: "Enable script", field: enablePathField, browseAction: #selector(browseEnableScript)))
        stack.addArrangedSubview(makeScriptRow(title: "Disable script", field: disablePathField, browseAction: #selector(browseDisableScript)))
        stack.addArrangedSubview(makeButtonRow())

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18)
        ])

        return root
    }

    private func makeDivider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func makeStatusSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6

        let label = NSTextField(labelWithString: "Status")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor

        section.addArrangedSubview(label)
        section.addArrangedSubview(makeStatusRow(title: "Host", valueField: hostStatusValue))
        section.addArrangedSubview(makeStatusRow(title: "Meeting", valueField: meetingStatusValue))
        return section
    }

    private func makeStatusRow(title: String, valueField: NSTextField) -> NSView {
        return makeLabeledRow(
            title: title,
            trailingView: valueField,
            width: 76
        )
    }

    private func makeScriptRow(title: String, field: NSTextField, browseAction: Selector) -> NSView {
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.isBordered = true
        field.focusRingType = .default
        field.translatesAutoresizingMaskIntoConstraints = false

        let browseButton = NSButton(title: "Browse…", target: self, action: browseAction)
        browseButton.bezelStyle = .rounded

        let fieldAndButton = NSStackView(views: [field, browseButton])
        fieldAndButton.orientation = .horizontal
        fieldAndButton.alignment = .centerY
        fieldAndButton.spacing = 8
        fieldAndButton.distribution = .fill

        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        browseButton.setContentHuggingPriority(.required, for: .horizontal)
        browseButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        return makeLabeledRow(title: title, trailingView: fieldAndButton, width: 112)
    }

    private func makeButtonRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.distribution = .fill

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(title: "Reset Defaults", target: self, action: #selector(resetPressed))
        resetButton.bezelStyle = .rounded

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closePressed))
        closeButton.bezelStyle = .rounded

        let saveButton = NSButton(title: "Save", target: self, action: #selector(savePressed))
        saveButton.bezelStyle = .rounded

        row.addArrangedSubview(spacer)
        row.addArrangedSubview(resetButton)
        row.addArrangedSubview(closeButton)
        row.addArrangedSubview(saveButton)

        return row
    }

    private func makeLabeledRow(title: String, trailingView: NSView, width: CGFloat) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .right
        label.textColor = .labelColor
        label.widthAnchor.constraint(equalToConstant: width).isActive = true

        row.addArrangedSubview(label)
        row.addArrangedSubview(trailingView)
        return row
    }

    @objc private func browseEnableScript() {
        chooseScriptPath(startingAt: enablePathField.stringValue, into: enablePathField)
    }

    @objc private func browseDisableScript() {
        chooseScriptPath(startingAt: disablePathField.stringValue, into: disablePathField)
    }

    private func chooseScriptPath(startingAt path: String, into field: NSTextField) {
        let panel = NSOpenPanel()
        panel.title = "Choose Audio Hijack Command"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [audioHijackCommandType]
        panel.directoryURL = preferredDirectoryURL(for: path)

        if panel.runModal() == .OK, let selectedURL = panel.url {
            field.stringValue = selectedURL.path
        }
    }

    private func preferredDirectoryURL(for path: String) -> URL? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPath.isEmpty {
            let candidateURL = URL(fileURLWithPath: trimmedPath)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL.deletingLastPathComponent()
            }
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }

    private var audioHijackCommandType: UTType {
        if let type = UTType(filenameExtension: "ahcommand") {
            return type
        }

        return .package
    }
}
