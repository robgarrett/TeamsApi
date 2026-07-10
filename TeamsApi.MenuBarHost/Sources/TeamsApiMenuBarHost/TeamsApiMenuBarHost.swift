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

    override init() {
        super.init()
        launcher.onMeetingStateChanged = { [weak self] isInMeeting in
            DispatchQueue.main.async {
                self?.updateStatusItem(isInMeeting: isInMeeting)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSLog("TeamsApi menu bar host launched.")
        configureStatusItem()
        updateStatusItem(isInMeeting: false)
        launcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        launcher.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func updateStatusItem(isInMeeting: Bool) {
        guard let button = statusItem?.button else {
            return
        }

        button.image = makeStatusImage(isInMeeting: isInMeeting)
        button.imagePosition = .imageOnly
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

private final class HostProcessLauncher {
    private let processLock = NSLock()
    private var process: Process?
    private var outputPipe: Pipe?
    private var outputParser: OutputParser?
    private let audioHijackCommands = AudioHijackCommandConfig.load()
    var onMeetingStateChanged: ((Bool) -> Void)?

    func start() {
        processLock.lock()
        defer { processLock.unlock() }

        guard process == nil else {
            return
        }

        guard let hostDll = HostLocator.resolveHostDll() else {
            NSLog("TeamsApi host could not be found.")
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["dotnet", hostDll.path]
        process.currentDirectoryURL = hostDll.deletingLastPathComponent()
        process.environment = makeEnvironment()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let outputParser = OutputParser(onMeetingStateChanged: onMeetingStateChanged)
        self.outputParser = outputParser

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            FileHandle.standardOutput.write(data)
            outputParser.ingest(data)
        }

        do {
            try process.run()
            self.process = process
            self.outputPipe = outputPipe
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            NSLog("Failed to start TeamsApi host: \(error.localizedDescription)")
        }
    }

    func stop() {
        processLock.lock()
        let process = process
        let outputPipe = outputPipe
        self.process = nil
        self.outputPipe = nil
        self.outputParser = nil
        processLock.unlock()

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
    }

    private func makeEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        if let enableScriptPath = audioHijackCommands?.enableTranscribeScriptPath,
           !enableScriptPath.isEmpty {
            environment["audiohijackenabletranscribescript"] = enableScriptPath
        } else {
            environment.removeValue(forKey: "audiohijackenabletranscribescript")
        }

        if let disableScriptPath = audioHijackCommands?.disableTranscribeScriptPath,
           !disableScriptPath.isEmpty {
            environment["audiohijackdisabletranscribescript"] = disableScriptPath
        } else {
            environment.removeValue(forKey: "audiohijackdisabletranscribescript")
        }

        return environment
    }
}

private struct AudioHijackCommandConfig: Decodable {
    let enableTranscribeScriptPath: String?
    let disableTranscribeScriptPath: String?

    private enum CodingKeys: String, CodingKey {
        case enableTranscribeScriptPath = "EnableTranscribeScriptPath"
        case disableTranscribeScriptPath = "DisableTranscribeScriptPath"
    }

    static func load() -> AudioHijackCommandConfig? {
        guard let url = Bundle.module.url(forResource: "AudioHijackCommands", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? PropertyListDecoder().decode(AudioHijackCommandConfig.self, from: data)
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

private enum HostLocator {
    static func resolveHostDll() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("TeamsApi.Host.dll"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        let startDirectories = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            Bundle.main.bundleURL.deletingLastPathComponent()
        ]

        for startDirectory in startDirectories {
            if let repoRoot = findRepoRoot(startingAt: startDirectory) {
                let hostDll = repoRoot
                    .appendingPathComponent("TeamsApi.Host")
                    .appendingPathComponent("bin")
                    .appendingPathComponent("Debug")
                    .appendingPathComponent("net10.0")
                    .appendingPathComponent("TeamsApi.Host.dll")

                if FileManager.default.fileExists(atPath: hostDll.path) {
                    return hostDll
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
