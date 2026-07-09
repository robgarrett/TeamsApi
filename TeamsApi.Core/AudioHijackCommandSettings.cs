namespace TeamsApi.Core;

public sealed record AudioHijackCommandSettings(
    string BundleIdentifier,
    string EnableTranscribeScriptPath,
    string DisableTranscribeScriptPath)
{
    public static AudioHijackCommandSettings FromEnvironment()
    {
        var bundleIdentifier = Environment.GetEnvironmentVariable("audiohijackbundleid", EnvironmentVariableTarget.User)
            ?? "com.rogueamoeba.audiohijack";
        var enableTranscribeScriptPath = Environment.GetEnvironmentVariable("audiohijackenabletranscribescript", EnvironmentVariableTarget.User)
            ?? "AudioHijackCommands/EnableTranscribe.ahcommand";
        var disableTranscribeScriptPath = Environment.GetEnvironmentVariable("audiohijackdisabletranscribescript", EnvironmentVariableTarget.User)
            ?? "AudioHijackCommands/DisableTranscribe.ahcommand";

        return new AudioHijackCommandSettings(
            BundleIdentifier: bundleIdentifier,
            EnableTranscribeScriptPath: enableTranscribeScriptPath,
            DisableTranscribeScriptPath: disableTranscribeScriptPath);
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
