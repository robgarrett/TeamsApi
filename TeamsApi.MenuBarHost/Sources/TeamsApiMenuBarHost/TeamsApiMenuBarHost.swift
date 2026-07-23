import AppKit
import Foundation
import Security

@main
enum TeamsApiMenuBarHostMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = TeamsApiMenuBarHostApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class TeamsApiMenuBarHostApp: NSObject, NSApplicationDelegate {
    private let launcher = HostProcessLauncher()
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private let settingsWindowController = SettingsWindowController()
    private var launcherStatusText = "Stopped"
    private var sessionStatusText = "Disabled"
    private var audioHijackAppStatusText = "Not running"
    private var meetingStatusText = "Out of meeting"
    private var audioHijackStatusTimer: Timer?

    override init() {
        super.init()
        launcher.onStatusChanged = { [weak self] statusText in
            DispatchQueue.main.async {
                self?.launcherStatusText = statusText
                self?.refreshStatusText()
            }
        }
        launcher.onMeetingStateChanged = { [weak self] isInMeeting in
            DispatchQueue.main.async {
                self?.meetingStatusText = isInMeeting ? "In meeting" : "Out of meeting"
                self?.sessionStatusText = isInMeeting ? "Enabled" : "Disabled"
                self?.updateStatusItem(isInMeeting: isInMeeting)
                self?.refreshStatusText()
            }
        }

        settingsWindowController.onSave = { [weak self] settings in
            CommandScriptSettingsStore.shared.save(
                enableTranscribeScriptPath: settings.enableTranscribeScriptPath,
                disableTranscribeScriptPath: settings.disableTranscribeScriptPath
            )
            self?.settingsWindowController.apply(settings: CommandScriptSettings.current())
            self?.launcher.restart()
            self?.refreshStatusText()
        }

        settingsWindowController.onResetToDefaults = { [weak self] in
            CommandScriptSettingsStore.shared.clearOverrides()
            self?.settingsWindowController.apply(settings: CommandScriptSettings.current())
            self?.launcher.restart()
            self?.refreshStatusText()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSLog("TeamsApi menu bar host launched.")
        configureStatusItem()
        startAudioHijackStatusTimer()
        refreshStatusText()
        updateStatusItem(isInMeeting: false)
        launcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioHijackStatusTimer?.invalidate()
        audioHijackStatusTimer = nil
        launcher.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        let statusMenuItem = NSMenuItem(title: "Status: Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        self.statusMenuItem = statusMenuItem
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    private func refreshStatusText() {
        refreshAudioHijackAppStatus()
        statusMenuItem?.title = "Status: \(sessionStatusText) | Audio Hijack: \(audioHijackAppStatusText)"
        settingsWindowController.updateStatus(
            launcherStatus: launcherStatusText,
            sessionStatus: sessionStatusText,
            audioHijackAppStatus: audioHijackAppStatusText,
            meetingStatus: meetingStatusText
        )
    }

    private func updateStatusItem(isInMeeting: Bool) {
        guard let button = statusItem?.button else {
            return
        }

        button.image = makeStatusImage(isInMeeting: isInMeeting)
        button.imagePosition = .imageOnly
    }

    @objc private func openSettings() {
        settingsWindowController.apply(settings: CommandScriptSettings.current())
        refreshStatusText()
        settingsWindowController.showAndActivate()
    }

    private func startAudioHijackStatusTimer() {
        audioHijackStatusTimer?.invalidate()
        audioHijackStatusTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshStatusText()
            }
        }
    }

    private func refreshAudioHijackAppStatus() {
        let bundleIdentifier = CommandScriptSettings.current().bundleIdentifier
        let isRunning = NSWorkspace.shared.runningApplications.contains { runningApp in
            runningApp.bundleIdentifier == bundleIdentifier
        }

        audioHijackAppStatusText = isRunning ? "Running" : "Not running"
    }

    private func makeStatusImage(isInMeeting: Bool) -> NSImage {
        let size = NSSize(width: 37, height: 24)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        let backgroundPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        let backgroundColor = isInMeeting ? NSColor.systemGreen : NSColor.systemRed
        backgroundColor.setFill()
        backgroundPath.fill()

        NSColor(calibratedWhite: 1.0, alpha: 0.2).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

        if let symbol = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "Transcribe")?
            .withSymbolConfiguration(symbolConfiguration) {
            symbol.draw(in: rect.insetBy(dx: 7.0, dy: 4.0))
        }

        image.isTemplate = false
        return image
    }

