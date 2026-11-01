# Historial de cambios

## 0.5.0 — 2026-10-31

- Aviso cuando el monitor activa y verifica el modo de bajo consumo.
- Avisos de activación persistentes y sin repeticiones, con reintentos separados del cambio de energía.
- Cancelación del aviso pendiente si el modo se desactiva manualmente o se rearma el ciclo al recargar.
- Migración de estados anteriores sin notificaciones retrospectivas.

## 0.4.0 — 2026-10-31

- Intervalo entre comprobaciones configurable de 1 a 120 minutos, con 10 por defecto.
- Selector de tiempo y guardado de los tres ajustes desde la app y por Terminal.
- Actualización y recarga del LaunchAgent al cambiar el intervalo, con recuperación ante fallos de launchctl.
- Compatibilidad con preferencias anteriores y conservación del estado de avisos al cambiar solo el tiempo.
- Protección para actualizar un motor anterior antes de guardar preferencias incompatibles.

## 0.3.0 — 2026-10-31

- Selectores independientes para el porcentaje de aviso y de bajo consumo (1–99 %).
- Preferencias persistentes desde la app y por Terminal, sin permisos de administrador.
- Rearme adaptado a los porcentajes y migración del estado anterior sin duplicar acciones completadas.
- Validación de entradas, guardado atómico y conservación de preferencias al actualizar.

## 0.2.0 — 2026-10-31

- App nativa de macOS con instalación y gestión del monitor.
- Notificaciones nativas para instalaciones realizadas desde la app.
- Paquetes `.dmg` y `.zip`, firma local y checksums SHA-256.
- Estructura de repositorio, CI, guías y portada con la imagen del proyecto.
- Conserva los accesos por Terminal de la versión anterior.

## 0.1.0 — 2026-10-31

- Monitor Bash con launchd y comprobaciones cada 10 minutos.
- Aviso al 30 %, bajo consumo al 20 % y estado persistente.
- Regla de autorización opcional y limitada, logs rotativos y desinstalación.
