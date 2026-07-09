namespace TeamsApi.Core;

public interface IAppCommandExecutor
{
    Task<int> ExecuteAsync(string bundleIdentifier, string scriptPath, CancellationToken cancellationToken);
}
