#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

app=Beam.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"

cc -o "$app/Contents/MacOS/Beam" beam.s -framework AppKit -framework AVFoundation -lcurl \
  -Wl,-objc_stubs_small,-no_data_const,-x,-no_function_starts,-no_data_in_code_info,-no_source_version

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Beam</string>
	<key>CFBundleIdentifier</key>
	<string>local.beam</string>
	<key>CFBundleName</key>
	<string>Beam</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSLocalNetworkUsageDescription</key>
	<string>Beam finds and plays on the speakers and TVs on your network.</string>
</dict>
</plist>
EOF

codesign --force --sign - "$app"
echo "Built $PWD/$app"
