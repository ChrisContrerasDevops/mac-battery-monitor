#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$#" -eq 1 ] && [ "$1" = --existing-app ]; then
    codesign --verify --strict "$root/build/Mac Battery Monitor.app"
elif [ "$#" -eq 0 ]; then
    /bin/bash "$root/scripts/build.sh"
else
    echo 'Uso: package.sh [--existing-app]' >&2; exit 2
fi
version=$(plutil -extract CFBundleShortVersionString raw "$root/build/Mac Battery Monitor.app/Contents/Info.plist")
arch=$(lipo -archs "$root/build/Mac Battery Monitor.app/Contents/MacOS/MacBatteryMonitor")
case "$arch" in arm64|x86_64) ;; *) echo "Arquitectura de bundle inesperada: $arch" >&2; exit 1 ;; esac
name="Mac-Battery-Monitor-$version-$arch"
mkdir -p "$root/dist"
stage=$(mktemp -d "$root/build/dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$root/build/Mac Battery Monitor.app" "$stage/Mac Battery Monitor.app"
ln -s /Applications "$stage/Applications"
cp "$root/docs/INSTALL.txt" "$stage/LEEME.txt"
hdiutil create -ov -volname 'Mac Battery Monitor' -srcfolder "$stage" \
    -format UDZO "$root/dist/$name.dmg"
hdiutil verify "$root/dist/$name.dmg"
ditto -c -k --sequesterRsrc --keepParent "$root/build/Mac Battery Monitor.app" "$root/dist/$name.zip"
unzip -tq "$root/dist/$name.zip"
cd "$root/dist"
shasum -a 256 "$name.dmg" "$name.zip" > "$name.sha256"
echo "Paquetes listos en $root/dist"
