#!/bin/bash
# Simulaciones: no invocan sudo, notificaciones reales ni cambios de energía.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$repo_root/scripts"
source "$source_dir/battery-monitor.sh"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mac-battery-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
data_dir="$test_dir"
state_file="$data_dir/state"
log_file="$data_dir/monitor.log"
passed=0
assert_equal() {
    if [ "$1" != "$2" ]; then
        printf 'FALLO %s: esperado <%s>, recibido <%s>\n' "$3" "$2" "$1" >&2; exit 1
    fi
    passed=$((passed + 1))
}

parse_battery "Now drawing from 'Battery Power'
 -InternalBattery-0 (id=123) 30%; discharging; 1:00 remaining present: true"
assert_equal "$percent:$power" 30:battery 'lectura de batería'
parse_battery "Now drawing from 'AC Power'
 -InternalBattery-0 (id=123) 005%; discharging; (no estimate) present: true"
assert_equal "$percent:$power" 5:ac 'fuente AC prevalece sobre discharging'
for invalid in \
    "Now drawing from 'AC Power'" \
    "Now drawing from 'UPS Power'
 -InternalBattery-0 30%; discharging" \
    "Now drawing from 'Battery Power'
 -InternalBattery-0 101%; discharging" \
    "Now drawing from 'Battery Power'
 -UPS-0 20%; discharging"; do
    if parse_battery "$invalid" 2>/dev/null; then echo 'Se aceptó lectura inválida' >&2; exit 1; fi
    passed=$((passed + 1))
done

# Sustituir las tres operaciones con efectos externos, conservando la lógica real.
sample_percent=31; sample_power=battery; notify_fail=0; power_fail=0; verify_fail=0
read_battery() { percent=$sample_percent; power=$sample_power; }
notify() {
    echo attempt >> "$test_dir/notices"
    [ "$notify_fail" -eq 0 ] || { echo 'Notificación denegada' >&2; return 1; }
}
low_power_value() { cat "$test_dir/mode"; }
enable_low_power() {
    echo attempt >> "$test_dir/power-attempts"
    [ "$power_fail" -eq 0 ] || { echo 'Permiso denegado' >&2; return 1; }
    [ "$verify_fail" -eq 0 ] || return 0
    echo 1 > "$test_dir/mode"
}
count() { if [ -f "$1" ]; then /usr/bin/awk 'END {print NR}' "$1"; else echo 0; fi; }
echo 0 > "$test_dir/mode"
check_once
assert_equal "$(count "$test_dir/notices")" 0 '31% no avisa'
sample_percent=30; check_once; check_once
assert_equal "$(count "$test_dir/notices")" 1 '30% avisa una vez con estado persistente'
sample_percent=19; check_once; check_once
assert_equal "$(count "$test_dir/power-attempts")" 1 'salto a 19% activa y verifica una vez'
assert_equal "$low_done" 1 'activación confirmada'
sample_power=ac; check_once; sample_power=battery; check_once
assert_equal "$(count "$test_dir/notices")" 1 'reconectar con poca carga no rearma'
sample_percent=35; check_once
assert_equal "$notified" 1 '35% mantiene histéresis'
sample_percent=36; check_once
assert_equal "$notified:$low_done" 0:0 '36% rearma ambos umbrales'
sample_percent=18; check_once
assert_equal "$(count "$test_dir/notices")" 2 'primer chequeo bajo ambos umbrales'
assert_equal "$(count "$test_dir/power-attempts")" 1 'ya activo no ejecuta pmset'

# Sin autorización, enfriar reintentos; un nuevo ciclo sí vuelve a intentar.
sample_percent=50; check_once
echo 0 > "$test_dir/mode"
power_fail=1; sample_percent=20; check_once; check_once
assert_equal "$low_done" 0 'denegación no marca éxito'
assert_equal "$(count "$test_dir/power-attempts")" 2 'denegación no se repite en comprobaciones consecutivas'
next_power=0; save_state; power_fail=0; check_once
assert_equal "$low_done" 1 'recuperación tras autorizar'

