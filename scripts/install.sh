#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
umask 077

app_bundle=
if [ "$#" -eq 2 ] && [ "$1" = --app-bundle ]; then
    app_bundle=$2
    [ -x "$app_bundle/Contents/MacOS/MacBatteryMonitor" ] &&
        [ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app_bundle/Contents/Info.plist")" = local.mac-battery-monitor.app ] || {
        echo 'El bundle de la app no es válido' >&2; exit 1;
    }
elif [ "$#" -ne 0 ]; then echo 'Uso: install.sh [--app-bundle RUTA.app]' >&2; exit 2; fi
[ "$(uname -s)" = Darwin ] || { echo 'Se requiere macOS' >&2; exit 1; }
[ "$EUID" -ne 0 ] || { echo 'Instala como usuario, sin sudo' >&2; exit 1; }
for tool in /usr/bin/lockf /usr/bin/osascript /usr/bin/pmset /bin/launchctl /usr/bin/plutil; do
    [ -x "$tool" ] || { echo "Falta herramienta de macOS: $tool" >&2; exit 1; }
done
source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
label=local.mac-battery-monitor
domain="gui/$(id -u)"
app_dir="$HOME/Library/Application Support/MacBatteryMonitor"
log_dir="$HOME/Library/Logs/MacBatteryMonitor"
plist="$HOME/Library/LaunchAgents/$label.plist"
source "$source_dir/battery-monitor.sh"
data_dir="$app_dir"
load_settings || { echo 'Corrige los ajustes antes de instalar.' >&2; exit 1; }
launchctl print "$domain" >/dev/null || { echo 'Ejecuta dentro de una sesión gráfica de macOS' >&2; exit 1; }
mkdir -p "$app_dir" "$log_dir" "${plist%/*}"

# Un plist generado con plutil conserva espacios, & y caracteres Unicode.
temp=$(mktemp "$app_dir/agent.XXXXXX")
trap 'rm -f "$temp"' EXIT
plutil -create xml1 "$temp"
plutil -insert Label -string "$label" "$temp"
plutil -insert ProgramArguments -xml '<array/>' "$temp"
plutil -insert ProgramArguments.0 -string /bin/bash "$temp"
plutil -insert ProgramArguments.1 -string "$app_dir/battery-monitor.sh" "$temp"
plutil -insert StartInterval -integer "$((interval_minutes * 60))" "$temp"
plutil -insert RunAtLoad -bool YES "$temp"
plutil -insert LimitLoadToSessionType -string Aqua "$temp"
plutil -insert ProcessType -string Background "$temp"
plutil -insert StandardOutPath -string /dev/null "$temp"
plutil -insert StandardErrorPath -string /dev/null "$temp"
plutil -lint "$temp"

if launchctl print "$domain/$label" >/dev/null 2>&1; then
    launchctl bootout "$domain/$label"
fi
install -m 700 "$source_dir/battery-monitor.sh" "$app_dir/battery-monitor.sh"
if [ -n "$app_bundle" ]; then
    # Copia estable para enviar avisos aunque se cierre o se mueva la app original.
    staged_bundle="$app_dir/Notifier-staging.app"
    /bin/rm -rf "$staged_bundle"
    /usr/bin/ditto "$app_bundle" "$staged_bundle"
    /bin/rm -rf "$app_dir/Notifier.app"
    /bin/mv "$staged_bundle" "$app_dir/Notifier.app"
fi
mv -f "$temp" "$plist"
chmod 600 "$plist"
launchctl enable "$domain/$label"
launchctl bootstrap "$domain" "$plist"
echo "Instalado: comprobación cada $interval_minutes minuto(s). Logs: $log_dir/monitor.log"
echo 'Para probar los avisos: /bin/bash battery-monitor.sh --test-notification'
echo 'La activación de bajo consumo requiere la autorización opcional descrita en la documentación.'
