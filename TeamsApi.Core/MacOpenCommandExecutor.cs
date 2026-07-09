using System.Diagnostics;
using Microsoft.Extensions.Logging;

namespace TeamsApi.Core;

internal sealed class MacOpenCommandExecutor : IAppCommandExecutor
{
    private readonly ILogger<MacOpenCommandExecutor>? _logger;

    public MacOpenCommandExecutor(ILogger<MacOpenCommandExecutor>? logger = null)
    {
        _logger = logger;
    }

    public async Task<int> ExecuteAsync(string bundleIdentifier, string scriptPath, CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "/usr/bin/open",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        startInfo.ArgumentList.Add("-b");
        startInfo.ArgumentList.Add(bundleIdentifier);
        startInfo.ArgumentList.Add(scriptPath);

        _logger?.LogInformation(
            "Executing macOS command: open -b {BundleIdentifier} {ScriptPath}",
            bundleIdentifier,
            scriptPath);

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Failed to start the open command.");

        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);

        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);

        var stdout = await outputTask.ConfigureAwait(false);
        var stderr = await errorTask.ConfigureAwait(false);

        if (!string.IsNullOrWhiteSpace(stdout))
        {
            _logger?.LogInformation("Audio Hijack command output: {Output}", stdout.Trim());
        }

        if (!string.IsNullOrWhiteSpace(stderr))
        {
            _logger?.LogWarning("Audio Hijack command error output: {Error}", stderr.Trim());
        }

        return process.ExitCode;
    }
}
