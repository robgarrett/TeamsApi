import Foundation

struct CommandScriptSettings: Equatable {
    let bundleIdentifier: String
    let enableTranscribeScriptPath: String
    let disableTranscribeScriptPath: String

    static let defaultBundleIdentifier = "com.rogueamoeba.audiohijack"
    static let defaultEnableTranscribeScriptPath = "AudioHijackCommands/EnableTranscribe.ahcommand"
    static let defaultDisableTranscribeScriptPath = "AudioHijackCommands/DisableTranscribe.ahcommand"

    static func current() -> CommandScriptSettings {
        let defaults = UserDefaults.standard
        let resourceSettings = Bundle.resourceSettings()

        let enableScriptPath = defaults.string(forKey: CommandScriptSettingKeys.enableScriptPathOverride)
            ?? resourceSettings?.enableTranscribeScriptPath
            ?? defaultEnableTranscribeScriptPath

        let disableScriptPath = defaults.string(forKey: CommandScriptSettingKeys.disableScriptPathOverride)
            ?? resourceSettings?.disableTranscribeScriptPath
            ?? defaultDisableTranscribeScriptPath

        let bundleIdentifier = defaults.string(forKey: CommandScriptSettingKeys.bundleIdentifierOverride)
            ?? resourceSettings?.bundleIdentifier
            ?? defaultBundleIdentifier

        return CommandScriptSettings(
            bundleIdentifier: bundleIdentifier,
            enableTranscribeScriptPath: enableScriptPath,
            disableTranscribeScriptPath: disableScriptPath
        )
    }
}

@MainActor
final class CommandScriptSettingsStore {
    static let shared = CommandScriptSettingsStore()

    func save(enableTranscribeScriptPath: String, disableTranscribeScriptPath: String) {
        let defaults = UserDefaults.standard
        defaults.set(enableTranscribeScriptPath, forKey: CommandScriptSettingKeys.enableScriptPathOverride)
        defaults.set(disableTranscribeScriptPath, forKey: CommandScriptSettingKeys.disableScriptPathOverride)
    }

    func clearOverrides() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: CommandScriptSettingKeys.enableScriptPathOverride)
        defaults.removeObject(forKey: CommandScriptSettingKeys.disableScriptPathOverride)
        defaults.removeObject(forKey: CommandScriptSettingKeys.bundleIdentifierOverride)
    }
}

private enum CommandScriptSettingKeys {
    static let enableScriptPathOverride = "TeamsApiEnableTranscribeScriptPathOverride"
    static let disableScriptPathOverride = "TeamsApiDisableTranscribeScriptPathOverride"
    static let bundleIdentifierOverride = "TeamsApiAudioHijackBundleIdentifierOverride"
}

private struct CommandScriptSettingsResource: Decodable {
    let bundleIdentifier: String?
    let enableTranscribeScriptPath: String?
    let disableTranscribeScriptPath: String?

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "BundleIdentifier"
        case enableTranscribeScriptPath = "EnableTranscribeScriptPath"
        case disableTranscribeScriptPath = "DisableTranscribeScriptPath"
    }
}

private extension Bundle {
    static func resourceSettings() -> CommandScriptSettingsResource? {
        guard let url = Bundle.module.url(forResource: "AudioHijackCommands", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? PropertyListDecoder().decode(CommandScriptSettingsResource.self, from: data)
    }
}
