using Microsoft.Extensions.Logging.Abstractions;
using System.Reactive.Subjects;
using System.Collections.Concurrent;
using TeamsApi.Core;

namespace TeamsApi.Tests;

public class AppRunnerTests
{
    [Fact]
    public void AudioHijackCommandSettings_FromEnvironment_UsesProcessOverrides()
    {
        const string enableKey = "audiohijackenabletranscribescript";
        const string disableKey = "audiohijackdisabletranscribescript";
        const string bundleKey = "audiohijackbundleid";

        var originalEnable = Environment.GetEnvironmentVariable(enableKey);
        var originalDisable = Environment.GetEnvironmentVariable(disableKey);
        var originalBundle = Environment.GetEnvironmentVariable(bundleKey);

        try
        {
            Environment.SetEnvironmentVariable(enableKey, "Custom/Enable.ahcommand");
            Environment.SetEnvironmentVariable(disableKey, "Custom/Disable.ahcommand");
            Environment.SetEnvironmentVariable(bundleKey, "com.example.custom");

            var settings = AudioHijackCommandSettings.FromEnvironment();

            Assert.Equal("com.example.custom", settings.BundleIdentifier);
            Assert.Equal("Custom/Enable.ahcommand", settings.EnableTranscribeScriptPath);
            Assert.Equal("Custom/Disable.ahcommand", settings.DisableTranscribeScriptPath);
        }
        finally
        {
            Environment.SetEnvironmentVariable(enableKey, originalEnable);
            Environment.SetEnvironmentVariable(disableKey, originalDisable);
            Environment.SetEnvironmentVariable(bundleKey, originalBundle);
        }
    }

    [Fact]
    public async Task RunAsync_ExecutesConfiguredCommands_ForMeetingStartAndStop()
    {
        var meetingState = new BehaviorSubject<bool>(false);
        var canToggleMute = new BehaviorSubject<bool>(false);
        var fakeClient = new FakeTeamsClient(meetingState, canToggleMute);
        var factory = new FakeTeamsClientFactory(fakeClient);
        var commandExecutor = new RecordingCommandExecutor();
        var runner = new AppRunner(
            NullLogger<AppRunner>.Instance,
            factory,
            new TeamsConnectionSettings("127.0.0.1", 8124, string.Empty, "manufacturer", "device", "app", "1.0", true),
            new AudioHijackCommandSettings(
                "com.rogueamoeba.audiohijack",
                "AudioHijackCommands/EnableTranscribe.ahcommand",
                "AudioHijackCommands/DisableTranscribe.ahcommand"),
            commandExecutor);

        using var cancellationSource = new CancellationTokenSource(TimeSpan.FromSeconds(2));

        var runTask = runner.RunAsync(cancellationSource.Token);

        canToggleMute.OnNext(true);
        await fakeClient.ToggleMuteCalled.Task.WaitAsync(TimeSpan.FromSeconds(1));
        meetingState.OnNext(true);
        await commandExecutor.WaitForCallCountAsync(1, TimeSpan.FromSeconds(1));
        meetingState.OnNext(false);
        await commandExecutor.WaitForCallCountAsync(2, TimeSpan.FromSeconds(1));

        cancellationSource.Cancel();
        var result = await runTask;

        Assert.Equal(0, result);
        Assert.True(fakeClient.ConnectCalled);
        Assert.Equal(1, fakeClient.ToggleMuteCallCount);
        Assert.Equal(
            [
                ("com.rogueamoeba.audiohijack", RepoRootPath.Resolve("AudioHijackCommands/EnableTranscribe.ahcommand")),
                ("com.rogueamoeba.audiohijack", RepoRootPath.Resolve("AudioHijackCommands/DisableTranscribe.ahcommand"))
            ],
            commandExecutor.Calls.ToArray());
    }