    @objc private func quitApp() {
        launcher.stop()
        NSApp.terminate(nil)
    }
}

private final class HostProcessLauncher: @unchecked Sendable {
    private let processLock = NSLock()
    private var process: Process?
    private var outputPipe: Pipe?
    private var outputParser: OutputParser?
    private var restartWorkItem: DispatchWorkItem?
    private var retryDelay: TimeInterval = 2
    private var shouldAutoRestart = true
    private var isStopping = false
    var onStatusChanged: ((String) -> Void)?
    var onMeetingStateChanged: ((Bool) -> Void)?

    func start() {
        processLock.lock()
        guard process == nil else {
            processLock.unlock()
            return
        }

        shouldAutoRestart = true
        isStopping = false
        restartWorkItem?.cancel()
        restartWorkItem = nil
        processLock.unlock()

        notifyStatus("Starting")

        guard let launchTarget = HostLocator.resolveLaunchTarget() else {
            notifyStatus("Host not found")
            scheduleRestartIfNeeded(reason: "TeamsApi host could not be found.")
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = launchTarget.executableURL
        process.arguments = launchTarget.arguments
        process.currentDirectoryURL = launchTarget.currentDirectoryURL
        process.environment = makeEnvironment()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let outputParser = OutputParser(
            onMeetingStateChanged: onMeetingStateChanged,
            onTokenChanged: { token in
                TeamsTokenKeychainStore.shared.save(token)
            }
        )
        process.terminationHandler = { [weak self] process in
            self?.handleTermination(process)
        }

        outputPipe.fileHandleForReading.readabilityHandler = { [weak outputParser] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            if let safeOutput = outputParser?.ingest(data), !safeOutput.isEmpty {
                FileHandle.standardOutput.write(safeOutput)
            }
        }

        do {
            try process.run()
            processLock.lock()
            self.process = process
            self.outputPipe = outputPipe
            self.outputParser = outputParser
            retryDelay = 2
            processLock.unlock()
            notifyStatus("Running")
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            notifyStatus("Host launch failed")
            scheduleRestartIfNeeded(reason: "Failed to start TeamsApi host: \(error.localizedDescription)")
        }
    }

    func restart() {
        stop()

        processLock.lock()
        shouldAutoRestart = true
        processLock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }

    func stop() {
        processLock.lock()
        isStopping = true
        shouldAutoRestart = false
        restartWorkItem?.cancel()
        restartWorkItem = nil
        let process = process
        let outputPipe = outputPipe
        self.process = nil
        self.outputPipe = nil
        self.outputParser = nil
        processLock.unlock()

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        notifyStatus("Stopped")
    }

    private func makeEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let commandSettings = CommandScriptSettings.current()

        environment["audiohijackbundleid"] = commandSettings.bundleIdentifier
        environment["audiohijackenabletranscribescript"] = commandSettings.enableTranscribeScriptPath
        environment["audiohijackdisabletranscribescript"] = commandSettings.disableTranscribeScriptPath
        if let teamsToken = TeamsTokenKeychainStore.shared.load() {
            environment["teamstoken"] = teamsToken
        }

        return environment
    }
    
    private func handleTermination(_ process: Process) {
        processLock.lock()
        let shouldRestart = shouldAutoRestart && !isStopping
        self.process = nil
        self.outputPipe = nil
        self.outputParser = nil
        processLock.unlock()

        if shouldRestart {
            scheduleRestartIfNeeded(reason: "TeamsApi host exited unexpectedly.")
        } else {
            notifyStatus("Stopped")
        }
    }

    private func scheduleRestartIfNeeded(reason: String) {
        processLock.lock()
        let shouldRestart = shouldAutoRestart && !isStopping && restartWorkItem == nil
        let currentDelay = retryDelay
        if shouldRestart {
            retryDelay = min(retryDelay * 2, 30)
            let workItem = DispatchWorkItem { [weak self] in
                self?.processLock.lock()
                self?.restartWorkItem = nil
                self?.processLock.unlock()
                self?.start()
            }
            restartWorkItem = workItem
            processLock.unlock()

            notifyStatus("Retrying in \(Int(currentDelay))s")
            NSLog("%@", reason)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + currentDelay, execute: workItem)
            return
        }
        processLock.unlock()
        NSLog("%@", reason)
    }

    private func notifyStatus(_ status: String) {
        onStatusChanged?(status)
    }
}