# Notificación fallida se reintenta con espera, independiente de bajo consumo.
sample_percent=50; check_once
notify_fail=1; sample_percent=29; check_once; check_once
assert_equal "$notified" 0 'error de aviso no marca envío'
assert_equal "$(count "$test_dir/notices")" 4 'error de aviso se enfría'
next_notice=0; save_state; notify_fail=0; check_once
assert_equal "$notified" 1 'recuperación de aviso'

sample_percent=50; check_once
echo 0 > "$test_dir/mode"
sample_percent=20; verify_fail=1; check_once
assert_equal "$low_done" 0 'salida cero sin cambio no se considera éxito'

sample_percent=50; check_once
sample_power=ac; sample_percent=10; check_once
assert_equal "$notified:$low_done" 0:0 'enchufado no activa ni notifica'

printf 'v1 0 0 $(touch hacked) 0\n' > "$state_file"
if load_state 2>/dev/null; then echo 'Estado corrupto aceptado' >&2; exit 1; fi
assert_equal "$(test -f hacked && echo yes || echo no)" no 'estado nunca se ejecuta como shell'

# Umbrales personalizados, independientes y cambios sin duplicar la otra acción.
rm -f "$state_file"
sample_power=battery; sample_percent=46; notify_fail=0; power_fail=0; verify_fail=0
before_notices=$(count "$test_dir/notices")
before_power=$(count "$test_dir/power-attempts")
save_settings 45 25
check_once
assert_equal "$alert_threshold:$power_threshold:$rearm_level" 45:25:51 'carga preferencias guardadas'
assert_equal "$(count "$test_dir/notices")" "$before_notices" '46% no avisa con límite 45%'
sample_percent=45; check_once; check_once
assert_equal "$(count "$test_dir/notices")" "$((before_notices + 1))" 'aviso personalizado sin repetición'
echo 0 > "$test_dir/mode"
sample_percent=24; check_once; check_once
assert_equal "$(count "$test_dir/power-attempts")" "$((before_power + 1))" 'bajo consumo personalizado sin repetición'
save_settings 50 25; check_once
assert_equal "$(count "$test_dir/notices")" "$((before_notices + 2))" 'cambiar aviso rearma su acción'
assert_equal "$(count "$test_dir/power-attempts")" "$((before_power + 1))" 'cambiar aviso conserva acción de ahorro'
echo 0 > "$test_dir/mode"
save_settings 50 30; check_once
assert_equal "$(count "$test_dir/notices")" "$((before_notices + 2))" 'cambiar ahorro no repite aviso'
assert_equal "$(count "$test_dir/power-attempts")" "$((before_power + 2))" 'cambiar ahorro rearma su acción'
save_settings 50 30; check_once
assert_equal "$(count "$test_dir/notices")" "$((before_notices + 2))" 'guardar los mismos valores conserva deduplicación'
sample_percent=55; check_once
assert_equal "$notified:$low_done" 1:1 'histéresis personalizada mantiene ambos estados'
sample_percent=56; check_once
assert_equal "$notified:$low_done" 0:0 'histéresis personalizada rearma ambos estados'

save_settings 20 60; sample_percent=50
echo 0 > "$test_dir/mode"
before_notices=$(count "$test_dir/notices")
check_once
assert_equal "$notified:$low_done" 0:1 'ahorro puede tener un umbral superior al aviso'
assert_equal "$(count "$test_dir/notices")" "$before_notices" 'ahorro independiente no envía aviso prematuro'
sample_percent=19; check_once
assert_equal "$(count "$test_dir/notices")" "$((before_notices + 1))" 'aviso inferior se dispara al cruzarlo'

save_settings 99 99; sample_percent=99; check_once; check_once
assert_equal "$rearm_level:$notified:$low_done" 100:1:1 '99% no queda rearmado continuamente'
sample_power=ac; sample_percent=100; check_once
assert_equal "$notified:$low_done" 0:0 '100% permite otro ciclo con umbrales altos'
save_settings 1 1; sample_power=battery; sample_percent=2; check_once
assert_equal "$notified:$low_done" 0:0 'umbral mínimo espera al 1%'
sample_percent=1; check_once
assert_equal "$notified:$low_done" 1:1 'umbral mínimo dispara ambas acciones'

