# TokenWatch Mac

**Un hub macOS natif, léger et économe en ressources, conçu pour rester actif en permanence.** Il détecte en lecture seule les données locales standard de Codex, Claude Code, Antigravity et OpenCode, puis regroupe l'utilisation du jour / 7 jours / 30 jours / historique, les tendances par modèle et projet ainsi que les quotas.

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · **Français** · [Español](README.es.md)

## Conçu pour fonctionner en continu

L'index incrémental persistant de Codex ne lit que les nouveaux octets. FSEvents surveille les répertoires Provider autorisés, la concurrence des collecteurs est limitée, les écritures disque / LAN / CloudKit sans changement significatif sont évitées et la synchronisation distante suit une stratégie latest-wins pour empêcher l'accumulation d'anciens snapshots. L'application est native Swift / SwiftUI, sans navigateur embarqué ni serveur Web local permanent.

### Performances de référence

Mesure de référence avec environ **810 MB d'historique Codex** : collecte à froid **3,23 s / ~127 MiB**, collecte incrémentale avec index **0,86 s / ~34 MiB**, actualisation sans changement **0,82 s / ~34 MiB**. Ces chiffres correspondent aux pics du chemin de collecte / export et non au RSS permanent de l'application.

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
