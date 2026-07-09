namespace TeamsApi.Core;

public static class RepoRootPath
{
    private const string SolutionFileName = "TeamsApi.sln";

    public static string Get()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);

        while (directory is not null)
        {
            if (directory.EnumerateFiles(SolutionFileName).Any())
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        return AppContext.BaseDirectory;
    }

    public static string Resolve(string path)
    {
        if (Path.IsPathRooted(path))
        {
            return path;
        }

        return Path.GetFullPath(Path.Combine(Get(), path));
    }
}
