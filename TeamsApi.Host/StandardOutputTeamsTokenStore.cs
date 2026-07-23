using System.Text;
using TeamsApi.Core;

namespace TeamsApi.Host;

/// <summary>
/// Relays the token between Core and the menu-bar parent process.
/// The parent consumes TEAMS_TOKEN lines before forwarding host output.
/// </summary>
internal sealed class StandardOutputTeamsTokenStore : ITeamsTokenStore
{
    private const string TokenPrefix = "TEAMS_TOKEN:";

    public Task<string?> GetTokenAsync(CancellationToken cancellationToken = default)
    {
        return Task.FromResult(Environment.GetEnvironmentVariable("teamstoken"));
    }

    public Task SaveTokenAsync(string token, CancellationToken cancellationToken = default)
    {
        var encodedToken = Convert.ToBase64String(Encoding.UTF8.GetBytes(token));
        Console.Out.WriteLine($"{TokenPrefix}{encodedToken}");
        return Task.CompletedTask;
    }
}
