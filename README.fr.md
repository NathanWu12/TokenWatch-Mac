# TokenWatch Mac

**Un hub macOS natif, léger et économe en ressources, conçu pour rester actif en permanence.** Il détecte en lecture seule les données locales standard de Codex, Claude Code, Antigravity et OpenCode, puis regroupe l'utilisation du jour / 7 jours / 30 jours / historique, les tendances par modèle et projet ainsi que les quotas.

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · **Français** · [Español](README.es.md)

## Conçu pour fonctionner en continu

L'index incrémental persistant de Codex ne lit que les nouveaux octets. FSEvents surveille les répertoires Provider autorisés, la concurrence des collecteurs est limitée, les écritures disque / LAN / CloudKit sans changement significatif sont évitées et la synchronisation distante suit une stratégie latest-wins pour empêcher l'accumulation d'anciens snapshots. L'application est native Swift / SwiftUI, sans navigateur embarqué ni serveur Web local permanent.

### Performances de référence

Mesure de référence avec environ **810 MB d'historique Codex** : collecte à froid **3,23 s / ~127 MiB**, collecte incrémentale avec index **0,86 s / ~34 MiB**, actualisation sans changement **0,82 s / ~34 MiB**. Ces chiffres correspondent aux pics du chemin de collecte / export et non au RSS permanent de l'application.

## Une petite empreinte par conception

TokenWatch Mac est développé en **Swift / SwiftUI / AppKit natif** et réutilise directement les frameworks de macOS. La version Universal actuelle n'embarque **ni dossier Frameworks, ni Chromium, ni Electron, ni runtime Node.js**.

Mesures du 2026-09-05 : DMG Universal **5,3 MB**, application installée **~11 MB**. Après ~1,5 h d'exécution, `top` indiquait **~45 MB** en veille ; six échantillons d'une seconde ont affiché **0,0 % CPU / POWER 0,0**. Le RSS `ps`, qui inclut les mappings partagés, était de **~121 MiB**. `POWER` est un indicateur relatif de `top`, pas une mesure en watts.

Sur le configurateur actuel du Mac mini M6 d'Apple (2026-09-05), un palier adjacent de 8 GB de mémoire unifiée coûte **$200** et le passage SSD 256→512 GB coûte **$200**. À titre d'illustration de capacité uniquement, 45 MB représentent **~0,19 % de 24 GB, soit ~1,1 $**, et 11 MB représentent **~0,004 % de 256 GB, soit ~0,01 $**. Ce n'est pas une estimation du coût réel du matériel.

Le runtime macOS arm64 d'Electron v44.0.0 est distribué sous forme d'un ZIP d'environ **123,7 MiB**. Le DMG Universal de TokenWatch, **5,3 MB** et contenant Apple Silicon + Intel, est encore **~23× plus petit que cette archive runtime compressée seule**. Il s'agit d'une comparaison de base de framework, pas d'une affirmation selon laquelle toutes les applications non-Swift ou concurrentes seraient lourdes.

Sources : [Apple M6 Mac mini](https://www.apple.com/newsroom/2026/08/apple-unveils-a-more-powerful-mac-mini-featuring-the-all-new-m6-and-m5-pro/) · [Configurateur Apple](https://www.apple.com/shop/buy-mac/mac-mini/m6-chip-12-core-cpu-12-core-gpu-24gb-memory-256gb-storage) · [Electron v44.0.0](https://github.com/electron/electron/releases/tag/v44.0.0) · [Modèle de processus Electron](https://www.electronjs.org/docs/latest/tutorial/process-model)

## Captures d'écran

<p align="center">
  <img src="docs/images/dashboard.webp" width="900" alt="Tableau de bord TokenWatch Mac">
</p>
<p align="center"><sub>Résumé d'utilisation, répartition par projet, distribution des modèles et tendances.</sub></p>

<p align="center">
  <img src="docs/images/menu-bar.webp" width="560" alt="Fenêtre de la barre des menus TokenWatch Mac">
</p>
<p align="center"><sub>Fenêtre de la barre des menus avec utilisation glissante et fenêtres de quota.</sub></p>

## Confidentialité

Les snapshots TokenWatch ne stockent ni prompts, ni réponses, ni arguments d'outils, ni chemins complets de projets, ni identifiants de fournisseurs. CloudKit ne conserve que la dernière enveloppe chiffrée de bout en bout dans la base privée de l'utilisateur. La découverte des fichiers est limitée aux emplacements Provider connus.

## Installation

Téléchargez le dernier DMG depuis GitHub Releases.

Les DMG actuels sont des builds Universal, signés ad-hoc et non notarized ; macOS peut afficher un avertissement Gatekeeper. La synchronisation distante CloudKit n'est disponible que dans les builds disposant des entitlements requis.

## Compilation

Prérequis : macOS 14+, Xcode et la toolchain Swift 6.1.

```sh
Scripts/bootstrap
Scripts/verify
Scripts/build-mac-dmg
```

## Code source

Le code source est visible publiquement pour la transparence et la revue. Aucune licence open source n'est accordée sauf indication explicite dans un fichier de licence du dépôt.
