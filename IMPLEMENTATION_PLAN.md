# Plan d'implémentation — VéloBoucle

Application iPhone de génération et de navigation de circuits à vélo en boucle.

---

## 1. Contraintes de l'environnement de développement

Ce dépôt est développé depuis un environnement **Linux** (Ubuntu 24.04) qui ne
dispose ni de macOS, ni de Xcode, ni du SDK iOS. Cela a une conséquence directe
et structurante sur l'architecture :

> **Tout ce qui peut être écrit sans dépendre des frameworks Apple doit l'être
> dans un paquet Swift séparé, réellement compilable et testable ici.**

Concrètement :

| Couche | Emplacement | Compilable dans cet environnement | Frameworks |
|---|---|---|---|
| Logique métier (modèles, algorithmes, réseau, GPX, statistiques) | `Core/` (paquet SwiftPM `VeloCore`) | **Oui** — `swift build` / `swift test` | Foundation uniquement |
| Interface et intégration système (cartes, GPS, voix, persistance) | `App/VeloBoucle/` | Non (nécessite Xcode) | SwiftUI, MapKit, CoreLocation, SwiftData, AVFoundation, UIKit |

Le compilateur Swift 6.1 est obtenu via Docker (`Scripts/swift-docker.sh`), car
`download.swift.org` est bloqué par la politique de sortie réseau de
l'environnement. Voir `docs/BUILD.md`.

Cette séparation n'est pas un contournement : c'est la bonne architecture. Elle
force l'algorithme de génération de boucles, le suivi de parcours et le calcul de
statistiques à être testables sans simulateur, ce qui est précisément ce que
demande le cahier des charges (§17).

## 2. Choix du moteur de routage

Voir `docs/ROUTING_ENGINE.md` pour la comparaison détaillée.

**Décision : OpenRouteService (ORS)**, avec une abstraction `RoutingService`
permettant d'en changer sans toucher au reste de l'application.

Raison décisive : **MapKit ne sait pas calculer d'itinéraire vélo.**
`MKDirectionsTransportType` n'expose que `.automobile`, `.walking` et
`.transit`. Il n'existe aucun moyen d'obtenir un itinéraire cyclable, ni
d'exclure les voies interdites aux vélos, ni de générer une boucle. MapKit est
donc conservé **uniquement pour l'affichage** de la carte.

ORS est retenu parce qu'il est le seul service gratuit à proposer nativement la
génération de **boucles** (`options.round_trip`) avec des profils vélo, des
instructions en français, l'altitude et les métadonnées de revêtement.

## 3. Architecture cible

```
GPS/
├── Core/                                  paquet SwiftPM « VeloCore »
│   ├── Package.swift
│   ├── Sources/VeloCore/
│   │   ├── Models/          GeographicCoordinate, CyclingRoute, RouteCandidate,
│   │   │                    RouteSegment, NavigationInstruction, RideSession,
│   │   │                    RecordedRide, CyclingProfile, RoutingPreferences,
│   │   │                    LocationSample, RouteDeviation
│   │   ├── Geo/             géodésie : distance, cap, projection sur polyligne
│   │   ├── Networking/      HTTPClient (protocole) + URLSession, erreurs
│   │   ├── Routing/         OpenRouteServiceClient, décodage GeoJSON
│   │   ├── LoopGeneration/  LoopGenerationService, scoring des candidats
│   │   ├── Navigation/      RouteMatchingService, NavigationEngine,
│   │   │                    formatage français des instructions
│   │   ├── Tracking/        RideTracker, filtrage GPS, statistiques
│   │   ├── GPX/             GPXExporter, GPXImporter
│   │   ├── Demo/            données et services simulés (isolés)
│   │   └── Utilities/       formatage, unités, journalisation sans PII
│   └── Tests/VeloCoreTests/
├── App/
│   ├── VeloBoucle.xcodeproj
│   └── VeloBoucle/
│       ├── App/             point d'entrée, injection de dépendances
│       ├── Features/        Home, Generation, Comparison, Preview,
│       │                    Navigation, RideSummary, History, Settings
│       ├── Services/        LocationService, SpeechInstructionService,
│       │                    HapticService, PersistenceService (SwiftData)
│       ├── MapKit/          ponts VeloCore ↔ MapKit
│       └── Resources/       Localizable (fr, en, de), Info.plist, Assets
├── Scripts/
├── docs/
└── (README, CHANGELOG, PROJECT_STATUS, PRIVACY, LIMITATIONS…)
```

Toutes les dépendances sont injectées via des protocoles (`RoutingService`,
`LocationProviding`, `HTTPClient`, `RideStoring`, `SpeechAnnouncing`,
`HapticFeedback`), ce qui rend chaque service remplaçable par un double de test.

## 4. Découpage en versions

### v0.1 — Fondation
- Paquet `VeloCore` : modèles, géodésie, préférences, profils.
- Client HTTP abstrait, gestion d'erreurs francisée.
- Squelette de l'application iOS : onglets, carte, état de localisation.
- `LocationService` complet (autorisations, précision adaptative, filtrage).
- Mode démonstration isolé.

### v0.2 — Génération de circuits
- `OpenRouteServiceClient` (boucles + points de passage).
- `LoopGenerationService` : multi-orientations, multi-graines, candidats
  parallèles, filtrage des circuits invalides, scoring.
- Écrans de chargement et de comparaison des circuits.

### v0.3 — Navigation
- `RouteMatchingService` : projection sur la polyligne, progression,
  distance restante, détection hors parcours avec hystérésis.
- `NavigationEngine` : instruction courante, distance à la manœuvre,
  ETA, annonces vocales, haptique.
- Recalcul (automatique / sur demande / désactivé).
- Écran de navigation « guidon ».

### v0.4 — Enregistrement
- `RideTracker` : filtrage des points aberrants, dénivelé, vitesses,
  temps de déplacement, calories estimées.
- Persistance SwiftData, reprise d'une sortie interrompue.
- Historique, détail, renommage, suppression.
- Export / import / partage GPX.

### v0.5 — Finalisation
- Localisation fr/en/de, Dynamic Type, VoiceOver, contraste.
- Gestion exhaustive des erreurs avec actions de récupération.
- Optimisation batterie documentée.
- Documentation complète, politique de confidentialité, guide d'installation.

## 5. Stratégie de test

- **Tests unitaires `VeloCore`** (exécutés réellement ici) : écart de distance,
  sélection du meilleur circuit, rejet des circuits invalides, détection de
  sortie de parcours, distance restante, progression, vitesse moyenne,
  génération GPX, reprise de sortie interrompue.
- **Doubles de test** : `MockHTTPClient` (réponses JSON figées, aucune clé API),
  `SimulatedLocationProvider` (rejeu d'une trace).
- **Tests d'interface XCUITest** : fournis dans le projet Xcode, exécutables sur
  macOS uniquement ; documentés avec la commande exacte.

## 6. Sécurité des secrets

Aucune clé API dans le code. Chaîne de résolution, dans l'ordre :

1. variable d'environnement `ORS_API_KEY` (tests et CI) ;
2. `Secrets.xcconfig` (non versionné) → injecté dans `Info.plist` ;
3. absence de clé → l'application démarre normalement en **mode démonstration**
   et affiche une explication avec un lien vers la procédure.
