# Architecture

## Principe directeur

VéloBoucle est découpé en **deux couches**, séparées par une frontière stricte :

| | `Core/` — paquet `VeloCore` | `App/VeloBoucle/` |
|---|---|---|
| Rôle | logique métier | interface et intégration système |
| Dépendances | Foundation uniquement | SwiftUI, MapKit, CoreLocation, SwiftData, AVFoundation, UIKit |
| Testable sans simulateur | oui | non |
| Connaît l'autre couche | non | oui |

`VeloCore` ne sait pas qu'une interface existe. Il ne contient ni vue, ni
`CLLocation`, ni `MKPolyline`, ni conteneur SwiftData. Il manipule ses propres
types (`GeographicCoordinate`, `LocationSample`, `CyclingRoute`) et l'application
fait la traduction à la frontière.

### Pourquoi

La raison immédiate est pratique : ce dépôt est développé depuis Linux, sans
Xcode. Sans cette séparation, rien ne serait compilable ni testable.

Mais la raison de fond est meilleure. Les parties délicates de cette application
— l'algorithme de génération de boucles, le suivi de position sur un tracé qui
se recoupe, la détection d'écart sans fausse alerte, le calcul de statistiques —
sont exactement celles qu'on ne peut pas valider en cliquant dans un simulateur.
Les isoler dans un paquet pur permet de **rejouer une trace GPS complète en
quelques millisecondes** et de vérifier chaque événement produit. C'est ce que
font `NavigationTests` et `RideTrackingTests`.

## Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────┐
│  Vues SwiftUI                                               │
│  PlannerScreen · RouteComparisonSheet · RoutePreviewScreen  │
│  RideNavigationScreen · RideSummaryScreen                   │
│  HistoryScreen · RideDetailScreen · SettingsScreen          │
└───────────────┬─────────────────────────────────────────────┘
                │ @Observable
┌───────────────▼─────────────────────────────────────────────┐
│  Vues-modèles                                               │
│  PlannerViewModel          RideViewModel                    │
└───────────────┬─────────────────────────────────────────────┘
                │ injection par AppDependencies
┌───────────────▼─────────────────────────────────────────────┐
│  Services de la couche iOS                                  │
│  LocationService · SpeechInstructionService · HapticService │
│  PersistenceService · SecretsProvider · DemoRideSimulator   │
└───────────────┬─────────────────────────────────────────────┘
                │ protocoles
