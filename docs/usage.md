# Guía del monitor por Terminal

Para instalar y gestionar el monitor con una ventana nativa, usa la [app descrita en el README](../README.md). Esta guía conserva la alternativa por Terminal y los detalles de funcionamiento. Se requiere macOS 15 o posterior.

Solución en Bash con herramientas de macOS, sin Python, Homebrew ni paquetes externos. Consulta con `launchd` cada **1 a 120 minutos**, según el valor elegido; por defecto son **10 minutos**. Puedes cerrar VS Code y Terminal. El instalador comprueba las herramientas necesarias, incluido `lockf` para impedir ejecuciones simultáneas.

## Comportamiento

- **Umbral de aviso o menos, usando batería:** envía una notificación. Por defecto es **30 %**. También funciona si una lectura salta de un lado al otro del umbral o la primera ejecución ya ocurre por debajo.
- **Umbral de ahorro o menos, usando batería:** intenta activar `pmset -b lowpowermode 1` si tiene la autorización descrita más abajo. Por defecto es **20 %**. Comprueba después que el ajuste haya cambiado.
- **Conectado a corriente:** no avisa ni activa bajo consumo, aunque `pmset` muestre `discharging` por carga optimizada u otra condición.
- Guarda el estado y los porcentajes entre ejecuciones, reinicios y actualizaciones. Cada acción completada se realiza una vez por ciclo. El ciclo se rearma al alcanzar `mínimo(100, máximo(aviso, ahorro) + 6)`; con los valores predeterminados es **36 %**. Enchufar y desenchufar con poca carga no genera otro aviso.
- Los fallos de notificación o activación se registran y esperan al menos **15 minutos** antes de reintentarse en una comprobación posterior (normalmente a los **20 minutos**, con el intervalo de 10 minutos). Si el ajuste ya está activo, no vuelve a aplicarlo. Si lo desactivas manualmente después de un éxito, respeta ese cambio hasta otro ciclo.
- No desactiva automáticamente el bajo consumo: `pmset -b` cambia un ajuste persistente para uso con batería. Al recargar seguirá configurado para futuras descargas hasta que lo cambies en Ajustes del Sistema. El perfil del cargador no cambia.

Un `LaunchAgent` trabaja mientras tu usuario tiene una sesión gráfica iniciada, también con la pantalla bloqueada. No necesita un editor abierto. No hace comprobaciones durante reposo ni con el equipo apagado; al despertar continúa con los intervalos de `launchd`. La detección de un umbral puede demorarse aproximadamente el intervalo elegido mientras el equipo está despierto, sujeta a planificación; el reposo puede prolongar esa demora. No impide que el Mac duerma ni programa despertares.

## Elegir porcentajes y tiempo entre comprobaciones

En la app, usa **Personalizar monitor** y pulsa **Guardar ajustes**. Los dos porcentajes son independientes y admiten enteros entre **1 y 99**: puedes, por ejemplo, activar el ahorro al 60 % y recibir el aviso al 20 %. En **Comprobar cada**, elige un intervalo entero de **1 a 120 minutos**. Guardar estos valores no requiere administrador; activar el modo de energía sigue necesitando la autorización opcional.

Por Terminal, indica aviso, ahorro y minutos, en ese orden:

```bash
/bin/bash battery-monitor.sh --configure 40 25 15
/bin/bash battery-monitor.sh --show-settings
```

Los porcentajes se aplican en la siguiente comprobación, sin mantener la app abierta. El intervalo se convierte a segundos y se guarda en `StartInterval` del plist. Si la tarea está registrada, se recarga con `launchctl`; esto puede provocar una comprobación inmediata. Si está detenida, solo se actualiza el plist para el siguiente inicio. Un error al recargar intenta restaurar preferencias, plist y registro anteriores; si la recuperación también falla, se informa de que debes reinstalar el monitor.

Los ajustes se guardan en `~/Library/Application Support/MacBatteryMonitor/settings` con permisos privados y reemplazo atómico, bajo el mismo bloqueo que utiliza el monitor. No necesitas editar el archivo a mano. Si no existe, se usan 30 %, 20 % y 10 minutos. Las preferencias antiguas mantienen sus porcentajes y reciben el intervalo de 10 minutos. El comando de dos valores `--configure 40 25` conserva el intervalo que ya esté guardado.

