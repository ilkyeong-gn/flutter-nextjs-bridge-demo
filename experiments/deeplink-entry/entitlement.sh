#!/bin/sh
# Runner에 associated-domains 엔타이틀먼트를 붙였다 뗀다.
#   ./entitlement.sh on 'applinks:fan.example'
#   ./entitlement.sh on 'applinks:fan.example?mode=developer'
#   ./entitlement.sh off
set -eu
cd "$(dirname "$0")/app/ios"
PBX=Runner.xcodeproj/project.pbxproj
ENT=Runner/Runner.entitlements

# 먼저 항상 뗀다.
sed -i '' '/CODE_SIGN_ENTITLEMENTS = Runner\/Runner.entitlements;/d' "$PBX"
rm -f "$ENT"

if [ "${1:-off}" = on ]; then
  cat > "$ENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyLists-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.associated-domains</key>
	<array>
		<string>$2</string>
	</array>
</dict>
</plist>
EOF
  # Runner 타깃의 Debug·Release·Profile 설정(번들 ID 줄) 바로 뒤에 넣는다.
  sed -i '' 's|^\([[:space:]]*\)PRODUCT_BUNDLE_IDENTIFIER = example.fan.exp.dle;|&\
\1CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;|' "$PBX"
fi
grep -c 'CODE_SIGN_ENTITLEMENTS' "$PBX" || true
