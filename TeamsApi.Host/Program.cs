using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;
using TeamsApi.Core;

using var loggerFactory = LoggerFactory.Create(builder =>
{
    builder.SetMinimumLevel(LogLevel.Information);
    builder.AddSimpleConsole(options =>
    {
        options.SingleLine = true;
        options.TimestampFormat = "HH:mm:ss ";
    });
});

using var cancellationSource = new CancellationTokenSource();
using var sigint = PosixSignalRegistration.Create(PosixSignal.SIGINT, ctx =>
{
    ctx.Cancel = true;
    cancellationSource.Cancel();
});
using var sigterm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, ctx =>
{
    ctx.Cancel = true;
    cancellationSource.Cancel();
});

var runner = new AppRunner(loggerFactory.CreateLogger<AppRunner>());
return await runner.RunAsync(cancellationSource.Token);
