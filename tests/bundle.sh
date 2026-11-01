#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
app="$root/build/Mac Battery Monitor.app"
temp=$(mktemp -d "${TMPDIR:-/tmp}/mac-battery-bundle.XXXXXX")
trap 'rm -rf "$temp"' EXIT
codesign --verify --strict "$app"
cmp "$root/docs/assets/banner.png" "$app/Contents/Resources/banner.png"
"$app/Contents/MacOS/MacBatteryMonitor" --self-test

launchctl() {
    case "$1" in
        print) case "$2" in gui/*/*) return 1 ;; *) return 0 ;; esac ;;
        bootstrap) plutil -lint "$3" >/dev/null ;;
        enable|bootout) return 0 ;;
        *) return 1 ;;
    esac
}
export -f launchctl
fake_home="$temp/Usuario & prueba"
HOME="$fake_home" /bin/bash "$root/scripts/battery-monitor.sh" --configure 43 17 25 >/dev/null
HOME="$fake_home" /bin/bash "$root/scripts/install.sh" --app-bundle "$app" >/dev/null
installed="$fake_home/Library/Application Support/MacBatteryMonitor/Notifier.app"
codesign --verify --strict "$installed"
HOME="$fake_home" "$installed/Contents/MacOS/MacBatteryMonitor" --self-test
preferences="$fake_home/Library/Application Support/MacBatteryMonitor/settings"
[ "$(cat "$preferences")" = 'v2 43 17 25' ] || { echo 'Instalación de app pierde preferencias' >&2; exit 1; }
[ "$(plutil -extract StartInterval raw "$fake_home/Library/LaunchAgents/local.mac-battery-monitor.plist")" = 1500 ] || {
    echo 'La app no instala el intervalo personalizado' >&2; exit 1;
}
printf 'v1 1 1 0 0\n' > "${preferences%/*}/state"
HOME="$fake_home" /bin/bash "$root/scripts/install.sh" --app-bundle "$app" >/dev/null
[ "$(cat "$preferences")" = 'v2 43 17 25' ] || { echo 'Actualización pierde preferencias' >&2; exit 1; }
[ "$(cat "${preferences%/*}/state")" = 'v1 1 1 0 0' ] || { echo 'Actualización pierde estado anterior' >&2; exit 1; }
HOME="$fake_home" /bin/bash "$root/scripts/uninstall.sh" --purge >/dev/null
[ ! -d "$installed" ] || { echo 'La copia nativa no se desinstaló' >&2; exit 1; }
[ ! -e "$preferences" ] || { echo 'La configuración no se desinstaló' >&2; exit 1; }
echo 'Bundle verificado: imagen, firma, instalación, conservación de preferencias y desinstalación en HOME temporal.'
