# Validation — 28 octobre 2026

- Mac Apple Silicon, macOS 27.0.1 (26A434).
- `csrutil status` : System Integrity Protection enabled. Aucun réglage SIP modifié.
- Compilation C : `-Wall -Wextra -Werror` ; Swift : `-warnings-as-errors`.
- Signature locale : vérification `codesign --verify --strict` réussie.
- 63 contrôles du modèle et du format des gestes réussis.
- Test de cycle de vie : contrôleur et minuteur toujours actifs après le démarrage.
  Correction de la conservation du contrôleur pendant la boucle principale.
- Seules des bibliothèques système sont liées.
- Diagnostic natif : dix bureaux ordinaires correctement énumérés ; API de déplacement disponible.
- Test natif sur une fenêtre créée par SpaceKeys : bureau 1 (ID 5) → bureau 10 (ID 703),
  appartenance confirmée en 15 ms ; retour au bureau 1 confirmé en 10 ms.
  Fenêtre de test fermée ; aucune fenêtre utilisateur déplacée.
- Répétition du test natif sur la version corrigée : bureau 10 → bureau 9 en 56 ms,
  retour au bureau 10 en 20 ms ; deux appartenances confirmées puis fenêtre fermée.

## À qualifier après autorisation Accessibilité

- Sauts courts et longs dans les deux sens, dont 1 ↔ 10, avec constat visuel d’absence de défilement.
- Série rapide de raccourcis et destination finale.
- Envoi d’une fenêtre utilisateur puis réorganisation automatique par Amethyst.
- Plusieurs écrans, veille/réveil et reconnexion d’écran : non qualifiés.

Le test natif de déplacement ne valide pas à lui seul les sauts ni l’intégration avec Amethyst.

## Version 1.1 — présentation et projet autonome

- Script `./build.sh` exécuté intégralement : génération ICNS avec les outils Apple,
  compilation C/Swift sans avertissement, 63 contrôles réussis, signature locale vérifiée.
- Test `--lifecycle-test` réussi sur le nouveau binaire ; aucun bureau changé.
- Fenêtre AppKit observée nativement en apparence sombre : icône, état, autorisation,
  dix numéros de bureaux, bureau 9 surligné, deux raccourcis et boutons visibles sans coupure.
- L’aperçu provenant du dossier temporaire indique correctement une autorisation manquante.
  La version 1.0 installée reconnaissait l’autorisation après la confirmation de l’utilisateur.
- Les détails techniques ont été séparés de la fenêtre principale ; leur bouton n’a pas pu
  être vérifié jusqu’au bout, car le Mac s’est verrouillé pendant le contrôle de l’interface.
- Cette modification concerne les ressources, la construction et la présentation.
  Elle ne qualifie pas davantage l’absence d’animation ni l’intégration Amethyst.
- Aucun dépôt distant créé et aucune publication effectuée.

## Installation finale 1.1

- Nouvelle app installée dans le dossier Applications personnel et relancée.
- Signature du bundle installé vérifiée ; diagnostic installé : Accessibilité accordée,
  dix bureaux ordinaires énumérés et déplacement natif disponible.
- SIP vérifié à nouveau : activé. Aucune nouvelle réautorisation n’a été nécessaire
  pour cette installation, malgré l’autorisation absente dans l’aperçu temporaire.
- Ancienne version conservée dans `build/backups/SpaceKeys-1.0.app` (ignorée par Git).
