namespace TeamsApi.Core;

public sealed record TeamsConnectionSettings(
    string Host,
    int Port,
    string Token,
    string Manufacturer,
    string Device,
    string App,
    string AppVersion,
    bool AutoReconnect)
{
    public static TeamsConnectionSettings FromEnvironment()
    {
        var host = GetEnvironmentVariable("teamsip") ?? "127.0.0.1";
        var portEnv = int.TryParse(GetEnvironmentVariable("teamsport"), out var parsedPort);
        var port = portEnv ? parsedPort : 8124;
        var token = GetEnvironmentVariable("teamstoken") ?? string.Empty;

        return new TeamsConnectionSettings(
            Host: host,
            Port: port,
            Token: token,
            Manufacturer: "Rob Garrett",
            Device: "Mac",
            App: "Teams Transcribe with Audio Hijack",
            AppVersion: "1.0.0",
            AutoReconnect: true);
    }

    private static string? GetEnvironmentVariable(string variable)
    {
        return Environment.GetEnvironmentVariable(variable)
            ?? Environment.GetEnvironmentVariable(variable, EnvironmentVariableTarget.User);
    }
}