Cambiar un umbral rearma solo su acción y permite un nuevo intento si la batería ya está por debajo del nuevo valor; el otro umbral mantiene su estado. Cambiar solo el intervalo o guardar los mismos porcentajes no repite acciones ni borra las esperas de reintento. El estado de la versión anterior se migra conservando los avisos ya completados. Si tienes una versión anterior a 0.4.0 instalada, actualízala desde la app o vuelve a ejecutar `install.sh` para incorporar el motor que lee estos ajustes.

La app y el comando de configuración comprueban que el motor instalado corresponda a la versión actual antes de guardar; si es distinto, conservan los ajustes y piden actualizar primero. Los valores seleccionados en la ventana se mantienen mientras actualizas para que puedas guardarlos después.

Una configuración inválida detiene las acciones y registra el error. Selecciona y guarda valores válidos desde la app o con `--configure AVISO AHORRO MINUTOS` para corregirla. El modo `--dry-run` muestra los límites y el intervalo configurados. Los reintentos esperan al menos 15 minutos y se realizan en una comprobación posterior: con un intervalo de 30 minutos, por ejemplo, el reintento llegará a los 30 minutos o después.

## Instalación del monitor, sin administrador

Desde Terminal:

```bash
cd mac-battery-monitor
/bin/bash tests.sh
/bin/bash battery-monitor.sh --dry-run
/bin/bash install.sh
/bin/bash battery-monitor.sh --test-notification
```

La prueba final envía un aviso real independiente del estado de los umbrales. Revisa Ajustes del Sistema → Notificaciones y permite los avisos para la aplicación a la que macOS atribuya el script. Concentración y las preferencias de notificación pueden ocultarlos: que `osascript` termine correctamente significa que macOS aceptó la solicitud, no que hayas visto el aviso. No se necesita Accesibilidad ni Acceso total al disco para este diseño. Si macOS solicita permitir la actividad en segundo plano, habilita este agente en Ajustes del Sistema → General → Ítems de inicio y extensiones.

Se instala una copia fuera de Documentos para evitar que la ejecución periódica dependa de permisos de acceso a esa carpeta:

| Elemento | Ubicación |
| --- | --- |
| Tarea de usuario | `~/Library/LaunchAgents/local.mac-battery-monitor.plist` |
| Script, configuración, estado y bloqueo | `~/Library/Application Support/MacBatteryMonitor/` |
| Logs | `~/Library/Logs/MacBatteryMonitor/monitor.log` |

El estado es texto validado, nunca se interpreta como código. Se escribe mediante reemplazo atómico con permisos privados. `lockf` libera el bloqueo automáticamente si termina el proceso. Los logs usan hora UTC, registran cada lectura y los errores, y rotan a 256 KiB con tres archivos anteriores (aproximadamente 1 MiB total).

## Autorización opcional para activar bajo consumo

**Por qué requiere administrador:** el manual local `man pmset` establece que modificar ajustes de energía requiere `root`. El agente se ejecuta como tu usuario. Sin autorización, los avisos funcionan y el intento de activación se registra como fallido; no aparece ningún diálogo de contraseña ni se bloquea el proceso.

Para permitir la activación automática, la herramienta siguiente instala una regla en `/etc/sudoers.d`, propiedad de `root` con modo `0440`. Esto requiere administrador porque cambia la política de `sudo`. La regla permite **únicamente a tu UID** ejecutar sin contraseña este comando y sus argumentos exactos:

```text
/usr/bin/pmset -b lowpowermode 1
```

No autoriza scripts, un shell, otros argumentos ni otros cambios de energía. El permiso también estará disponible para otros procesos de tu mismo usuario, limitado a ese comando. Se valida con `visudo` antes y después de instalar; no se modifica el archivo principal `sudoers`. La instalación requiere que la política del equipo incluya `/etc/sudoers.d`; la consulta final permite comprobarlo. Una política corporativa puede impedir esta autorización o el cambio de energía.

