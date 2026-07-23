namespace TeamsApi.Core;

public interface ITeamsClient : IDisposable
{
    IObservable<bool> IsInMeetingChanged { get; }
    IObservable<bool> CanToggleMuteChanged { get; }
    IObservable<string> TokenChanged { get; }

    bool CanToggleMute { get; }

    Task Connect(CancellationToken cancellationToken = default);
    Task ToggleMute();
}

public interface ITeamsClientFactory
{
    ITeamsClient Create(TeamsConnectionSettings settings, CancellationToken cancellationToken);
}
