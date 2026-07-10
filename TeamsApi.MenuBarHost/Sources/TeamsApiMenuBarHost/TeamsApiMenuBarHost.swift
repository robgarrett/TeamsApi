import AppKit
import Foundation

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
    private var hostStatusText = "Stopped"
    private var meetingStatusText = "Out of meeting"

    override init() {
        super.init()
        launcher.onStatusChanged = { [weak self] statusText in
            DispatchQueue.main.async {
                self?.hostStatusText = statusText
                self?.refreshStatusText()
            }
        }
        launcher.onMeetingStateChanged = { [weak self] isInMeeting in
            DispatchQueue.main.async {
                self?.meetingStatusText = isInMeeting ? "In meeting" : "Out of meeting"
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
        refreshStatusText()
        updateStatusItem(isInMeeting: false)
        launcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        statusMenuItem?.title = "Status: \(hostStatusText) | Meeting: \(meetingStatusText)"
        settingsWindowController.updateStatus(hostStatus: hostStatusText, meetingStatus: meetingStatusText)
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
        settingsWindowController.updateStatus(hostStatus: hostStatusText, meetingStatus: meetingStatusText)
        settingsWindowController.showAndActivate()
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

        let outputParser = OutputParser(onMeetingStateChanged: onMeetingStateChanged)
        process.terminationHandler = { [weak self] process in
            self?.handleTermination(process)
        }

        outputPipe.fileHandleForReading.readabilityHandler = { [weak outputParser] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            FileHandle.standardOutput.write(data)
            outputParser?.ingest(data)
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

private final class OutputParser: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private let onMeetingStateChanged: ((Bool) -> Void)?

    init(onMeetingStateChanged: ((Bool) -> Void)?) {
        self.onMeetingStateChanged = onMeetingStateChanged
    }

    func ingest(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        guard let chunk = String(data: data, encoding: .utf8) else {
            return
        }

        buffer += chunk

        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(...newlineIndex)

            guard line.hasPrefix("MEETING_STATE:") else {
                continue
            }

            let state = line.replacingOccurrences(of: "MEETING_STATE:", with: "")
            onMeetingStateChanged?(state == "in")
        }
    }
}

private struct HostLaunchTarget {
    let executableURL: URL
    let arguments: [String]
    let currentDirectoryURL: URL?
}

private enum HostLocator {
    static func resolveLaunchTarget() -> HostLaunchTarget? {
        if let bundledExecutable = Bundle.module.url(
            forResource: "TeamsApi.Host",
            withExtension: nil,
            subdirectory: "TeamsApiHostRuntime"
        ),
           FileManager.default.isExecutableFile(atPath: bundledExecutable.path) {
            return HostLaunchTarget(
                executableURL: bundledExecutable,
                arguments: [],
                currentDirectoryURL: bundledExecutable.deletingLastPathComponent()
            )
        }

        if let bundledDll = Bundle.main.resourceURL?.appendingPathComponent("TeamsApi.Host.dll"),
           FileManager.default.fileExists(atPath: bundledDll.path) {
            return HostLaunchTarget(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["dotnet", bundledDll.path],
                currentDirectoryURL: bundledDll.deletingLastPathComponent()
            )
        }

        let startDirectories = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            Bundle.main.bundleURL.deletingLastPathComponent()
        ]

        for startDirectory in startDirectories {
            if let repoRoot = findRepoRoot(startingAt: startDirectory) {
                let hostRuntime = repoRoot
                    .appendingPathComponent("TeamsApi.Host")
                    .appendingPathComponent("bin")
                    .appendingPathComponent("Debug")
                    .appendingPathComponent("net10.0")
                    .appendingPathComponent("TeamsApi.Host.dll")

                if FileManager.default.fileExists(atPath: hostRuntime.path) {
                    return HostLaunchTarget(
                        executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                        arguments: ["dotnet", hostRuntime.path],
                        currentDirectoryURL: hostRuntime.deletingLastPathComponent()
                    )
                }
            }
        }

        return nil
    }

    private static func findRepoRoot(startingAt url: URL) -> URL? {
        var current = url

        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("TeamsApi.sln").path) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }

            current = parent
        }
    }
}