Puedes previsualizar la regla sin privilegios ni modificaciones:

```bash
/bin/bash power-permission.sh show "$(/usr/bin/id -u)"
```

**Solo si quieres habilitar ese permiso**, ejecuta tú este comando, después de revisar el script:

```bash
sudo /bin/bash power-permission.sh install "$(/usr/bin/id -u)"
```

Para comprobar que `sudo` reconoce la regla sin cambiar la energía:

```bash
sudo -n -l /usr/bin/pmset -b lowpowermode 1
```

El monitor usa `sudo -n -k`: nunca pide contraseña ni aprovecha autorizaciones temporales guardadas por otra sesión. No relaja SIP ni modifica TCC. Si hubo un intento fallido, el siguiente llegará en la primera comprobación posterior a su espera de 15 minutos. No ejecutes el monitor ni su instalador con `sudo`.

## Inspección y diagnóstico

```bash
/bin/launchctl print "gui/$(/usr/bin/id -u)/local.mac-battery-monitor"
/usr/bin/tail -n 50 "$HOME/Library/Logs/MacBatteryMonitor/monitor.log"
/usr/bin/pmset -g batt
/usr/bin/pmset -g custom
```

En la salida de `pmset -g custom`, busca `lowpowermode 1` dentro de **Battery Power**. Un equipo sin batería interna o sin ese ajuste compatible devuelve un error registrado, sin interpretar otro porcentaje como batería del portátil. Una lectura inválida no dispara acciones.

Para comprobar inmediatamente el monitor instalado:

```bash
/bin/bash "$HOME/Library/Application Support/MacBatteryMonitor/battery-monitor.sh" --check
```

`--check` tiene efectos reales si se cumplen los umbrales. `--dry-run` solo lee batería y muestra los umbrales: no escribe estado ni logs, no notifica ni cambia energía. El modo de simulación no garantiza que existan permisos de activación.

Si aparece un estado inválido, el monitor se detiene sin ejecutar acciones. Después de inspeccionar su contenido, puedes quitar únicamente el archivo `state` para reiniciar los ciclos; esto permite que llegue un nuevo aviso si la batería sigue baja. Si falta un permiso de escritura o se llena el disco, la comprobación devuelve un código de error; revisa también `last exit code` en `launchctl print`. Ningún script puede registrar en disco cuando el propio disco impide escribir.

Para actualizar, vuelve a ejecutar `install.sh` desde esta carpeta; sustituye la copia instalada y conserva el estado y los porcentajes. La solicitud de notificación y el guardado de estado no forman una transacción del sistema: un cierre abrupto entre ambos puede producir un reintento posterior. Las pruebas cubren la deduplicación normal y los reintentos, sin prometer entrega exactamente una vez frente a fallos del sistema.

## Desinstalación

Como tu usuario, sin administrador:

```bash
/bin/bash uninstall.sh
# O eliminar también los logs:
/bin/bash uninstall.sh --purge
```

Descarga el agente y elimina su plist, copia instalada, estado y porcentajes guardados. Conserva el proyecto fuente. Si instalaste la autorización opcional, retírala también. **Esta operación requiere administrador porque elimina la regla de `/etc/sudoers.d`:**

```bash
sudo /bin/bash power-permission.sh remove "$(/usr/bin/id -u)"
```

La desinstalación conserva el ajuste de energía vigente. Para desactivar el bajo consumo, usa Ajustes del Sistema → Batería y selecciona el modo automático para batería; la regla opcional no concede autorización para desactivarlo mediante `sudo` sin contraseña.

## Referencias

- [Apple: administrar scripts con launchd](https://support.apple.com/en-asia/guide/terminal/apdc6c1077b-5d5d-4d35-9c19-60f2397b2369/mac).
- [Apple: modos de energía del Mac](https://support.apple.com/en-us/101613).
- Manuales locales: `man pmset`, `man launchd.plist`, `man launchctl`, `man lockf`, `man sudoers`.

Se usa el manual local para el comportamiento actual de `StartInterval`: los intervalos durante reposo pueden perderse. No se depende de la promesa de recuperación inmediata al despertar que aparece en documentación antigua de `launchd`.
