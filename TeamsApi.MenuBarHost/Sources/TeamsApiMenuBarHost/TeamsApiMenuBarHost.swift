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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSLog("TeamsApi menu bar host launched.")
        configureStatusItem()
        launcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        launcher.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "Transcribe")
            button.image = image?.withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func quitApp() {
        launcher.stop()
        NSApp.terminate(nil)
    }
}

private final class HostProcessLauncher {
    private let processLock = NSLock()
    private var process: Process?

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
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["dotnet", hostDll.path]
        process.currentDirectoryURL = hostDll.deletingLastPathComponent()
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("Failed to start TeamsApi host: \(error.localizedDescription)")
        }
    }

    func stop() {
        processLock.lock()
        let process = process
        self.process = nil
        processLock.unlock()

        process?.terminate()
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
