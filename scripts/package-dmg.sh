#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$repo_root/TeamsApi.MenuBarHost/.build/arm64-apple-macosx/release"
dist_root="$repo_root/dist"
staging_root="$dist_root/staging"
assets_root="$repo_root/TeamsApi.MenuBarHost/PackagingAssets"
app_name="TeamsApi"
app_bundle="$staging_root/$app_name.app"
contents_dir="$app_bundle/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
app_icon_source="$assets_root/AppIconSource.png"
final_dmg="$dist_root/$app_name-Private.dmg"

rm -rf "$staging_root" "$final_dmg"
mkdir -p "$dist_root" "$macos_dir" "$resources_dir"

if [[ ! -f "$app_icon_source" ]]; then
  echo "Missing app icon source: $app_icon_source" >&2
  exit 1
fi

"$repo_root/scripts/publish-host-runtime.sh"

HOME=/private/tmp DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build --package-path "$repo_root/TeamsApi.MenuBarHost" -c release --disable-sandbox

swift_bin_path="$(
  HOME=/private/tmp DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    swift build --package-path "$repo_root/TeamsApi.MenuBarHost" -c release --show-bin-path
)"

cp "$swift_bin_path/TeamsApiMenuBarHost" "$macos_dir/TeamsApiMenuBarHost"
chmod +x "$macos_dir/TeamsApiMenuBarHost"

for bundle in "$swift_bin_path"/*.bundle; do
  if [[ -d "$bundle" ]]; then
    cp -R "$bundle" "$resources_dir/"
  fi
done

app_icon_work_dir="$(mktemp -d /private/tmp/TeamsApiAppIcon.XXXXXX)"

cleanup() {
  rm -rf "$app_icon_work_dir"
  rm -rf "$staging_root"
}
trap cleanup EXIT

create_icon_representation() {
  local size="$1"
  local output_name="$2"

  sips -s format png -z "$size" "$size" "$app_icon_source" --out "$app_icon_work_dir/$output_name" >/dev/null
}

create_icon_representation 16 icon_16x16.png
create_icon_representation 32 icon_32x32.png
create_icon_representation 64 icon_64x64.png
create_icon_representation 128 icon_128x128.png
create_icon_representation 256 icon_256x256.png
create_icon_representation 512 icon_512x512.png
create_icon_representation 1024 icon_1024x1024.png

python3 - "$resources_dir/AppIcon.icns" "$app_icon_work_dir" <<'PY'
import os
import struct
import sys

output_path = sys.argv[1]
source_dir = sys.argv[2]
chunks = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_64x64.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_1024x1024.png"),
]

entries = []
for chunk_type, file_name in chunks:
    file_path = os.path.join(source_dir, file_name)
    with open(file_path, "rb") as file_handle:
        entries.append((chunk_type.encode("ascii"), file_handle.read()))

total_size = 8 + sum(8 + len(data) for _, data in entries)
with open(output_path, "wb") as output_file:
    output_file.write(b"icns")
    output_file.write(struct.pack(">I", total_size))
    for chunk_type, data in entries:
        output_file.write(chunk_type)
        output_file.write(struct.pack(">I", len(data) + 8))
        output_file.write(data)
PY
cat > "$contents_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>TeamsApiMenuBarHost</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.robgarrett.TeamsApiMenuBarHost</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>TeamsApi</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

python3 - "$final_dmg" "$app_name" "$app_bundle" <<'PY'
from dmgbuild.core import build_dmg
import sys

filename = sys.argv[1]
volume_name = sys.argv[2]
app_bundle = sys.argv[3]
app_name = app_bundle.rsplit("/", 1)[-1]

settings = {
    "format": "UDZO",
    "filesystem": "HFS+",
    "window_rect": ((160, 120), (1080, 600)),
    "icon_size": 140,
    "text_size": 14,
    "show_toolbar": False,
    "show_status_bar": False,
    "show_pathbar": False,
    "show_sidebar": False,
    "files": [(app_bundle, app_name)],
    "symlinks": {"Applications": "/Applications"},
    "icon_locations": {
        app_name: (190, 255),
        "Applications": (700, 255),
    },
}

build_dmg(filename, volume_name, settings=settings)
PY

echo "Created $final_dmg"