    [Fact]
    public async Task RunAsync_UsesStoredToken_AndPersistsTokenChanges()
    {
        var tokenChanged = new Subject<string>();
        var fakeClient = new FakeTeamsClient(
            new BehaviorSubject<bool>(false),
            new BehaviorSubject<bool>(false),
            tokenChanged);
        var factory = new FakeTeamsClientFactory(fakeClient);
        var tokenStore = new RecordingTokenStore("saved-token");
        var runner = new AppRunner(
            NullLogger<AppRunner>.Instance,
            factory,
            new TeamsConnectionSettings("127.0.0.1", 8124, "environment-token", "manufacturer", "device", "app", "1.0", true),
            commandExecutor: new RecordingCommandExecutor(),
            teamsTokenStore: tokenStore);

        using var cancellationSource = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        var runTask = runner.RunAsync(cancellationSource.Token);

        await factory.CreateCalled.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Assert.Equal("saved-token", factory.LastSettings!.Token);

        tokenChanged.OnNext("refreshed-token");
        await tokenStore.TokenSaved.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Assert.Equal("refreshed-token", tokenStore.SavedToken);

        cancellationSource.Cancel();
        Assert.Equal(0, await runTask);
    }

    private sealed class FakeTeamsClientFactory : ITeamsClientFactory
    {
        private readonly ITeamsClient _client;

        public TaskCompletionSource CreateCalled { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TeamsConnectionSettings? LastSettings { get; private set; }

        public FakeTeamsClientFactory(ITeamsClient client)
        {
            _client = client;
        }

        public ITeamsClient Create(TeamsConnectionSettings settings, CancellationToken cancellationToken)
        {
            LastSettings = settings;
            CreateCalled.TrySetResult();
            return _client;
        }
    }

    private sealed class FakeTeamsClient : ITeamsClient
    {
        private readonly IObservable<bool> _isInMeetingChanged;
        private readonly IObservable<bool> _canToggleMuteChanged;
        private readonly IObservable<string> _tokenChanged;

        public FakeTeamsClient(
            IObservable<bool> isInMeetingChanged,
            IObservable<bool> canToggleMuteChanged,
            IObservable<string>? tokenChanged = null)
        {
            _isInMeetingChanged = isInMeetingChanged;
            _canToggleMuteChanged = canToggleMuteChanged;
            _tokenChanged = tokenChanged ?? new Subject<string>();
        }

        public bool ConnectCalled { get; private set; }
        public int ToggleMuteCallCount { get; private set; }
        public TaskCompletionSource ToggleMuteCalled { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public IObservable<bool> IsInMeetingChanged => _isInMeetingChanged;
        public IObservable<bool> CanToggleMuteChanged => _canToggleMuteChanged;
        public IObservable<string> TokenChanged => _tokenChanged;
        public bool CanToggleMute => true;

        public Task Connect(CancellationToken cancellationToken = default)
        {
            ConnectCalled = true;
            return Task.CompletedTask;
        }

        public Task ToggleMute()
        {
            ToggleMuteCallCount++;
            ToggleMuteCalled.TrySetResult();
            return Task.CompletedTask;
        }

        public void Dispose()
        {
        }
    }

    private sealed class RecordingTokenStore : ITeamsTokenStore
    {
        private readonly string? _storedToken;

        public RecordingTokenStore(string? storedToken)
        {
            _storedToken = storedToken;
        }

        public string? SavedToken { get; private set; }
        public TaskCompletionSource TokenSaved { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public Task<string?> GetTokenAsync(CancellationToken cancellationToken = default)
        {
            return Task.FromResult(_storedToken);
        }

        public Task SaveTokenAsync(string token, CancellationToken cancellationToken = default)
        {
            SavedToken = token;
            TokenSaved.TrySetResult();
            return Task.CompletedTask;
        }
    }

    private sealed class RecordingCommandExecutor : IAppCommandExecutor
    {
        private readonly ConcurrentQueue<(string BundleIdentifier, string ScriptPath)> _calls = new();
        private readonly SemaphoreSlim _signal = new(0);

        public IReadOnlyCollection<(string BundleIdentifier, string ScriptPath)> Calls => _calls.ToArray();

        public Task<int> ExecuteAsync(string bundleIdentifier, string scriptPath, CancellationToken cancellationToken)
        {
            _calls.Enqueue((bundleIdentifier, scriptPath));
            _signal.Release();
            return Task.FromResult(0);
        }

        public async Task WaitForCallCountAsync(int expectedCallCount, TimeSpan timeout)
        {
            var deadline = DateTimeOffset.UtcNow + timeout;

            while (_calls.Count < expectedCallCount)
            {
                var remaining = deadline - DateTimeOffset.UtcNow;
                if (remaining <= TimeSpan.Zero)
                {
                    throw new TimeoutException($"Timed out waiting for {expectedCallCount} command calls.");
                }

                await _signal.WaitAsync(remaining);
            }
        }
    }
}
