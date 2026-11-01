# Desarrollo y distribución

## Requisitos y comandos

macOS 15+, herramientas de línea de comandos de Xcode y Swift. No se utiliza Swift Package Manager ni se descargan librerías. La interfaz usa AppKit y UserNotifications del sistema; el trabajo periódico sigue en Bash.

```bash
make test
make build
make check
make package
```

`make check` valida sintaxis Bash, porcentajes e intervalo configurables, deduplicación, migración de estado, reintentos, instalación en un HOME temporal, recarga y recuperación ante errores de launchd, bloqueo, plist, firma del bundle y recursos. Ejecuta además `--self-test` de la app, que verifica el modelo de ajustes sin abrir ventanas, solicitar permisos ni enviar avisos. En las pruebas de instalación y recarga, `launchctl` se simula: no se registran servicios reales.

Las pruebas automáticas no verifican la entrega visual de notificaciones, los diálogos de autenticación ni un cambio real de energía. Para esos casos, abre la app en una sesión de prueba, instala el monitor y usa Probar aviso. Revisa los avisos con Concentración y Notificaciones configurados. Los cambios administrativos solo se realizan desde el botón correspondiente después de la explicación.

Para revisar la interfaz sin instalar tareas ni consultar la batería:

```bash
'build/Mac Battery Monitor.app/Contents/MacOS/MacBatteryMonitor' --preview docs/assets/app-preview.png
```

Este modo abre brevemente la ventana, guarda una vista de revisión y sale. No representa el estado de una instalación real.

## Arquitectura

- `Sources/MacBatteryMonitor/main.swift`: ventana de gestión y modo de notificaciones breves. La ventana no tiene un temporizador de sondeo; actualiza el estado al abrirse, activarse o pulsar Actualizar.
- `scripts/battery-monitor.sh`: lee batería y preferencias, conserva estado, evita avisos repetidos y maneja los reintentos. `--configure AVISO AHORRO [MINUTOS]` valida y guarda los ajustes, actualiza el plist y recarga una tarea ya registrada si cambia su intervalo. Ante un error de recarga intenta restaurar los archivos y la tarea originales. Se utiliza el bloqueo del monitor para evitar una comprobación durante el cambio. `--show-settings` permite consultar los ajustes. El estado v2 conserva los últimos umbrales aplicados para rearmar solo las acciones cuyo porcentaje cambió y admite el estado v1 de la versión anterior.
- `scripts/install.sh`: lee los ajustes con el parser del monitor e instala el LaunchAgent con `StartInterval = minutos × 60`. Con `--app-bundle RUTA` incorpora una copia estable del bundle en Application Support para emitir avisos aunque se mueva la app original.
- `scripts/power-permission.sh`: muestra, instala o retira la regla limitada de sudoers. Solo `install` y `remove` requieren root; la app los invoca después de una explicación y confirmación.
- `scripts/uninstall.sh`: descarga la tarea y elimina configuración, estado, script y copia de notificaciones; conserva logs salvo con `--purge`.

La copia de notificaciones utiliza el mismo identificador de bundle que la app. La app solicita autorización al instalar. Concentración o una denegación del usuario pueden impedir la entrega. El código de éxito confirma aceptación por el servicio del sistema, no lectura por la persona.

Las preferencias v2 tienen el formato `v2 AVISO AHORRO MINUTOS`. Se sigue leyendo `v1 AVISO AHORRO`, con un intervalo de 10 minutos. Este versionado es independiente del formato del archivo `state`. El comando anterior de dos porcentajes conserva el intervalo existente y no recarga la tarea si el tiempo no cambió. Los límites son 1–99 para porcentajes y 1–120 para minutos, tanto en Swift como en Bash.

La imagen original se copia sin cambios al README y al bundle. El build crea tamaños técnicos para el icono `.icns`; no cambia el original. Mantén la atribución o permisos de la imagen si publicas una copia del proyecto.

## Firma y notarización

Por defecto, `build.sh` firma ad hoc con `codesign --sign -`. Esto sirve para la compilación local; no acredita al desarrollador frente a Gatekeeper.

Para una distribución pública con tu identidad Developer ID:

```bash
CODESIGN_IDENTITY='Developer ID Application: TU IDENTIDAD' make package
```

El script activa hardened runtime y timestamp cuando se especifica esa identidad. Luego debes enviar el ZIP a Apple, esperar la aprobación, grapar el ticket a la app y volver a empaquetarla. Los siguientes comandos transmiten el paquete a Apple y requieren credenciales propias configuradas; no los ejecuta el build ni CI:

```bash
xcrun notarytool submit dist/Mac-Battery-Monitor-0.4.0-arm64.zip --keychain-profile TU_PERFIL --wait
xcrun stapler staple 'build/Mac Battery Monitor.app'
# Empaqueta la app grapada sin volver a compilarla ni firmarla:
/bin/bash scripts/package.sh --existing-app
```

No guardes certificados ni claves en el repositorio. No se solicitan credenciales para la compilación local. Consulta la [documentación de notarización de Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## GitHub

`.github/workflows/ci.yml` ejecuta las comprobaciones y empaqueta la app en macOS. Los artefactos de CI permiten revisarla; el workflow no publica releases ni hace cambios en tu cuenta de GitHub. Usa tags y adjunta los archivos de `dist/` cuando decidas publicar una versión. Los permisos del workflow son de lectura sobre el repositorio.

El repositorio no contiene un remoto preconfigurado. Crea el repositorio de GitHub con el nombre y visibilidad que prefieras, y conecta después el remoto. No hace falta publicar los archivos generados dentro del historial de Git.
