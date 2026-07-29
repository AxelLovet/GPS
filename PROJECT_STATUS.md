# État du projet — VéloBoucle

*Mis à jour le 29 juillet 2026.*

## Version actuelle

**0.5.0** — toutes les étapes prévues au plan d'implémentation sont écrites.

| | |
|---|---|
| Sources Swift | 57 fichiers, ~13 000 lignes |
| Paquet `VeloCore` | 28 fichiers |
| Application iOS | 29 fichiers |
| Tests | 10 fichiers, 124 tests unitaires `VeloCore` + tests de la couche application + 6 scénarios d'interface |
| Dépendances externes | aucune |
| Cible | iOS 17.0 et supérieur |

---

## Résultat de la dernière compilation

Environnement : Ubuntu 24.04, Swift 6.1.3 (conteneur `swift:6.1-noble`).
Commande : `./Scripts/check.sh`.

```
═══ VeloCore — compilation
  ✓ swift build                     Compiling ... Build complete.

═══ VeloCore — tests unitaires
  ✓ swift test                      Executed 124 tests, with 0 failures

═══ Application iOS — analyse syntaxique
  ✓ toutes les sources analysées    29 fichiers, swiftc -parse, 0 erreur

═══ Projet Xcode — cohérence
  ✓ validate_pbxproj                127 objets, 37 références de fichiers,
                                    29 sources Swift compilées, projet cohérent

═══ Traductions — catalogues à jour
  ✓ extract_strings                 169 clés · fr 169/169 · en 0/169 · de 0/169

═══ Secrets — aucun jeton versionné
  ✓ aucun secret détecté
  ✓ Secrets.xcconfig non versionné

Tous les contrôles disponibles sont au vert.
```

