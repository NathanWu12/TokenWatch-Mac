# TokenWatch Mac

**Un hub nativo para macOS, ligero y de bajo consumo, diseñado para permanecer activo de forma continua.** Detecta en modo de solo lectura los datos locales estándar de Codex, Claude Code, Antigravity y OpenCode y unifica el uso de hoy / 7 días / 30 días / histórico, las tendencias por modelo y proyecto y las cuotas.

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · **Español**

## Diseñado para funcionar de forma continua

El índice incremental persistente de Codex solo lee los bytes nuevos. FSEvents detecta cambios en directorios Provider autorizados, la concurrencia de los recolectores está limitada, se evitan escrituras innecesarias en disco / LAN / CloudKit y la sincronización remota usa una estrategia latest-wins para impedir la acumulación de snapshots antiguos. La aplicación está implementada de forma nativa con Swift / SwiftUI, sin navegador integrado ni servidor web local permanente.

### Rendimiento de referencia

Medición de referencia con aproximadamente **810 MB de historial de Codex**: colección en frío **3,23 s / ~127 MiB**, colección incremental con índice **0,86 s / ~34 MiB**, actualización sin cambios **0,82 s / ~34 MiB**. Son picos del proceso de colección / exportación, no el RSS permanente de la aplicación.

## Una huella pequeña por diseño

TokenWatch Mac está desarrollado con **Swift / SwiftUI / AppKit nativos** y reutiliza directamente los frameworks del sistema macOS. La versión Universal actual no incluye **Frameworks embebidos, Chromium, Electron ni runtime de Node.js**.

Medición del 2026-09-05: DMG Universal **5,3 MB**, aplicación instalada **~11 MB**. Después de ~1,5 h de ejecución, `top` mostró **~45 MB** en reposo; seis muestras consecutivas de un segundo dieron **0,0 % CPU / POWER 0,0**. El RSS de `ps`, que incluye mapeos compartidos, fue **~121 MiB**. `POWER` es una métrica relativa de `top`, no una medición en vatios.

En el configurador actual del Mac mini M6 de Apple (2026-09-05), un salto adyacente de 8 GB de memoria unificada cuesta **$200** y el salto SSD de 256→512 GB cuesta **$200**. Solo como ilustración de capacidad, 45 MB son **~0,19 % de 24 GB, o ~1,1 USD**, y 11 MB son **~0,004 % de 256 GB, o ~0,01 USD**. No es una estimación del coste real del hardware.

El runtime macOS arm64 de Electron v44.0.0 se distribuye como un ZIP de **~123,7 MiB**. El DMG Universal de TokenWatch, de **5,3 MB** e incluyendo Apple Silicon + Intel, sigue siendo **~23× más pequeño que ese runtime comprimido por sí solo**. Es una comparación de base de framework, no una afirmación de que toda aplicación no-Swift o competidora sea pesada.

Fuentes: [Apple M6 Mac mini](https://www.apple.com/newsroom/2026/08/apple-unveils-a-more-powerful-mac-mini-featuring-the-all-new-m6-and-m5-pro/) · [Configurador de Apple](https://www.apple.com/shop/buy-mac/mac-mini/m6-chip-12-core-cpu-12-core-gpu-24gb-memory-256gb-storage) · [Electron v44.0.0](https://github.com/electron/electron/releases/tag/v44.0.0) · [Modelo de procesos de Electron](https://www.electronjs.org/docs/latest/tutorial/process-model)

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