final class OutputParser: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private let onMeetingStateChanged: ((Bool) -> Void)?
    private let onTokenChanged: ((String) -> Void)?

    init(
        onMeetingStateChanged: ((Bool) -> Void)?,
        onTokenChanged: ((String) -> Void)? = nil
    ) {
        self.onMeetingStateChanged = onMeetingStateChanged
        self.onTokenChanged = onTokenChanged
    }

    func ingest(_ data: Data) -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard let chunk = String(data: data, encoding: .utf8) else {
            return Data()
        }

        buffer += chunk
        var safeLines: [String] = []

        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(...newlineIndex)

            if let token = decodeToken(from: line) {
                onTokenChanged?(token)
                continue
            }

            if line.hasPrefix("MEETING_STATE:") {
                let state = line.replacingOccurrences(of: "MEETING_STATE:", with: "")
                onMeetingStateChanged?(state == "in")
            }

            safeLines.append(line)
        }

        guard !safeLines.isEmpty else {
            return Data()
        }

        return Data((safeLines.joined(separator: "\n") + "\n").utf8)
    }

    private func decodeToken(from line: String) -> String? {
        let prefix = "TEAMS_TOKEN:"
        guard line.hasPrefix(prefix),
              let tokenData = Data(base64Encoded: String(line.dropFirst(prefix.count))),
              let token = String(data: tokenData, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }

        return token
    }
}

private final class TeamsTokenKeychainStore: @unchecked Sendable {
    static let shared = TeamsTokenKeychainStore()

    private let service = "com.robgarrett.TeamsApiMenuBarHost"
    private let account = "teams-pairing-token"

    func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            return nil
        }
        guard status == errSecSuccess,
              let tokenData = result as? Data,
              let token = String(data: tokenData, encoding: .utf8) else {
            NSLog("Unable to load the Teams pairing token from Keychain: %d", status)
            return nil
        }

        return token
    }

    func save(_ token: String) {
        let attributes = [kSecValueData as String: Data(token.utf8)]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            NSLog("Unable to update the Teams pairing token in Keychain: %d", updateStatus)
            return
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = Data(token.utf8)
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            NSLog("Unable to save the Teams pairing token in Keychain: %d", addStatus)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct HostLaunchTarget {
    let executableURL: URL
    let arguments: [String]
    let currentDirectoryURL: URL?
}

private enum HostLocator {
    static func resolveLaunchTarget() -> HostLaunchTarget? {
        if let bundledExecutable = bundledResourceURL(
            forResource: "TeamsApi.Host",
            withExtension: nil
        ),
           FileManager.default.isExecutableFile(atPath: bundledExecutable.path) {
            return HostLaunchTarget(
                executableURL: bundledExecutable,
                arguments: [],
                currentDirectoryURL: bundledExecutable.deletingLastPathComponent()
            )
        }

        if let bundledDll = bundledResourceURL(forResource: "TeamsApi.Host", withExtension: "dll"),
           FileManager.default.fileExists(atPath: bundledDll.path) {
            return HostLaunchTarget(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["dotnet", bundledDll.path],
                currentDirectoryURL: bundledDll.deletingLastPathComponent()
            )
        }

        return nil
    }

    private static func bundledResourceURL(forResource resource: String, withExtension fileExtension: String?) -> URL? {
        let candidateBundles = [
            Bundle.module.resourceURL,
            Bundle.main.resourceURL
        ].compactMap { $0 }

        for bundleURL in candidateBundles {
            let directURL = bundleURL.appendingPathComponent(resource).appendingPathExtensionIfNeeded(fileExtension)
            if FileManager.default.fileExists(atPath: directURL.path) {
                return directURL
            }

            let runtimeURL = bundleURL
                .appendingPathComponent("TeamsApiHostRuntime")
                .appendingPathComponent(resource)
                .appendingPathExtensionIfNeeded(fileExtension)
            if FileManager.default.fileExists(atPath: runtimeURL.path) {
                return runtimeURL
            }
        }

        return nil
    }
}

private extension URL {
    func appendingPathExtensionIfNeeded(_ fileExtension: String?) -> URL {
        guard let fileExtension, !fileExtension.isEmpty else {
            return self
        }

        return appendingPathExtension(fileExtension)
    }
}
