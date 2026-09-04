# TokenWatch Mac

**Un hub nativo para macOS, ligero y de bajo consumo, pensado para permanecer abierto todo el tiempo.** Detecta en modo de solo lectura los datos locales estándar de Codex, Claude Code, Antigravity y OpenCode y unifica uso de hoy / 7 días / 30 días / histórico, tendencias por modelo/proyecto y cuotas.

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · **Español**

## Diseñado para estar siempre activo

Índice incremental persistente para Codex, eventos FSEvents sobre rutas autorizadas, concurrencia limitada, deduplicación de snapshots y sincronización remota latest-wins. Así evita volver a analizar todos los logs y reduce escrituras innecesarias.

Medición con ~810 MB de historial de Codex (2026-09-04): colección en frío **3,23 s / ~127 MiB**, colección incremental con índice **0,86 s / ~34 MiB**, sin cambios **0,82 s / ~34 MiB**. Son picos del proceso de colección, no el RSS permanente de la app.

## Privacidad

TokenWatch no guarda prompts, respuestas, argumentos de herramientas, rutas completas de proyectos ni credenciales del proveedor en sus snapshots. CloudKit conserva únicamente el último sobre cifrado de extremo a extremo en la base privada del usuario.

## Instalación

Descarga el DMG desde GitHub Releases. El DMG Preview actual usa firma ad-hoc, no está notarizado y utiliza entitlements local-only, por lo que la sincronización remota CloudKit está desactivada. La versión pública estable deberá usar Developer ID y notarización de Apple.

```sh
Scripts/bootstrap
Scripts/verify
Scripts/build-mac-dmg
```

Se añadirá una captura real del dashboard antes de la versión estable. Sin un archivo LICENSE explícito no se concede una licencia de código abierto.
