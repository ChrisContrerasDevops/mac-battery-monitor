#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
app="$root/build/Mac Battery Monitor.app"
version=$(cat "$root/VERSION")
arch=${BUILD_ARCH:-arm64}
case "$arch" in arm64|x86_64) ;; *) echo 'BUILD_ARCH debe ser arm64 o x86_64' >&2; exit 2 ;; esac
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/scripts" "$root/build/module-cache"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
for script in battery-monitor install uninstall power-permission; do
    install -m 755 "$root/scripts/$script.sh" "$app/Contents/Resources/scripts/$script.sh"
done
cp "$root/docs/assets/banner.png" "$app/Contents/Resources/banner.png"
cp "$root/docs/usage.md" "$app/Contents/Resources/usage.md"
cp "$root/LICENSE" "$app/Contents/Resources/LICENSE"
xcrun swiftc -swift-version 5 -O -target "$arch-apple-macosx15.0" \
    -module-cache-path "$root/build/module-cache" \
    -framework AppKit -framework UserNotifications \
    "$root/Sources/MacBatteryMonitor/main.swift" \
    -o "$app/Contents/MacOS/MacBatteryMonitor"

# Conversión técnica del mismo arte a los tamaños que exige el formato ICNS.
icon="$app/Contents/Resources/AppIcon.icns"
if [ ! -f "$icon" ] || [ "$root/docs/assets/banner.png" -nt "$icon" ]; then
    iconset="$root/build/AppIcon.iconset"
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$root/docs/assets/banner.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" "$root/docs/assets/banner.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset" -o "$icon"
fi

# Firma ad hoc local; una identidad Developer ID puede pasarse al distribuir.
identity=${CODESIGN_IDENTITY:--}
if [ "$identity" = - ]; then
    codesign --force --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --strict "$app"
plutil -lint "$app/Contents/Info.plist"
echo "App compilada: $app ($arch)"