┌───────────────▼─────────────────────────────────────────────┐
│  VeloCore                                                   │
│  RoutingService ◄── OpenRouteServiceClient / DemoRouting…   │
│  LoopGenerating ◄── LoopGenerationService ── RouteScorer    │
│  RouteMatching  ◄── RouteMatchingService                    │
│  NavigationEngine · DeviationDetector · RejoinPointSelector │
│  RideTracker · LocationFilter · GPXService                  │
│  RideStoring · RideSnapshotStoring                          │
└─────────────────────────────────────────────────────────────┘
```

## Injection de dépendances

`AppDependencies` est l'unique point de construction des services. Aucun
singleton n'est utilisé, aucune vue n'instancie un service. Le conteneur est
placé dans l'environnement SwiftUI au démarrage.

Cela rend possibles trois choses qui seraient autrement pénibles :

- **basculer entre moteur réel et moteur de démonstration** en remplaçant une
  seule référence (`setDemoMode(_:)`), sans condition disséminée dans le code ;
- **lancer les tests d'interface sans réseau ni clé API**, en forçant le mode
  démonstration depuis un argument de lancement ;
- **changer de moteur de routage** — écrire un `GraphHopperClient` conforme à
  `RoutingService` et le déclarer ici suffirait ; rien d'autre ne connaît
  OpenRouteService.

## Décisions techniques notables

### Types valeur à état mutable pour la navigation et le suivi

`NavigationEngine` et `RideTracker` sont des `struct` avec des méthodes
`mutating`, et non des classes observables. Chaque relevé GPS produit un nouvel
état et une liste d'événements :

```swift
let events = engine.update(with: sample)
```

Un test peut donc rejouer une trace entière et vérifier la séquence exacte
d'événements, sans horloge, sans capteur, sans simulateur. L'observabilité est
apportée par `RideViewModel`, qui enveloppe ces types.

### Fenêtre glissante pour le suivi de parcours

Sur une **boucle**, le tracé se recoupe — au minimum près du départ. Chercher le
point le plus proche sur l'ensemble de l'itinéraire ferait sauter la progression
d'un croisement à l'autre : la navigation annoncerait l'arrivée dès les premiers
mètres.

`RouteMatchingService` limite donc la recherche à une fenêtre autour de la
position précédente : 120 m en arrière — pour tolérer un recul, une dérive GPS ou
un demi-tour volontaire — et 900 m en avant, de quoi couvrir la traversée d'un
tunnel. La recherche n'est élargie à tout le tracé que si la fenêtre ne donne
rien de plausible, et le résultat global n'est retenu que s'il est nettement
meilleur.

### Hystérésis sur la détection de sortie de parcours

Trois précautions, parce que la fausse alerte est le défaut le plus pénible d'une
application de navigation à vélo :

1. **seuil adaptatif** — la tolérance croît avec l'incertitude annoncée par le
   GPS (en ville, entre les immeubles, l'erreur dépasse couramment 30 m) ;
2. **confirmation dans la durée** — trois relevés consécutifs au-delà du seuil ;
3. **hystérésis** — le retour est déclaré à 60 % du seuil de sortie, ce qui évite
   l'oscillation quand on longe le tracé.

### Point de reprise toujours vers l'avant

`RejoinPointSelector` explore les 2,5 km suivants sur le circuit et choisit le
point qui minimise « distance à parcourir moins crédit d'avancement ». Rejoindre
plus loin devant est donc récompensé, mais pas au prix d'un détour
disproportionné. On ne renvoie jamais l'utilisateur en arrière si une solution
existe devant : faire faire demi-tour à un cycliste sur une route ouverte est un
problème de sécurité, pas seulement de confort.

### Recollement après recalcul

`RouteSplicer` fusionne l'itinéraire de rattrapage avec **la suite** du circuit
d'origine, en réindexant les consignes restantes sur la nouvelle polyligne. Sans
cela, un recalcul guiderait jusqu'au point de reprise puis abandonnerait
l'utilisateur au milieu de nulle part.

### Précision GPS adaptative

| Situation | Précision | Filtre de distance | Arrière-plan |
|---|---|---|---|
| Consultation de la carte | 100 m | 50 m | non |
| Navigation ou enregistrement | meilleure possible | 5 m | oui, si « Toujours » autorisé |
| Pause | 100 m | 50 m | non |
| Aucune sortie, application en fond | arrêt complet | — | non |

À 25 km/h, un point tous les 5 m donne environ 1,4 relevé par seconde : assez
dense pour un tracé fidèle, sans réveiller l'application à l'arrêt.
`pausesLocationUpdatesAutomatically` est désactivé, car du point de vue de
CoreLocation une pause au sommet d'un col ressemble beaucoup à une fin de trajet.

### Filtrage des positions plutôt que lissage

`LocationFilter` **écarte l'impossible** — précision au-delà de 65 m, saut
impliquant plus de 90 km/h, relevé antérieur au précédent, déplacement inférieur
à 3 m — mais ne lisse pas la trace. Un lissage agressif raccourcirait la distance
réellement parcourue par le cycliste, ce qui serait une erreur plus grave que de
laisser passer un peu de bruit.

Le dénivelé est cumulé **par paliers de 3 m** : l'altitude GPS oscille de
plusieurs mètres même à l'arrêt, et sans ce seuil une sortie parfaitement plate
afficherait plusieurs centaines de mètres de dénivelé.

### Persistance : deux mécanismes distincts

- **Historique** → SwiftData (`StoredRide`). Les données volumineuses — trace,
  circuit, écarts — sont stockées en JSON dans des `Data` marqués
  `.externalStorage`. Les modéliser en entités liées multiplierait les objets
  gérés par le contexte sans bénéfice, puisqu'on ne les interroge jamais
  individuellement. Date, nom et distance restent de vrais attributs, car on
  trie et recherche dessus.
- **Sortie en cours** → un fichier JSON écrit atomiquement toutes les dix
  secondes (`FileRideSnapshotStore`). Sans schéma à migrer ni contexte à
  sauvegarder, ce qui compte quand le système peut tuer l'application à tout
  moment. Au maximum dix secondes de trajet sont perdues.

### Concurrence

Les vues-modèles et les services iOS sont `@MainActor`. `VeloCore` est composé
de types `Sendable`, et la génération de boucles utilise un `TaskGroup` à
concurrence bornée (trois requêtes simultanées) pour rester dans le quota du
moteur tout en divisant le temps d'attente.

Le projet est compilé en mode Swift 5 avec `SWIFT_STRICT_CONCURRENCY = minimal`.
Le code est écrit pour être correct sous concurrence stricte ; le passage au mode
Swift 6 est listé dans les améliorations futures.

## Modèles principaux

| Type | Rôle |
|---|---|
| `GeographicCoordinate` | coordonnée WGS 84 avec altitude optionnelle |
| `CyclingRoute` | tracé, distance, durée, dénivelé, consignes, tronçons ; distances cumulées précalculées |
| `RouteCandidate` | circuit évalué : note, avertissements, graine |
| `RouteSegment` | portion homogène en revêtement et type de voie |
| `NavigationInstruction` | manœuvre rattachée à une plage d'indices du tracé |
| `LocationSample` | relevé GPS indépendant de CoreLocation |
| `RouteDeviation` | écart au circuit, avec durée et distance maximale |
| `RideSession` | sortie en cours, sérialisable pour la reprise |
| `RecordedRide` | sortie terminée |
| `CyclingProfile` | type de vélo → profil de routage, MET, vitesse indicative |
| `RoutingPreferences` | préférences de parcours de l'utilisateur |

`CyclingRoute` précalcule ses distances cumulées à la construction : la
navigation les interroge à chaque relevé GPS, et les recalculer coûterait O(n)
par point.

## Localisation

Tous les textes visibles passent par `Strings.swift`, qui appelle
`NSLocalizedString` avec une clé et une valeur française par défaut. Aucune
chaîne n'est écrite en dur dans une vue.

`Scripts/extract_strings.py` extrait les 169 clés et génère les trois catalogues
`fr` / `en` / `de` en préservant les traductions déjà faites. Ajouter une langue
consiste à traduire un fichier `.strings` : aucun code à modifier.

## Journalisation

`AppLog` expose cinq catégories `OSLog`. Règle absolue : **aucune trace ne
contient de clé API, de position précise ni de donnée personnelle.** `OSLog`
traite par défaut toute valeur interpolée comme privée ; les rares valeurs
marquées `.public` sont des libellés fixes. `GeographicCoordinate.description`
est arrondi à quatre décimales (~11 m) pour la même raison.