before_notices=$(count "$test_dir/notices")
before_power=$(count "$test_dir/power-attempts")
for invalid in 'v1 0 20' 'v1 30 100' 'v1 3.5 20' 'v1 030 20' 'v1 30 20 extra' \
    'v2 30 20' 'v1 $(touch SETTINGS_HACKED) 20' $'v1 30\n20'; do
    printf '%s\n' "$invalid" > "$data_dir/settings"
    if check_once 2>/dev/null; then echo 'Se aceptó configuración inválida' >&2; exit 1; fi
    passed=$((passed + 1))
done
assert_equal "$(count "$test_dir/notices"):$(count "$test_dir/power-attempts")" \
    "$before_notices:$before_power" 'configuración inválida no ejecuta acciones'
assert_equal "$(test -f SETTINGS_HACKED && echo yes || echo no)" no 'configuración nunca se ejecuta como shell'

# Un estado de la app anterior se migra conservando sus acciones completadas.
save_settings 30 20
printf 'v1 1 1 0 0\n' > "$state_file"
sample_percent=19; check_once
assert_equal "$(count "$test_dir/notices"):$(count "$test_dir/power-attempts")" \
    "$before_notices:$before_power" 'migración conserva deduplicación de versión anterior'
save_settings 40 20; check_once
assert_equal "$(count "$test_dir/notices")" "$((before_notices + 1))" 'migración aplica nuevo aviso'
assert_equal "$(count "$test_dir/power-attempts")" "$before_power" 'migración conserva ahorro sin cambios'
save_settings 40 20 37; check_once
assert_equal "$interval_minutes" 37 'lee intervalo personalizado'
assert_equal "$(count "$test_dir/notices"):$(count "$test_dir/power-attempts")" \
    "$((before_notices + 1)):$before_power" 'cambiar solo intervalo no repite acciones'
printf 'v1 40 20\n' > "$data_dir/settings"
load_settings
assert_equal "$interval_minutes" 10 'preferencias anteriores conservan diez minutos'
for invalid in 'v2 30 20 0' 'v2 30 20 121' 'v2 30 20 1.5' 'v2 30 20 01' 'v2 30 20 5 extra'; do
    printf '%s\n' "$invalid" > "$data_dir/settings"
    if load_settings 2>/dev/null; then echo 'Se aceptó intervalo inválido' >&2; exit 1; fi
    passed=$((passed + 1))
done

# Rotación real y acotada de logs.
dd if=/dev/zero of="$log_file" bs=262144 count=1 2>/dev/null
log 'INFO prueba de rotación'
assert_equal "$(stat -f %z "$log_file.1")" 262144 'rotación a 256 KiB'

# Validar la regla real generada sin instalarla ni solicitar privilegios.
/bin/bash "$source_dir/power-permission.sh" show "$(id -u)" > "$test_dir/sudoers"
/usr/sbin/visudo -cf "$test_dir/sudoers" >/dev/null
passed=$((passed + 1))

