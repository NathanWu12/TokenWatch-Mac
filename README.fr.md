# TokenWatch Mac

**Un hub macOS natif, léger et peu gourmand, conçu pour rester ouvert en permanence.** Il détecte en lecture seule les données locales standard de Codex, Claude Code, Antigravity et OpenCode et regroupe l'utilisation du jour / 7 jours / 30 jours / cumulée, les tendances par modèle/projet et les quotas.

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · **Français** · [Español](README.es.md)

## Pensé pour fonctionner 24/7

Index Codex incrémental persistant, déclenchement FSEvents sur une liste blanche de dossiers, concurrence bornée, déduplication des instantanés et synchronisation distante « latest-wins » : l'application évite les rescans complets et les écritures inutiles.

Mesure sur ~810 Mo d'historique Codex (2026-09-04) : collecte à froid **3,23 s / ~127 MiB**, collecte incrémentale avec index **0,86 s / ~34 MiB**, aucune modification **0,82 s / ~34 MiB**. Ces chiffres mesurent le pic du chemin de collecte, pas le RSS permanent de l'application.

## Confidentialité

Les prompts, réponses, paramètres d'outils, chemins de projet complets et identifiants fournisseur ne sont pas enregistrés dans les instantanés TokenWatch. CloudKit ne conserve que la dernière enveloppe chiffrée de bout en bout dans la base privée de l'utilisateur.

## Installation

Téléchargez le DMG depuis GitHub Releases. Le DMG Preview actuel est signé ad-hoc, non notarized et utilise les entitlements local-only : la synchronisation distante CloudKit y est donc désactivée. Une version stable publique devra être signée Developer ID et notarized.

```sh
Scripts/bootstrap
Scripts/verify
Scripts/build-mac-dmg
```

Une vraie capture du tableau de bord sera ajoutée avant la version stable. Aucun droit open source n'est accordé sans fichier LICENSE explicite.
