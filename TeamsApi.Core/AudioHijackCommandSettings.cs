namespace TeamsApi.Core;

public sealed record AudioHijackCommandSettings(
    string BundleIdentifier,
    string EnableTranscribeScriptPath,
    string DisableTranscribeScriptPath)
{
    public static AudioHijackCommandSettings FromEnvironment()
    {
        var bundleIdentifier = ReadEnvironmentVariable("audiohijackbundleid")
            ?? "com.rogueamoeba.audiohijack";
        var enableTranscribeScriptPath = ReadEnvironmentVariable("audiohijackenabletranscribescript")
            ?? "AudioHijackCommands/EnableTranscribe.ahcommand";
        var disableTranscribeScriptPath = ReadEnvironmentVariable("audiohijackdisabletranscribescript")
            ?? "AudioHijackCommands/DisableTranscribe.ahcommand";

        return new AudioHijackCommandSettings(
            BundleIdentifier: bundleIdentifier,
            EnableTranscribeScriptPath: enableTranscribeScriptPath,
            DisableTranscribeScriptPath: disableTranscribeScriptPath);
    }

    private static string? ReadEnvironmentVariable(string name)
    {
        return Environment.GetEnvironmentVariable(name)
            ?? Environment.GetEnvironmentVariable(name, EnvironmentVariableTarget.User);
    }

    public string? GetScriptPath(bool isInMeeting)
    {
        var scriptPath = isInMeeting ? EnableTranscribeScriptPath : DisableTranscribeScriptPath;
        if (string.IsNullOrWhiteSpace(scriptPath))
        {
            return null;
        }

        return RepoRootPath.Resolve(scriptPath);
    }
}