# Instalación y desinstalación reales en HOME temporal; solo launchctl se simula.
# Así se valida el plist y las rutas con espacios, &, y caracteres Unicode.
export BATTERY_MONITOR_TEST_LAUNCHCTL_DIR="$test_dir/launchctl"
mkdir -p "$BATTERY_MONITOR_TEST_LAUNCHCTL_DIR"
launchctl() {
    local fixture="$BATTERY_MONITOR_TEST_LAUNCHCTL_DIR"
    case "$1" in
        print) case "$2" in gui/*/*) [ -f "$fixture/registered" ] ;; *) return 0 ;; esac ;;
        bootstrap)
            echo bootstrap >> "$fixture/calls"
            if [ -f "$fixture/fail-bootstrap" ]; then rm -f "$fixture/fail-bootstrap"; return 1; fi
            /usr/bin/plutil -lint "$3" >/dev/null || return 1
            /usr/bin/plutil -extract StartInterval raw "$3" > "$fixture/registered"
            ;;
        bootout)
            echo bootout >> "$fixture/calls"
            if [ -f "$fixture/fail-bootout" ]; then rm -f "$fixture/fail-bootout"; return 1; fi
            rm -f "$fixture/registered"
            ;;
        enable) return 0 ;;
        *) echo 'Invocación inesperada de launchctl' >&2; return 1 ;;
    esac
}
export -f launchctl
fake_home="$test_dir/Usuario prueba & ñ"
HOME="$fake_home" /bin/bash "$source_dir/battery-monitor.sh" --configure 42 18 15 >/dev/null
saved="$fake_home/Library/Application Support/MacBatteryMonitor/settings"
assert_equal "$(cat "$saved")" 'v2 42 18 15' 'CLI guarda porcentajes e intervalo antes de instalar'
assert_equal "$(stat -f %Lp "$saved")" 600 'preferencias con permisos privados'
if HOME="$fake_home" /bin/bash "$source_dir/battery-monitor.sh" --configure 0 101 >/dev/null 2>&1; then
    echo 'CLI aceptó porcentajes fuera de rango' >&2; exit 1
fi
assert_equal "$(cat "$saved")" 'v2 42 18 15' 'entrada CLI inválida conserva ajustes anteriores'
HOME="$fake_home" /bin/bash "$source_dir/install.sh" >/dev/null
assert_equal "$(cat "$saved")" 'v2 42 18 15' 'instalación conserva los ajustes elegidos'
assert_equal "$(HOME="$fake_home" /bin/bash "$source_dir/battery-monitor.sh" --show-settings)" \
    'Aviso: 42%; bajo consumo: 18%; intervalo: 15 min; rearme: 48%.' 'CLI muestra ajustes persistidos'
installed_plist="$fake_home/Library/LaunchAgents/local.mac-battery-monitor.plist"
assert_equal "$(/usr/bin/plutil -extract ProgramArguments.1 raw "$installed_plist")" \
    "$fake_home/Library/Application Support/MacBatteryMonitor/battery-monitor.sh" 'ruta escapada en plist'
assert_equal "$(/usr/bin/plutil -extract StartInterval raw "$installed_plist")" 900 'intervalo personalizado real del plist'
# Worker real, lectura real en modo sin efectos; HOME no toca la instalación del usuario.
dry_output=$(HOME="$fake_home" /bin/bash "$fake_home/Library/Application Support/MacBatteryMonitor/battery-monitor.sh" --dry-run)
case "$dry_output" in
    *'Aviso si <=42%; bajo consumo si <=18%.'*) passed=$((passed + 1)) ;;
    *) echo 'La simulación no usa los porcentajes guardados' >&2; exit 1 ;;
esac
assert_equal "$(test -f "${saved%/*}/state" && echo yes || echo no)" no 'simulación no crea estado'

# No escribir un formato nuevo mientras siga instalado un motor anterior.
installed_worker="${saved%/*}/battery-monitor.sh"
cp "$installed_worker" "$test_dir/worker-backup"
printf '# motor de otra versión\n' >> "$installed_worker"
if HOME="$fake_home" /bin/bash "$source_dir/battery-monitor.sh" --configure 42 18 8 >/dev/null 2>&1; then
    echo 'Se guardó configuración incompatible con el motor instalado' >&2; exit 1
fi
assert_equal "$(cat "$saved")" 'v2 42 18 15' 'motor anterior conserva ajustes hasta actualizar'
cp "$test_dir/worker-backup" "$installed_worker"

# Cambiar el tiempo recarga la tarea activa; cambiar solo porcentajes no lo hace.
printf 'v2 1 1 0 0 42 18\n' > "${saved%/*}/state"
HOME="$fake_home" /bin/bash "$source_dir/battery-monitor.sh" --configure 42 18 3 >/dev/null
assert_equal "$(/usr/bin/plutil -extract StartInterval raw "$installed_plist")" 180 'cambio de tiempo actualiza el plist'
assert_equal "$(cat "$BATTERY_MONITOR_TEST_LAUNCHCTL_DIR/registered")" 180 'tarea activa recibe el nuevo tiempo'
assert_equal "$(cat "${saved%/*}/state")" 'v2 1 1 0 0 42 18' 'cambio de tiempo conserva estado'
before_calls=$(count "$BATTERY_MONITOR_TEST_LAUNCHCTL_DIR/calls")
HOME="$fake_home" /bin/bash "$source_dir/battery-monitor.sh" --configure 43 18 >/dev/null
assert_equal "$(cat "$saved")" 'v2 43 18 3' 'comando anterior de dos porcentajes conserva tiempo'
assert_equal "$(count "$BATTERY_MONITOR_TEST_LAUNCHCTL_DIR/calls")" "$before_calls" 'porcentajes no recargan launchd'
HOME="$fake_home" /bin/bash "$source_dir/battery-monitor.sh" --configure 42 18 3 >/dev/null

for failure in bootstrap bootout; do
    touch "$BATTERY_MONITOR_TEST_LAUNCHCTL_DIR/fail-$failure"
    if HOME="$fake_home" /bin/bash "$source_dir/battery-monitor.sh" --configure 42 18 7 >/dev/null 2>&1; then
        echo 'No se propagó el error de launchctl' >&2; exit 1
    fi
    assert_equal "$(cat "$saved")" 'v2 42 18 3' "fallo de $failure restaura preferencias"
    assert_equal "$(/usr/bin/plutil -extract StartInterval raw "$installed_plist")" 180 "fallo de $failure restaura plist"
    assert_equal "$(cat "$BATTERY_MONITOR_TEST_LAUNCHCTL_DIR/registered")" 180 "fallo de $failure conserva tarea anterior"
done
for invalid in 0 121 -1 1.5 01 '$(touch INTERVAL_HACKED)'; do
    if HOME="$fake_home" /bin/bash "$source_dir/battery-monitor.sh" --configure 42 18 "$invalid" >/dev/null 2>&1; then
        echo 'CLI aceptó intervalo inválido' >&2; exit 1
    fi
    passed=$((passed + 1))
done
assert_equal "$(cat "$saved")" 'v2 42 18 3' 'intervalos inválidos no modifican preferencias'
rm -f "$BATTERY_MONITOR_TEST_LAUNCHCTL_DIR/registered"
before_calls=$(count "$BATTERY_MONITOR_TEST_LAUNCHCTL_DIR/calls")
HOME="$fake_home" /bin/bash "$source_dir/battery-monitor.sh" --configure 42 18 12 >/dev/null
assert_equal "$(count "$BATTERY_MONITOR_TEST_LAUNCHCTL_DIR/calls")" "$before_calls" 'guardar no reactiva una tarea detenida'
assert_equal "$(/usr/bin/plutil -extract StartInterval raw "$installed_plist")" 720 'tarea detenida guarda tiempo para el próximo inicio'
HOME="$fake_home" /bin/bash "$source_dir/install.sh" >/dev/null
assert_equal "$(cat "$BATTERY_MONITOR_TEST_LAUNCHCTL_DIR/registered")" 720 'reinstalación conserva intervalo'
HOME="$fake_home" /bin/bash "$source_dir/uninstall.sh" --purge >/dev/null
assert_equal "$(test -f "$installed_plist" && echo yes || echo no)" no 'desinstala plist'
assert_equal "$(test -d "$fake_home/Library/Application Support/MacBatteryMonitor" && echo yes || echo no)" no 'desinstala copia y estado'
assert_equal "$(test -f "$saved" && echo yes || echo no)" no 'desinstala preferencias'
unset -f launchctl
unset BATTERY_MONITOR_TEST_LAUNCHCTL_DIR

# El bloqueo nativo impide solapamientos y se libera al terminar el proceso.
/usr/bin/lockf -k -t 0 "$test_dir/exclusive.lock" /bin/bash -c \
    'echo ready > "$1"; /bin/sleep 1' bash "$test_dir/ready" &
lock_pid=$!
for attempt in {1..100}; do
    [ ! -f "$test_dir/ready" ] || break
    /bin/sleep 0.01
done
[ -f "$test_dir/ready" ] || { echo 'No comenzó la prueba del bloqueo' >&2; exit 1; }
if /usr/bin/lockf -k -s -t 0 "$test_dir/exclusive.lock" /usr/bin/true; then
    echo 'El bloqueo permitió un proceso concurrente' >&2; exit 1
else
    assert_equal "$?" 75 'bloqueo rechaza ejecución concurrente'
fi
wait "$lock_pid"
/usr/bin/lockf -k -t 0 "$test_dir/exclusive.lock" /usr/bin/true
passed=$((passed + 1))

printf 'Correcto: %s verificaciones. Sin cambios en energía ni avisos reales.\n' "$passed"
