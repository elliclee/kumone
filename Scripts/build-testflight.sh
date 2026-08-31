#!/usr/bin/env bash
# 构建并可选上传 Kumo 的 TestFlight Internal Only 版本。
#
#   Scripts/build-testflight.sh            # 导出本地签名 IPA
#   Scripts/build-testflight.sh --upload   # 归档、校验并上传 App Store Connect
set -euo pipefail

TEAM_ID="${KUMO_TEAM_ID:-GLAX98QHX4}"
ASC_KEY_ID="${KUMO_ASC_KEY_ID:-3AU3H29X5A}"
ASC_ISSUER_ID="${KUMO_ASC_ISSUER_ID:-f2a5ffef-ebd3-460a-ac5c-4c845a5b4312}"
ASC_KEY_PATH="${KUMO_ASC_KEY_PATH:-${HOME}/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

BUNDLE_ID="com.wenmingshu.kumone.internal"
DISPLAY_NAME="Kumo"
VERSION="${KUMO_VERSION:-0.3.15}"
BUILD_NUMBER="${KUMO_BUILD:-1}"
SCHEME="KumoneIOS"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$ROOT/ios/KumoneIOS.xcworkspace"
OUTPUT_ROOT="${KUMO_ARCHIVE_OUT:-$(mktemp -d /tmp/kumo-testflight.XXXXXX)}"
ARCHIVE="$OUTPUT_ROOT/Kumo.xcarchive"
EXPORT_PATH="$OUTPUT_ROOT/export"
EXPORT_OPTIONS="$OUTPUT_ROOT/ExportOptions.plist"

UPLOAD=no
if [[ "${1:-}" == "--upload" ]]; then
    UPLOAD=yes
elif [[ -n "${1:-}" ]]; then
    echo "未知参数：$1" >&2
    exit 2
fi

[[ -f "$ASC_KEY_PATH" ]] || { echo "缺少 API 密钥：$ASC_KEY_PATH" >&2; exit 1; }
[[ -f "$ROOT/ios/KumoneIOS/PrivacyInfo.xcprivacy" ]] || { echo "缺少 PrivacyInfo.xcprivacy" >&2; exit 1; }

PYTHON="${KUMO_PYTHON:-/Users/ellic/code/zhimingshu/.venv/bin/python}"
[[ -x "$PYTHON" ]] || PYTHON=python3

echo "==> 准备 Kumo 独立签名材料"
SIGNING_OUTPUT="$($PYTHON "$ROOT/Scripts/prepare-testflight-signing.py" --require-app)"
echo "$SIGNING_OUTPUT" | grep -v '^PROFILE_' || true
PROFILE_NAME="$(echo "$SIGNING_OUTPUT" | sed -n 's/^PROFILE_NAME=//p')"
[[ -n "$PROFILE_NAME" ]] || { echo "没有取得 Kumo 描述文件名。" >&2; exit 1; }

echo "==> 归档 Kumo $VERSION ($BUILD_NUMBER)"
if [[ "${KUMO_REUSE_ARCHIVE:-0}" == "1" && -d "$ARCHIVE" ]]; then
    echo "    复用已有 Archive：$ARCHIVE"
else
    xcodebuild archive \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -archivePath "$ARCHIVE" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="Apple Distribution" \
        KUMO_PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
        INFOPLIST_KEY_CFBundleDisplayName="$DISPLAY_NAME" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
fi

APP="$ARCHIVE/Products/Applications/KumoneIOS.app"
[[ -d "$APP" ]] || { echo "归档中没有 KumoneIOS.app" >&2; exit 1; }

echo "==> 校验归档"
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist")" == "$BUNDLE_ID" ]]
[[ "$(plutil -extract CFBundleDisplayName raw -o - "$APP/Info.plist")" == "$DISPLAY_NAME" ]]
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Info.plist")" == "$VERSION" ]]
[[ "$(plutil -extract CFBundleVersion raw -o - "$APP/Info.plist")" == "$BUILD_NUMBER" ]]
[[ "$(lipo -archs "$APP/KumoneIOS")" == "arm64" ]]
codesign --verify --deep --strict "$APP"

PROFILE_PLIST="$OUTPUT_ROOT/embedded-profile.plist"
security cms -D -i "$APP/embedded.mobileprovision" > "$PROFILE_PLIST"
[[ "$(plutil -extract TeamIdentifier.0 raw -o - "$PROFILE_PLIST")" == "$TEAM_ID" ]]
[[ "$(plutil -extract Entitlements.application-identifier raw -o - "$PROFILE_PLIST")" == "$TEAM_ID.$BUNDLE_ID" ]]
[[ "$(plutil -extract Entitlements.get-task-allow raw -o - "$PROFILE_PLIST")" == "false" ]]

if [[ "$UPLOAD" == yes ]]; then
    DESTINATION=upload
else
    DESTINATION=export
fi

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$DESTINATION</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Apple Distribution</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>$BUNDLE_ID</key><string>$PROFILE_NAME</string>
    </dict>
    <key>manageAppVersionAndBuildNumber</key><false/>
    <key>uploadSymbols</key><true/>
    <key>testFlightInternalTestingOnly</key><true/>
</dict>
</plist>
PLIST

echo "==> 导出模式：${DESTINATION}（TestFlight Internal Only）"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo
if [[ "$UPLOAD" == yes ]]; then
    echo "UPLOAD_COMPLETE=yes"
    echo "已上传 Kumo $VERSION ($BUILD_NUMBER)；输出目录：$OUTPUT_ROOT"
else
    IPA="$(find "$EXPORT_PATH" -maxdepth 1 -name '*.ipa' -print -quit)"
    [[ -n "$IPA" ]] || { echo "没有导出 IPA。" >&2; exit 1; }
    echo "IPA=$IPA"
    echo "已导出 Kumo $VERSION ($BUILD_NUMBER)；尚未上传。"
fi