**Ce que cela ne couvre pas** : la compilation complète de l'application iOS
exige le SDK Apple, absent de cet environnement. Voir
[la section « Réserves »](#réserves) plus bas et
[LIMITATIONS.md](LIMITATIONS.md).

## Résultat des derniers tests

### `VeloCore` — 124 tests, 0 échec, 1,6 s

| Suite | Tests | Ce qu'elle couvre |
|---|---|---|
| `GeodesyTests` | 11 | distances, caps, projections, validation de coordonnées, arrondi des journaux |
| `RouteScoringTests` | 17 | écart de distance, rejet des allers-retours et des boucles ouvertes, gravier, sélection du meilleur circuit, dédoublonnage |
| `LoopGenerationTests` | 14 | trois propositions distinctes, fermeture des boucles, passe corrective, direction préférée, erreurs, annulation, panne partielle du moteur |
| `NavigationTests` | 19 | distance restante, progression monotone sur une boucle qui se recoupe, détection de sortie de parcours, hystérésis, point de reprise, annonces, haptique, arrivée, ETA |
| `RideTrackingTests` | 13 | vitesse moyenne, rejet des positions aberrantes, dénivelé par paliers, pause, écarts, calories |
| `GPXServiceTests` | 12 | structure GPX 1.1, échappement, horodatage UTC, aller-retour export/import, fichiers externes, erreurs |
| `RideRecoveryTests` | 12 | décision de reprise, instantané sur disque, fichier corrompu, poursuite d'une sortie reprise |
| `OpenRouteServiceClientTests` | 16 | décodage GeoJSON, traduction des manœuvres, corps de requête, codes HTTP, messages d'erreur |
| `InstructionPhrasingTests` | 10 | consignes françaises, arrondis, virgule décimale, flèches |

Les tests n'utilisent **aucune clé API réelle** et n'émettent aucune requête
réseau : le client HTTP est remplacé par un double rejouant des réponses figées.

### Couverture des tests obligatoires du cahier des charges (§17)

| Exigence | Test |
|---|---|
| écart entre distance souhaitée et obtenue | `testDistanceDeviationRatioIsSignedAndRelative` |
| sélection du meilleur circuit | `testBestCandidateIsTheOneClosestToTarget` |
| élimination des circuits invalides | `testOutAndBackIsRejectedAsRepeatedSections`, `testUnclosedLoopIsRejected` |
| détection d'une sortie du parcours | `testSustainedDistanceTriggersDeparture`, `testSimulatedDetourIsDetectedThenResolved` |
| calcul de la distance restante | `testRemainingDistanceDecreasesAlongTheRoute` |
| progression sur le parcours | `testProgressAdvancesMonotonicallyAlongASimulatedRide` |
| calcul de la vitesse moyenne | `testAverageMovingSpeedIgnoresStops`, `testAverageSpeedOverARecordedRide` |
| création d'un fichier GPX | `testExportProducesValidGPXStructure`, `testExportedFileCanBeParsedBack` |
| reprise d'une sortie interrompue | `testRecentInterruptedRideIsOfferedForResume`, `testResumedRideCanContinueAccumulatingDistance` |

### Tests écrits mais non exécutés

`App/VeloBoucleTests` (secrets, recollement d'itinéraire, persistance SwiftData)
et `App/VeloBoucleUITests` (six scénarios d'interface) exigent un simulateur iOS.
Commande sur macOS :

```bash
xcodebuild test -project App/VeloBoucle.xcodeproj -scheme VeloBoucle \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## Fonctionnalités terminées

### Génération de circuits

- boucle depuis la position actuelle ou un point choisi sur la carte ;
- distances préréglées (5, 10, 20, 30, 50 km) et valeur libre de 2 à 300 km ;
- six à neuf itinéraires calculés par génération, concurrence bornée à trois
  requêtes ;
- passe corrective automatique quand la tolérance de ±5 % n'est pas atteinte ;
- rejet des boucles ouvertes, des allers-retours déguisés, des écarts supérieurs
  à 40 %, du gravier refusé ;
- notation sur l'écart de distance, les répétitions, les demi-tours, le
  revêtement, les pistes cyclables, le dénivelé et la densité de manœuvres ;
- trois propositions dédoublonnées : recommandée, alternative 1, alternative 2 ;
- préférences : profil de vélo (électrique par défaut), pistes cyclables, trafic,
  revêtement, gravier, fortes montées, direction préférée ;
- écart résiduel affiché en clair lorsqu'il dépasse ±5 %.

### Carte et écrans

- carte interactive avec position, recentrage, choix du départ par appui ;
- tracé du circuit à double trait, chevrons indiquant le sens de parcours,
  marqueurs de départ et d'arrivée ;
- circuits alternatifs affichés en retrait et sélectionnables par appui ;
- écran de chargement avec progression réelle et annulation ;
- écran de comparaison : carte, distance, durée, dénivelé, part de pistes
  cyclables, avertissements ;
- écran d'aperçu : carte complète, résumé, liste des principales indications,
  export GPX ;
- écran de navigation, écran de fin de sortie, historique, réglages.

### Navigation

- suivi temps réel, carte orientée sens de marche ou nord en haut ;
- grande flèche et consigne française, nom de la voie, numéro de sortie de
  rond-point, distance avant la manœuvre ;
- distance restante, durée restante, heure d'arrivée estimée, vitesse
  instantanée, vitesse moyenne, distance parcourue, temps écoulé ;
- annonces vocales à trois paliers, activables ou non, sans couper la musique ;
- retours haptiques avant chaque changement de direction ;
- détection de sortie de parcours à seuil adaptatif, avec confirmation et
  hystérésis ;
- recalcul vers un point de reprise situé devant, recollé à la suite du circuit ;
- politique de recalcul : automatique, sur demande, jamais ;
- pause, reprise, fin, recentrage, vue d'ensemble.

### Arrière-plan et enregistrement

- suivi écran verrouillé et en arrière-plan avec l'autorisation « Toujours » ;
- tous les états d'autorisation gérés, jamais de blocage en cas de refus ;
- instantané écrit toutes les dix secondes et reprise proposée au redémarrage ;
- statistiques complètes, calories estimées, écarts de parcours enregistrés ;
- historique avec vignette, recherche, détail, renommage, suppression ;
- export GPX, partage, import GPX, « refaire ce parcours ».

### Qualité

- mode démonstration complet et isolé, avec simulation de déplacement et de
  sortie de parcours ;
- dix-neuf erreurs typées, chacune expliquée en français avec des actions ;
- précision GPS adaptative, filtrage des positions aberrantes, dénivelé par
  paliers ;
- aucune clé dans le code, aucune position précise dans les journaux ;
- mode clair et sombre, Dynamic Type, libellés VoiceOver.

## Fonctionnalités partielles

| Fonctionnalité | État |
|---|---|
| Traductions anglaise et allemande | infrastructure complète, 169 clés extraites, catalogues générés ; valeurs non traduites |
| Icône de l'application | emplacement présent dans le catalogue d'assets, image à fournir |
| Concurrence stricte Swift 6 | code écrit pour être conforme, compilé en mode Swift 5 ; non validé faute de compilateur Apple |
| Migration SwiftData | schéma stable, repli en mémoire en cas d'échec, mais aucune migration éprouvée |

## Fonctionnalités restantes

Détail et priorités dans [LIMITATIONS.md](LIMITATIONS.md) :
profil altimétrique avant départ, cache hors ligne des circuits, activité en
direct sur l'écran verrouillé, application Apple Watch, inversion du sens de
parcours, favoris, statistiques agrégées, capteurs Bluetooth, second moteur de
routage.

## Erreurs connues

Aucune erreur ouverte dans le périmètre vérifiable.

Les deux échecs rencontrés pendant le développement ont été corrigés :

1. **Le moteur de démonstration reliait les points de passage en ligne droite**,
   ce qui rendait tous les circuits polygonaux trop courts d'environ 20 % et les
   faisait systématiquement écarter — la préférence de direction devenait alors
   sans effet. Le moteur simulé applique désormais un facteur de détour réaliste,
   ajusté par dichotomie.
2. **Le générateur du projet Xcode construisait les groupes depuis une racine
   erronée**, produisant 27 identifiants orphelins et 27 sources non compilées.
   Détecté par `Scripts/validate_pbxproj.py`, écrit précisément pour ça.

## Réserves

Ce qui suit n'a **pas** pu être vérifié depuis cet environnement Linux et
demande une passe sur macOS :

- la **compilation complète de l'application iOS**. La syntaxe des 29 sources est
  validée, mais la vérification de types des appels SwiftUI, MapKit,
  CoreLocation et SwiftData exige le SDK Apple. Des corrections mineures à la
  première ouverture dans Xcode sont probables ;
- l'exécution des tests de la couche application et des tests d'interface ;
- le rendu visuel, l'ergonomie sur un guidon, la consommation réelle de batterie
  et le comportement du GPS en extérieur.

## Critères d'acceptation du cahier des charges (§23)

| Critère | État |
|---|---|
| l'application s'ouvre sans crash | écrit ; repli en mémoire si SwiftData échoue — à vérifier sur appareil |
| la carte s'affiche | écrit — à vérifier sur appareil |
| la position du téléphone peut être affichée | écrit, tous les états d'autorisation gérés |
| l'utilisateur peut saisir une distance | fait, préréglages et valeur libre |
| une boucle cyclable est réellement générée | fait, testé de bout en bout avec un moteur simulé |
| le départ et l'arrivée sont proches | fait, tolérance de 0,5 % bornée à 50–200 m, vérifiée par test |
| les autoroutes sont exclues | fait, par les profils vélo d'OpenRouteService |
| le parcours est affiché sur la carte | écrit — à vérifier sur appareil |
| l'utilisateur peut démarrer la navigation | fait |
| sa progression est visible | fait, progression monotone vérifiée par test |
| les directions sont affichées avec des flèches | fait, une flèche par manœuvre, couverte par test |
| une sortie du parcours est détectée | fait, détection et retour vérifiés par test |
| la sortie peut être terminée et sauvegardée | fait |
| l'historique peut être consulté | fait |
| un fichier GPX peut être exporté | fait, aller-retour export/import vérifié par test |
| le projet compile | `VeloCore` oui ; application iOS non vérifiable ici |
| les tests essentiels réussissent | 124 tests `VeloCore`, 0 échec |
