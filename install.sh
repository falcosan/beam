#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

app=MIA.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"

cc -o "$app/Contents/MacOS/MIA" mia.s \
  -Wl,-objc_stubs_small,-no_data_const,-x,-no_function_starts,-no_data_in_code_info,-no_source_version

icons=$app/Contents/Resources/MIA.iconset
mkdir -p "$icons"
for s in 16 32 128 256 512; do
  sips -s format png -z $s $s icon.svg --out "$icons/icon_${s}x$s.png" >/dev/null
  sips -s format png -z $((s * 2)) $((s * 2)) icon.svg --out "$icons/icon_${s}x$s@2x.png" >/dev/null
done
iconutil -c icns "$icons" -o "$app/Contents/Resources/MIA.icns"
rm -r "$icons"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>Audio and video</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.audiovisual-content</string>
			</array>
		</dict>
	</array>
	<key>CFBundleExecutable</key>
	<string>MIA</string>
	<key>CFBundleIconFile</key>
	<string>MIA</string>
	<key>CFBundleIdentifier</key>
	<string>local.mia</string>
	<key>CFBundleName</key>
	<string>MIA</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF

codesign --force --sign - "$app"
echo "Built $PWD/$app"
