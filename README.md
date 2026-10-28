<p align="center"><img src="Resources/AppIcon.png" width="128" alt="SpaceKeys icon"></p>

# SpaceKeys

Un petit utilitaire de barre des menus pour piloter les **Spaces natifs de macOS** au clavier,
en gardant **SIP activé**. Il complète un gestionnaire de fenêtres comme Amethyst.

## Raccourcis

| Touches | Action |
| --- | --- |
| **⌘1…9, ⌘0** | Aller au bureau 1…10 de l’écran sous le pointeur |
| **⌘⇧1…9, ⌘⇧0** | Envoyer la fenêtre active au bureau 1…10 de son écran, sans la suivre |

Sur AZERTY, utiliser les **positions de la rangée numérique** : `⌘&`, `⌘é`, etc.
Maj sert à envoyer la fenêtre, pas à saisir un chiffre.
Ces combinaisons prennent la place des raccourcis des applications pour les mêmes touches.

## Construire

Prérequis : **macOS 27**, les outils en ligne de commande Apple avec Swift et Clang
(`xcode-select --install` si nécessaire). La version actuelle est vérifiée sur Apple Silicon.

```sh
./build.sh
```

Le script fabrique l’icône macOS depuis le PNG inclus, compile l’application,
exécute les tests, puis signe et vérifie `build/SpaceKeys.app`.
Tout fonctionne hors ligne, sans gestionnaire de paquets ni dépendance à télécharger.

Pour installer dans votre dossier Applications personnel, après avoir quitté SpaceKeys :

```sh
./build.sh --install
open ~/Applications/SpaceKeys.app
```

La signature est locale par défaut. Une reconstruction peut demander de renouveler
l’autorisation macOS. Si vous disposez d’une identité de signature Apple existante,
vous pouvez la passer dans la variable `CODESIGN_IDENTITY`.
Le script ne crée aucun certificat et ne modifie aucune protection du système.

## Première utilisation

1. Autoriser SpaceKeys dans Réglages Système → Confidentialité et sécurité →
   **Contrôle de l’appareil et accès aux données** (anciennement Accessibilité).
2. Dans la fenêtre SpaceKeys, choisir **Activer les raccourcis**.
3. Garder activé Trackpad → Gestes supplémentaires →
   **Balayer entre les applications en plein écran** : le mécanisme natif de saut en dépend.
4. Dans Mission Control, désactiver le réarrangement automatique des Spaces pour garder des numéros stables.

La fenêtre montre l’état, l’autorisation, le bureau actif et les raccourcis.
Les identifiants internes et le journal se trouvent dans **Détails techniques…**.
Le menu de barre des menus permet de mettre en pause, quitter et choisir l’ouverture à la connexion
(désactivée par défaut). Aucun service supplémentaire n’est installé.

## Comportement et limites

- Les numéros suivent l’ordre des **bureaux ordinaires** dans Mission Control, indépendamment des identifiants internes.
- Les Spaces plein écran comptent dans le trajet, sans recevoir de numéro de bureau ordinaire.
- SpaceKeys ne crée, supprime ou réordonne aucun Space et ne redimensionne aucune fenêtre.
- Les demandes de saut sont sérialisées ; seule la dernière destination attend en cas de frappes rapides.
- Une courte stabilisation du Dock protège les gestes successifs.
- Un échec est signalé : aucune simulation de raccourcis animés n’est lancée en remplacement.
- Les fenêtres plein écran, dialogues actifs et fenêtres sur plusieurs Spaces sont refusés à l’envoi.
- Chaque déplacement de fenêtre est confirmé en relisant son appartenance au Space cible.
- Pas d’injection, de modification de SIP, d’accès réseau ni d’autorisation d’enregistrement de l’écran.

**Compatibilité :** l’app utilise des interfaces privées de macOS 27.
Leur fonctionnement peut changer lors d’une mise à jour. L’absence visuelle d’animation,
les séquences rapides, plusieurs écrans et l’intégration Amethyst nécessitent des observations natives :
les tests de compilation seuls ne les valident pas. Voir les résultats réels dans [VALIDATION.md](VALIDATION.md).

## Diagnostics

```sh
# Lecture seule, aucun changement de bureau ni enregistrement de raccourcis
build/SpaceKeys.app/Contents/MacOS/SpaceKeys --diagnose

# Vérifier le cycle de vie du contrôleur et de son minuteur
build/SpaceKeys.app/Contents/MacOS/SpaceKeys --lifecycle-test

# Déplacer uniquement une fenêtre temporaire créée par l’app, puis la ramener
build/SpaceKeys.app/Contents/MacOS/SpaceKeys --native-move-test
```

Le dernier test est également accessible depuis le menu.
Journal local : `~/Library/Logs/SpaceKeys.log` (états et identifiants, pas de titres de fenêtres).

## Organisation

| Chemin | Contenu |
| --- | --- |
| `Sources/main.swift` | Application, raccourcis et opérations sur les Spaces |
| `Sources/StatusWindow.swift` | Fenêtre native AppKit |
| `Sources/Core.swift` | Modèle des bureaux et événements de geste |
| `Sources/Bridge.c`, `Bridge.h` | Pont natif de lecture et déplacement |
| `Tests/` | Contrôles du modèle et des événements sérialisés |
| `Resources/AppIcon.png` | Icône originale avec transparence |
| `docs/icon-generation.md` | Outil et prompt de création de l’icône |
| `build.sh`, `Info.plist` | Construction et métadonnées macOS |
| `Licenses/`, `SOURCES.txt` | Notices et références des sources tierces |

`build/` est ignoré par Git. Le dossier source peut être ajouté à un dépôt sans inclure les résultats de compilation.

## Provenance

Le pont de déplacement adapte une partie de [gechr/WhichSpace](https://github.com/gechr/WhichSpace),
sous MIT ; notice conservée dans `Licenses/WhichSpace-MIT.txt`.
Le format des événements est également documenté par [joshuarli/iss](https://github.com/joshuarli/iss),
sous 0BSD ; notice incluse. Les révisions étudiées figurent dans `SOURCES.txt`.
L’analyse de [Spacetile](https://github.com/Spacetile/Spacetile.app) a éclairé les mécanismes ;
aucun code sous sa licence propriétaire n’est incorporé.
L’icône a été créée avec l’outil intégré OpenAI image generation ; son prompt est conservé.

Pour désinstaller : désactiver l’ouverture à la connexion si nécessaire, quitter SpaceKeys,
puis supprimer l’application. Le journal peut être supprimé séparément.
