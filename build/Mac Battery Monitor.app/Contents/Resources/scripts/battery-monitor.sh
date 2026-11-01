#!/bin/bash
# Compatible con el Bash del sistema. No cargar este archivo como root.

export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
umask 077

validate_thresholds() {
    if [[ ! "$1" =~ ^[1-9][0-9]?$ || ! "$2" =~ ^[1-9][0-9]?$ ]]; then
        printf 'Los porcentajes deben ser enteros entre 1 y 99.\n' >&2
        return 1
    fi
}

validate_interval() {
    if [[ ! "$1" =~ ^[1-9][0-9]{0,2}$ ]] || [ "$1" -gt 120 ]; then
        printf 'El intervalo debe ser un entero entre 1 y 120 minutos.\n' >&2
        return 1
    fi
}

load_settings() {
    local content version extra
    alert_threshold=30; power_threshold=20; interval_minutes=10
    if [ -f "$data_dir/settings" ]; then
        content=$(/bin/cat "$data_dir/settings") || return 1
        if [[ "$content" == *$'\n'* ]]; then
            printf 'Configuración inválida: se esperaba una sola línea.\n' >&2; return 1
        fi
        IFS=' ' read -r version alert_threshold power_threshold interval_minutes extra <<< "$content"
        if [ "$version" = v1 ] && [ -z "$interval_minutes$extra" ]; then
            interval_minutes=10
        elif [ "$version" != v2 ] || ! validate_interval "$interval_minutes"; then
            printf 'Versión o intervalo de configuración inválido.\n' >&2; return 1
        fi
        if [ -n "$extra" ] || ! validate_thresholds "$alert_threshold" "$power_threshold"; then
            printf 'Configuración inválida: %s/settings\n' "$data_dir" >&2; return 1
        fi
    fi
    # La recarga debe superar ambos umbrales con margen; siempre se rearma al 100 %.
    rearm_level=$((alert_threshold > power_threshold ? alert_threshold + 6 : power_threshold + 6))
    [ "$rearm_level" -le 100 ] || rearm_level=100
}

save_settings() {
    local temp minutes=${3:-10}
    validate_thresholds "$1" "$2" || return 1
    validate_interval "$minutes" || return 1
    temp=$(/usr/bin/mktemp "$data_dir/settings.XXXXXX") || return 1
    if ! printf 'v2 %s %s %s\n' "$1" "$2" "$minutes" > "$temp"; then
        /bin/rm -f "$temp"; return 1
    fi
    /bin/mv -f "$temp" "$data_dir/settings" || { /bin/rm -f "$temp"; return 1; }
}

restore_configuration() {
    local settings_backup=$1 plist_backup=$2 registered=$3 service=$4 plist=$5 status=0
    if [ -n "$settings_backup" ]; then
        /bin/mv -f "$settings_backup" "$data_dir/settings" || status=1
    else
        /bin/rm -f "$data_dir/settings" || status=1
    fi
    if [ -n "$plist_backup" ]; then /bin/mv -f "$plist_backup" "$plist" || status=1; fi
    if [ "$registered" -eq 1 ] && ! launchctl print "$service" >/dev/null 2>&1; then
        if ! launchctl bootstrap "${service%/*}" "$plist"; then
            printf 'No se pudo restaurar la tarea. Vuelve a instalar el monitor.\n' >&2
            status=1
        fi
    fi
    return "$status"
}

