#!/bin/bash
# Esta herramienta NO se invoca automáticamente desde el monitor o instalador.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
umask 077

action=${1:-}
uid=${2:-}
emit_rule() {
    printf '# MacBatteryMonitor: UID %s, un único comando con argumentos exactos\n#%s ALL=(root) NOPASSWD: /usr/bin/pmset -b lowpowermode 1\n' "$uid" "$uid"
}
if [ "$#" -ne 2 ] || [[ ! "$uid" =~ ^[1-9][0-9]{0,9}$ ]]; then
    echo 'Uso: /bin/bash power-permission.sh show|install|remove UID (install/remove requieren sudo)' >&2; exit 2
fi
case "$action" in
    show)
        emit_rule
        exit 0 ;;
    install|remove) ;; *) echo 'Acción inválida' >&2; exit 2 ;;
esac
echo 'Se necesita administrador para modificar una regla en /etc/sudoers.d.'
echo 'Esta regla solo permite ejecutar como root: /usr/bin/pmset -b lowpowermode 1'
echo 'No concede permiso para desactivarlo, modificar otros ajustes ni ejecutar scripts como root.'
[ "$EUID" -eq 0 ] || { echo 'Consulta README.md antes de ejecutar con sudo.' >&2; exit 1; }
[ -d /private/etc/sudoers.d ] && [ ! -L /private/etc/sudoers.d ] || {
    echo 'No existe un directorio sudoers.d seguro; no se modifica sudoers.' >&2; exit 1;
}
target="/private/etc/sudoers.d/mac-battery-monitor-$uid"
if [ "$action" = remove ]; then
    rm -f "$target"
    /usr/sbin/visudo -c
    echo 'Autorización retirada. El ajuste actual de bajo consumo se conserva.'
    exit 0
fi
[ ! -e "$target" ] && [ ! -L "$target" ] || {
    echo 'La regla ya existe. Revísala o retírala antes de reinstalar.' >&2; exit 1;
}
/usr/sbin/visudo -c
# Un nombre temporal con punto es ignorado por la directiva @includedir.
temp=$(mktemp /private/etc/sudoers.d/.mac-battery-monitor.XXXXXX)
trap 'rm -f "$temp"' EXIT
emit_rule > "$temp"
chown root:wheel "$temp"
chmod 440 "$temp"
/usr/sbin/visudo -cf "$temp"
mv "$temp" "$target"
if ! /usr/sbin/visudo -c; then
    rm -f "$target"
    echo 'Error de validación; se retiró la regla nueva.' >&2; exit 1
fi
echo "Regla instalada: $target"
echo 'Comprueba que sudo la reconoce: sudo -n -l /usr/bin/pmset -b lowpowermode 1'
