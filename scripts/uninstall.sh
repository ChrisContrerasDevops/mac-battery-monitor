#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
purge=0
if [ "$#" -eq 1 ] && [ "$1" = --purge ]; then purge=1
elif [ "$#" -ne 0 ]; then echo 'Uso: /bin/bash uninstall.sh [--purge]' >&2; exit 2; fi
[ "$EUID" -ne 0 ] || { echo 'Ejecuta como usuario, sin sudo' >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || { echo 'Se requiere macOS' >&2; exit 1; }
label=local.mac-battery-monitor
service="gui/$(id -u)/$label"
if launchctl print "$service" >/dev/null 2>&1; then launchctl bootout "$service"; fi
rm -f "$HOME/Library/LaunchAgents/$label.plist"
app_dir="$HOME/Library/Application Support/MacBatteryMonitor"
if [ -d "$app_dir" ]; then
    # Esperar a cualquier ejecución manual antes de borrar su estado.
    /usr/bin/lockf -k -t 10 "$app_dir/check.lock" /bin/rm -f "$app_dir/battery-monitor.sh" "$app_dir/state" "$app_dir/settings"
    rm -rf "$app_dir/Notifier.app" "$app_dir/Notifier-staging.app"
    rm -f "$app_dir/check.lock"
    rmdir "$app_dir" 2>/dev/null || true
fi
if [ "$purge" -eq 1 ]; then
    log="$HOME/Library/Logs/MacBatteryMonitor/monitor.log"
    rm -f "$log" "$log.1" "$log.2" "$log.3"
    rmdir "${log%/*}" 2>/dev/null || true
fi
echo 'LaunchAgent desinstalado. Logs conservados salvo si usaste --purge.'
if [ -f "/private/etc/sudoers.d/mac-battery-monitor-$(id -u)" ]; then
    echo 'Queda la autorización opcional. Para retirarla se necesita administrador porque reside en /etc/sudoers.d:'
    echo 'sudo /bin/bash power-permission.sh remove "$(/usr/bin/id -u)"'
fi
echo 'El ajuste actual de bajo consumo no se modifica.'