apply_settings() {
    local minutes=${3:-} plist="$HOME/Library/LaunchAgents/local.mac-battery-monitor.plist"
    local service="gui/$(/usr/bin/id -u)/local.mac-battery-monitor" registered=0
    local seconds old_seconds settings_backup= plist_backup= staged_plist=
    if [ -f "$data_dir/battery-monitor.sh" ] &&
       ! /usr/bin/cmp -s "${BASH_SOURCE[0]}" "$data_dir/battery-monitor.sh"; then
        printf 'Actualiza el monitor antes de guardar: el motor instalado es de otra versión.\n' >&2
        return 1
    fi
    # El comando anterior de dos porcentajes conserva el intervalo guardado.
    if [ -z "$minutes" ]; then load_settings || return 1; minutes=$interval_minutes; fi
    validate_thresholds "$1" "$2" || return 1
    validate_interval "$minutes" || return 1
    seconds=$((minutes * 60))
    if launchctl print "$service" >/dev/null 2>&1; then registered=1; fi
    if [ "$registered" -eq 1 ] && [ ! -f "$plist" ]; then
        printf 'La tarea está registrada pero falta su plist. Actualiza el monitor antes de guardar.\n' >&2
        return 1
    fi
    if [ -f "$plist" ]; then
        /usr/bin/plutil -lint "$plist" >/dev/null || return 1
        old_seconds=$(/usr/bin/plutil -extract StartInterval raw "$plist") || return 1
        if [ "$old_seconds" != "$seconds" ]; then
            plist_backup=$(/usr/bin/mktemp "$data_dir/agent-backup.XXXXXX") || return 1
            /bin/cp -p "$plist" "$plist_backup" || { /bin/rm -f "$plist_backup"; return 1; }
            staged_plist=$(/usr/bin/mktemp "$data_dir/agent-update.XXXXXX") || { /bin/rm -f "$plist_backup"; return 1; }
            if ! /bin/cp -p "$plist" "$staged_plist" ||
               ! /usr/bin/plutil -replace StartInterval -integer "$seconds" "$staged_plist" ||
               ! /usr/bin/plutil -lint "$staged_plist" >/dev/null; then
                /bin/rm -f "$plist_backup" "$staged_plist"; return 1
            fi
        fi
    fi
    if [ -f "$data_dir/settings" ]; then
        settings_backup=$(/usr/bin/mktemp "$data_dir/settings-backup.XXXXXX") || {
            /bin/rm -f "$plist_backup" "$staged_plist"; return 1;
        }
        /bin/cp -p "$data_dir/settings" "$settings_backup" || {
            /bin/rm -f "$plist_backup" "$staged_plist" "$settings_backup"; return 1;
        }
    fi
    if ! save_settings "$1" "$2" "$minutes"; then
        /bin/rm -f "$plist_backup" "$staged_plist" "$settings_backup"; return 1
    fi
    if [ -n "$staged_plist" ]; then
        if ! /bin/mv -f "$staged_plist" "$plist" ||
           { [ "$registered" -eq 1 ] &&
             { ! launchctl bootout "$service" || ! launchctl bootstrap "${service%/*}" "$plist"; }; }; then
            restore_configuration "$settings_backup" "$plist_backup" "$registered" "$service" "$plist" || true
            /bin/rm -f "$staged_plist"
            printf 'No se pudo aplicar el intervalo; se intentó restaurar la configuración anterior.\n' >&2
            return 1
        fi
    fi
    /bin/rm -f "$settings_backup" "$plist_backup"
    log "INFO configuración guardada: aviso=$1% bajo_consumo=$2% intervalo=${minutes}min" || return 1
    printf 'Ajustes guardados: comprobación cada %s minuto(s).\n' "$minutes"
}

read_battery() {
    local output line value
    output=$(/usr/bin/pmset -g batt 2>&1) || { printf '%s\n' "$output" >&2; return 1; }
    parse_battery "$output"
}

