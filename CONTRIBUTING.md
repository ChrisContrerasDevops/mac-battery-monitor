# Contribuir

Usa macOS 15 o posterior con las Command Line Tools de Xcode.

1. Crea una rama para el cambio.
2. Mantén el motor compatible con el Bash de macOS, sin paquetes externos.
3. Ejecuta `make check` y, para cambios de distribución, `make package`.
4. Describe el comportamiento que cambia y cómo lo verificaste.

Las pruebas deben usar directorios temporales y simular `launchctl`. No deben instalar reglas de sudoers, enviar avisos reales ni modificar ajustes de energía. Los cambios de interfaz o permisos necesitan una comprobación manual separada y documentada.

Conserva el intervalo predeterminado de 10 minutos. Antes de cualquier operación administrativa, explica al usuario el motivo y el alcance concreto del permiso.
