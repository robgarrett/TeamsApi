using Teams.ThirdPartyAppApi.TeamsClient;

namespace TeamsApi.Core;

internal sealed class TeamsClientAdapter : ITeamsClient
{
    private readonly TeamsClient _teamsClient;

    public TeamsClientAdapter(TeamsClient teamsClient)
    {
        _teamsClient = teamsClient;
    }

    public IObservable<bool> IsInMeetingChanged => _teamsClient.IsInMeetingChanged;
    public IObservable<bool> CanToggleMuteChanged => _teamsClient.CanToggleMuteChanged;
    public IObservable<string> TokenChanged => _teamsClient.TokenChanged;

    public bool CanToggleMute => _teamsClient.CanToggleMute;

    public Task Connect(CancellationToken cancellationToken = default)
    {
        return _teamsClient.Connect(cancellationToken);
    }

    public Task ToggleMute()
    {
        return _teamsClient.ToggleMute();
    }

    public void Dispose()
    {
        _teamsClient.Dispose();
    }
}