parse_battery() {
    local output=$1 line value
    case "$output" in
        *"Now drawing from 'Battery Power'"*) power=battery ;;
        *"Now drawing from 'AC Power'"*) power=ac ;;
        *) printf 'Fuente de alimentación desconocida\n' >&2; return 1 ;;
    esac
    # Solo batería interna: ignorar UPS y periféricos con porcentaje.
    line=$(printf '%s\n' "$output" | /usr/bin/awk '/-InternalBattery-[0-9]+/ {print; exit}')
    value=$(printf '%s\n' "$line" | /usr/bin/sed -nE 's/.*[[:space:]]([0-9]{1,3})%;.*/\1/p')
    case "$value" in ''|*[!0-9]*) printf 'No se pudo leer la batería interna\n' >&2; return 1 ;; esac
    percent=$((10#$value))
    [ "$percent" -le 100 ] || { printf 'Porcentaje fuera de rango\n' >&2; return 1; }
}

log() {
    local size index
    if [ -f "$log_file" ]; then
        size=$(/usr/bin/stat -f %z "$log_file") || return 1
        if [ "$size" -ge 262144 ]; then
            for index in 2 1; do
                if [ -f "$log_file.$index" ]; then
                    /bin/mv -f "$log_file.$index" "$log_file.$((index + 1))" || return 1
                fi
            done
            /bin/mv -f "$log_file" "$log_file.1" || return 1
        fi
    fi
    printf '%s %s\n' "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$log_file"
}

load_state() {
    local version extra
    notified=0; low_done=0; next_notice=0; next_power=0
    state_alert=30; state_power=20
    low_notice_pending=0; next_low_notice=0
    [ -f "$state_file" ] || return 0
    IFS=' ' read -r version notified low_done next_notice next_power state_alert state_power low_notice_pending next_low_notice extra < "$state_file" || return 1
    if [ "$version" = v1 ] && [ -z "$state_alert$state_power$low_notice_pending$next_low_notice$extra" ]; then
        # Migrar sin repetir avisos ya completados con los valores originales.
        state_alert=30; state_power=20
        low_notice_pending=0; next_low_notice=0
    elif [ "$version" = v2 ] && [ -z "$low_notice_pending$next_low_notice$extra" ]; then
        # Las activaciones previas a este aviso no generan una notificación retrospectiva.
        low_notice_pending=0; next_low_notice=0
    elif [ "$version" != v3 ]; then
        printf 'Versión o umbrales de estado inválidos: %s\n' "$state_file" >&2; return 1
    fi
    if ! validate_thresholds "$state_alert" "$state_power" ||
       [[ ! "$notified" =~ ^[01]$ || ! "$low_done" =~ ^[01]$ ||
          ! "$next_notice" =~ ^[0-9]{1,11}$ || ! "$next_power" =~ ^[0-9]{1,11}$ ||
          ! "$low_notice_pending" =~ ^[01]$ || ! "$next_low_notice" =~ ^[0-9]{1,11}$ || -n "$extra" ]] ||
       { [ "$low_notice_pending" -eq 1 ] && [ "$low_done" -ne 1 ]; }; then
        printf 'Estado inválido: %s. Revisarlo antes de eliminarlo.\n' "$state_file" >&2
        return 1
    fi
    # Forzar base decimal al leer datos persistidos.
    next_notice=$((10#$next_notice)); next_power=$((10#$next_power))
    next_low_notice=$((10#$next_low_notice))
}

save_state() {
    local temp
    temp=$(/usr/bin/mktemp "$data_dir/state.XXXXXX") || return 1
    if ! printf 'v3 %s %s %s %s %s %s %s %s\n' "$notified" "$low_done" "$next_notice" "$next_power" "$state_alert" "$state_power" "$low_notice_pending" "$next_low_notice" > "$temp"; then
        /bin/rm -f "$temp"; return 1
    fi
    /bin/mv -f "$temp" "$state_file" || { /bin/rm -f "$temp"; return 1; }
}

notify() {
    local native="$HOME/Library/Application Support/MacBatteryMonitor/Notifier.app/Contents/MacOS/MacBatteryMonitor"
    if [ -x "$native" ]; then
        "$native" --notify "$1"
        return $?
    fi
    /usr/bin/osascript - "$1" <<'APPLESCRIPT'
on run argv
    display notification (item 1 of argv) with title "Monitor de batería" sound name "Glass"
end run
APPLESCRIPT
}

low_power_value() {
    local output value
    output=$(/usr/bin/pmset -g custom 2>&1) || { printf '%s\n' "$output" >&2; return 1; }
    value=$(printf '%s\n' "$output" | /usr/bin/awk '
        /^[^ \t]/ { battery = ($0 ~ /^Battery Power:/) }
        battery && $1 == "lowpowermode" { print $2; exit }')
    case "$value" in 0|1) printf '%s\n' "$value" ;; *) printf 'lowpowermode no disponible para batería\n' >&2; return 1 ;; esac
}

enable_low_power() {
    # -n: nunca solicitar contraseña. -k: no usar credenciales temporales en caché.
    # Solo funciona si existe una autorización NOPASSWD para este comando exacto.
    /usr/bin/sudo -n -k /usr/bin/pmset -b lowpowermode 1
}

check_once() {
    local now current result
    now=$(/bin/date +%s) || return 1
    load_settings || { log 'ERROR configuración inválida; no se ejecutan acciones'; return 1; }
    load_state || { log 'ERROR estado persistente inválido'; return 1; }
    # Cambiar solo un umbral rearma únicamente su acción, no la otra.
    if [ "$state_alert" -ne "$alert_threshold" ] || [ "$state_power" -ne "$power_threshold" ]; then
        if [ "$state_alert" -ne "$alert_threshold" ]; then notified=0; next_notice=0; fi
        if [ "$state_power" -ne "$power_threshold" ]; then
            low_done=0; next_power=0; low_notice_pending=0; next_low_notice=0
        fi
        state_alert=$alert_threshold; state_power=$power_threshold
        save_state || return 1
        log "INFO umbrales actualizados: aviso=$alert_threshold% bajo_consumo=$power_threshold%" || return 1
    fi
    if ! read_battery; then log 'ERROR no se pudo consultar pmset'; return 1; fi
    log "INFO batería=$percent% fuente=$power" || return 1

    # Histéresis: enchufar con poca carga no habilita otro aviso.
    if [ "$percent" -ge "$rearm_level" ]; then
        notified=0; low_done=0; next_notice=0; next_power=0
        low_notice_pending=0; next_low_notice=0
        save_state || return 1
    fi
    [ "$power" = battery ] || return 0

    if [ "$percent" -le "$alert_threshold" ] && [ "$notified" -eq 0 ] && [ "$now" -ge "$next_notice" ]; then
        next_notice=$((now + 900))
        save_state || return 1
        if result=$(notify "Batería al $percent %. Conecta el cargador." 2>&1); then
            notified=1
            save_state || return 1
            log "INFO aviso enviado al sistema ($percent%)" || return 1
        else
            log "ERROR notificación: $result; reintento en 15 minutos" || return 1
        fi
    fi

    if [ "$percent" -le "$power_threshold" ] && [ "$low_done" -eq 0 ] && [ "$now" -ge "$next_power" ]; then
        next_power=$((now + 900))
        save_state || return 1
        if ! current=$(low_power_value 2>&1); then
            log "ERROR consulta de bajo consumo: $current; reintento en 15 minutos"
            return 1
        fi
        if [ "$current" = 1 ]; then
            low_done=1
            save_state || return 1
            log 'INFO bajo consumo ya activo para batería' || return 1
        elif result=$(enable_low_power 2>&1); then
            if current=$(low_power_value 2>&1) && [ "$current" = 1 ]; then
                low_done=1
                low_notice_pending=1; next_low_notice=0
                # Persistir la activación antes del aviso: un fallo del aviso no repite pmset.
                save_state || return 1
                log 'INFO bajo consumo activado y verificado para batería' || return 1
            else
                log "ERROR pmset terminó sin confirmar activación: $current" || return 1
            fi
        else
            log "ERROR activación no autorizada o fallida: $result; reintento en 15 minutos" || return 1
        fi
        save_state || return 1
    fi

    if [ "$low_notice_pending" -eq 1 ] && [ "$now" -ge "$next_low_notice" ]; then
        next_low_notice=$((now + 900))
        save_state || return 1
        if ! current=$(low_power_value 2>&1); then
            log "ERROR verificación para aviso de bajo consumo: $current; reintento en 15 minutos"
            return 1
        fi
        if [ "$current" = 0 ]; then
            low_notice_pending=0; next_low_notice=0
            save_state || return 1
            log 'INFO aviso de activación descartado: el bajo consumo fue desactivado' || return 1
        elif result=$(notify 'Modo de bajo consumo activado para uso con batería.' 2>&1); then
            low_notice_pending=0; next_low_notice=0
            save_state || return 1
            log 'INFO aviso de activación de bajo consumo enviado al sistema' || return 1
        else
            log "ERROR aviso de activación de bajo consumo: $result; reintento en 15 minutos" || return 1
        fi
    fi
}

main() {
    local mode=${1:---check} self status
    case "$mode" in --check|--locked|--dry-run|--test-notification|--show-settings|--configure|--configure-locked) ;; *)
        printf 'Uso: %s [--check|--dry-run|--test-notification|--show-settings|--configure AVISO AHORRO [MINUTOS]]\n' "$0" >&2; return 2 ;;
    esac
    case "$mode" in
        --configure|--configure-locked)
            { [ "$#" -eq 3 ] || [ "$#" -eq 4 ]; } || return 2
            validate_thresholds "$2" "$3" || return 2
            if [ "$#" -eq 4 ]; then validate_interval "$4" || return 2; fi ;;
        *) [ "$#" -le 1 ] || return 2 ;;
    esac
    [ "$(/usr/bin/uname -s)" = Darwin ] || { printf 'Se requiere macOS\n' >&2; return 1; }
    [ "$EUID" -ne 0 ] || { printf 'Ejecuta el monitor como usuario, sin sudo\n' >&2; return 1; }
    data_dir="$HOME/Library/Application Support/MacBatteryMonitor"
    if [ "$mode" = --show-settings ]; then
        load_settings || return 1
        printf 'Aviso: %s%%; bajo consumo: %s%%; intervalo: %s min; rearme: %s%%.\n' "$alert_threshold" "$power_threshold" "$interval_minutes" "$rearm_level"
        return 0
    fi
    if [ "$mode" = --dry-run ]; then
        load_settings || return 1
        read_battery || return 1
        printf 'Batería: %s%%; fuente: %s. Aviso si <=%s%%; bajo consumo si <=%s%%.\n' "$percent" "$power" "$alert_threshold" "$power_threshold"
        printf 'Intervalo configurado: %s minuto(s).\n' "$interval_minutes"
        printf 'Simulación: no se modifican estado, logs ni ajustes de energía.\n'
        return 0
    fi
    if [ "$mode" = --test-notification ]; then notify 'Prueba del monitor de batería.'; return $?; fi
    state_file="$data_dir/state"
    log_file="$HOME/Library/Logs/MacBatteryMonitor/monitor.log"
    /bin/mkdir -p "$data_dir" "${log_file%/*}" || return 1
    if [ "$mode" = --configure-locked ]; then
        apply_settings "$2" "$3" "${4:-}"
        return $?
    fi
    if [ "$mode" != --locked ]; then
        self="$(cd -- "$(/usr/bin/dirname -- "$0")" && pwd)/$(/usr/bin/basename -- "$0")"
        if [ "$mode" = --configure ]; then
            shift
            /usr/bin/lockf -k -t 10 "$data_dir/check.lock" /bin/bash "$self" --configure-locked "$@"
            return $?
        fi
        /usr/bin/lockf -k -s -t 0 "$data_dir/check.lock" /bin/bash "$self" --locked
        status=$?
        # EX_TEMPFAIL significa que ya hay otra comprobación en curso.
        [ "$status" -ne 75 ] || return 0
        return "$status"
    fi
    if check_once 2>> "$log_file"; then
        return 0
    else
        log 'ERROR comprobación incompleta; revisar el registro y permisos de los archivos' || true
        return 1
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -u
    set -o pipefail
    main "$@"
fi
