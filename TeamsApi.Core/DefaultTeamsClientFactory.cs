using Teams.ThirdPartyAppApi.TeamsClient;

namespace TeamsApi.Core;

internal sealed class DefaultTeamsClientFactory : ITeamsClientFactory
{
    public ITeamsClient Create(TeamsConnectionSettings settings, CancellationToken cancellationToken)
    {
        var client = new TeamsClient(
            settings.Host,
            settings.Port,
            settings.Token,
            settings.Manufacturer,
            settings.Device,
            settings.App,
            settings.AppVersion,
            autoReconnect: settings.AutoReconnect,
            cancellationToken);

        return new TeamsClientAdapter(client);
    }
}
