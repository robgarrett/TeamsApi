namespace TeamsApi.Core;

/// <summary>
/// Provides durable storage for the pairing token issued by Teams.
/// </summary>
public interface ITeamsTokenStore
{
    Task<string?> GetTokenAsync(CancellationToken cancellationToken = default);

    Task SaveTokenAsync(string token, CancellationToken cancellationToken = default);
}

internal sealed class NullTeamsTokenStore : ITeamsTokenStore
{
    public Task<string?> GetTokenAsync(CancellationToken cancellationToken = default)
    {
        return Task.FromResult<string?>(null);
    }

    public Task SaveTokenAsync(string token, CancellationToken cancellationToken = default)
    {
        return Task.CompletedTask;
    }
}
