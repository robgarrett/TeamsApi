#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$repo_root/TeamsApi.MenuBarHost/.build/arm64-apple-macosx/release"
dist_root="$repo_root/dist"
staging_root="$dist_root/staging"
app_name="TeamsApi"
app_bundle="$staging_root/$app_name.app"
contents_dir="$app_bundle/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
tmp_dmg="$dist_root/$app_name.dmg"
final_dmg="$dist_root/$app_name-Private.dmg"

rm -rf "$staging_root" "$tmp_dmg" "$final_dmg"
mkdir -p "$dist_root" "$macos_dir" "$resources_dir"

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
  <string></string>
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

ln -s /Applications "$staging_root/Applications"
hdiutil create -volname "$app_name" -srcfolder "$staging_root" -ov -format UDZO "$tmp_dmg"
mv "$tmp_dmg" "$final_dmg"

echo "Created $final_dmg"
