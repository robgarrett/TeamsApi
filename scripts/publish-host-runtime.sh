#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
publish_dir="$repo_root/TeamsApi.MenuBarHost/Sources/TeamsApiMenuBarHost/Resources/TeamsApiHostRuntime"

rm -rf "$publish_dir"
mkdir -p "$publish_dir"

dotnet restore "$repo_root/TeamsApi.Host/TeamsApi.Host.csproj" \
  -r osx-arm64 \
  --ignore-failed-sources

dotnet publish "$repo_root/TeamsApi.Host/TeamsApi.Host.csproj" \
  -c Release \
  -r osx-arm64 \
  --self-contained true \
  --no-restore \
  /p:PublishSingleFile=true \
  /p:IncludeNativeLibrariesForSelfExtract=true \
  -o "$publish_dir"

host_executable="$publish_dir/TeamsApi.Host"

if [[ ! -f "$host_executable" ]]; then
  echo "Expected published host executable at $host_executable" >&2
  exit 1
fi

chmod +x "$host_executable"
echo "Published self-contained host to $publish_dir"
