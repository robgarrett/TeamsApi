using Microsoft.Extensions.Logging;
using System.Threading.Channels;
using System.Reactive.Linq;

namespace TeamsApi.Core;

public interface IAppRunner
{
    Task<int> RunAsync(CancellationToken cancellationToken);
}

public sealed record AppEvent(string Kind, string Message, DateTimeOffset OccurredAt);

public interface IAppEventPublisher
{
    ValueTask PublishAsync(AppEvent appEvent, CancellationToken cancellationToken = default);
}

public sealed class AppRunner : IAppRunner, IAppEventPublisher
{
    private readonly ILogger<AppRunner> _logger;
    private readonly ITeamsClientFactory _teamsClientFactory;
    private readonly TeamsConnectionSettings _teamsConnectionSettings;
    private readonly AudioHijackCommandSettings _commandSettings;
    private readonly IAppCommandExecutor _commandExecutor;
    private readonly Channel<AppEvent> _eventChannel = Channel.CreateUnbounded<AppEvent>(
        new UnboundedChannelOptions
        {
            SingleReader = true,
            SingleWriter = false
        });

    public AppRunner(
        ILogger<AppRunner> logger,
        ITeamsClientFactory? teamsClientFactory = null,
        TeamsConnectionSettings? teamsConnectionSettings = null,
        AudioHijackCommandSettings? commandSettings = null,
        IAppCommandExecutor? commandExecutor = null)
    {
        _logger = logger;
        _teamsClientFactory = teamsClientFactory ?? new DefaultTeamsClientFactory();
        _teamsConnectionSettings = teamsConnectionSettings ?? TeamsConnectionSettings.FromEnvironment();
        _commandSettings = commandSettings ?? AudioHijackCommandSettings.FromEnvironment();
        _commandExecutor = commandExecutor ?? new MacOpenCommandExecutor();
    }

    public async Task<int> RunAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("App runner starting.");

        using var teamsClient = _teamsClientFactory.Create(_teamsConnectionSettings, cancellationToken);
        using var teamsBootstrapSubscription = teamsClient.CanToggleMuteChanged
            .Skip(1)
            .Select(canToggleMute => Observable.FromAsync(ct => TryBootstrapTeamsApiAsync(teamsClient, canToggleMute, ct)))
            .Concat()
            .Subscribe();
        using var teamsMeetingSubscription = teamsClient.IsInMeetingChanged
            .Skip(1)
            .Select(isInMeeting => Observable.FromAsync(ct => HandleMeetingStateChangedAsync(isInMeeting, ct)))
            .Concat()
            .Subscribe();

        try
        {
            _logger.LogInformation(
                "Connecting to Teams at {Host}:{Port}.",
                _teamsConnectionSettings.Host,
                _teamsConnectionSettings.Port);

            await teamsClient.Connect(cancellationToken).ConfigureAwait(false);
            _logger.LogInformation("Connected to Teams.");

            while (await _eventChannel.Reader.WaitToReadAsync(cancellationToken).ConfigureAwait(false))
            {
                while (_eventChannel.Reader.TryRead(out var appEvent))
                {
                    HandleEvent(appEvent);
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            _logger.LogInformation("App runner stopping.");
        }

        _logger.LogInformation("App runner finished.");
        return 0;
    }

    public ValueTask PublishAsync(AppEvent appEvent, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(appEvent);

        return _eventChannel.Writer.WriteAsync(appEvent, cancellationToken);
    }

    private async Task TryBootstrapTeamsApiAsync(ITeamsClient teamsClient, bool canToggleMute, CancellationToken cancellationToken)
    {
        if (_teamsApiActivated || _teamsApiActivationAttempted)
        {
            return;
        }

        if (!canToggleMute)
        {
            return;
        }

        _teamsApiActivationAttempted = true;

        try
        {
            _logger.LogInformation("Bootstrapping Teams API by toggling mute once so Teams registers the plugin.");
            await teamsClient.ToggleMute().ConfigureAwait(false);

            _teamsApiActivated = true;
            _logger.LogInformation("Teams API bootstrap command completed.");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            _logger.LogInformation("Teams API bootstrap was cancelled.");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Teams API bootstrap failed.");
        }
    }

    private async Task HandleMeetingStateChangedAsync(bool isInMeeting, CancellationToken cancellationToken)
    {
        await PublishAsync(
            new AppEvent(
                Kind: isInMeeting ? "meeting.started" : "meeting.stopped",
                Message: isInMeeting ? "Teams meeting started." : "Teams meeting stopped.",
                OccurredAt: DateTimeOffset.UtcNow),
            cancellationToken).ConfigureAwait(false);

        Console.WriteLine($"MEETING_STATE:{(isInMeeting ? "in" : "out")}");

        var scriptPath = _commandSettings.GetScriptPath(isInMeeting);
        if (scriptPath is null)
        {
            return;
        }

        try
        {
            _logger.LogInformation("Running Audio Hijack script for {State}: {ScriptPath}", isInMeeting ? "meeting start" : "meeting stop", scriptPath);
            var exitCode = await _commandExecutor.ExecuteAsync(_commandSettings.BundleIdentifier, scriptPath, cancellationToken).ConfigureAwait(false);

            if (exitCode == 0)
            {
                _logger.LogInformation("Audio Hijack command completed successfully.");
            }
            else
            {
                _logger.LogWarning("Audio Hijack command exited with code {ExitCode}.", exitCode);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            _logger.LogInformation("Audio Hijack command was cancelled.");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Audio Hijack command failed.");
        }
    }

    private void HandleEvent(AppEvent appEvent)
    {
        _logger.LogInformation(
            "Received {Kind} event at {OccurredAt:u}: {Message}",
            appEvent.Kind,
            appEvent.OccurredAt,
            appEvent.Message);
    }

    private bool _teamsApiActivationAttempted;
    private bool _teamsApiActivated;
}
