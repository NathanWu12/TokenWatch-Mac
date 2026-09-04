# TokenWatch Mac

**Un hub nativo para macOS, ligero y de bajo consumo, diseñado para permanecer activo de forma continua.** Detecta en modo de solo lectura los datos locales estándar de Codex, Claude Code, Antigravity y OpenCode y unifica el uso de hoy / 7 días / 30 días / histórico, las tendencias por modelo y proyecto y las cuotas.

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · **Español**

## Diseñado para funcionar de forma continua

El índice incremental persistente de Codex solo lee los bytes nuevos. FSEvents detecta cambios en directorios Provider autorizados, la concurrencia de los recolectores está limitada, se evitan escrituras innecesarias en disco / LAN / CloudKit y la sincronización remota usa una estrategia latest-wins para impedir la acumulación de snapshots antiguos. La aplicación está implementada de forma nativa con Swift / SwiftUI, sin navegador integrado ni servidor web local permanente.

### Rendimiento de referencia

Medición de referencia con aproximadamente **810 MB de historial de Codex**: colección en frío **3,23 s / ~127 MiB**, colección incremental con índice **0,86 s / ~34 MiB**, actualización sin cambios **0,82 s / ~34 MiB**. Son picos del proceso de colección / exportación, no el RSS permanente de la aplicación.

## Capturas de pantalla

<p align="center">
  <img src="docs/images/dashboard.webp" width="900" alt="Panel de TokenWatch Mac">
</p>
<p align="center"><sub>Resumen de uso, desglose por proyecto, distribución de modelos y tendencias.</sub></p>

<p align="center">
  <img src="docs/images/menu-bar.webp" width="560" alt="Panel de la barra de menús de TokenWatch Mac">
</p>
<p align="center"><sub>Panel de la barra de menús con uso acumulado por periodos y ventanas de cuota.</sub></p>

## Privacidad

Los snapshots de TokenWatch no almacenan prompts, respuestas, argumentos de herramientas, rutas completas de proyectos ni credenciales de proveedores. CloudKit conserva únicamente el último sobre cifrado de extremo a extremo en la base privada del usuario. La detección de archivos se limita a ubicaciones Provider conocidas.

## Instalación

Descarga el último DMG desde GitHub Releases.

Los DMG actuales son builds Universal, con firma ad-hoc y sin notarización; macOS puede mostrar una advertencia de Gatekeeper. La sincronización remota de CloudKit solo está disponible en builds con los entitlements necesarios.

## Compilación

Requisitos: macOS 14+, Xcode y toolchain Swift 6.1.

```sh
Scripts/bootstrap
Scripts/verify
Scripts/build-mac-dmg
```

## Código fuente

El código fuente es visible públicamente para facilitar la transparencia y la revisión. No se concede una licencia de código abierto salvo que un archivo de licencia del repositorio indique expresamente lo contrario.
