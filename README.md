# VéloBoucle

Application iPhone qui **génère automatiquement des circuits à vélo en boucle**
puis vous y guide, à la manière d'un GPS Garmin Edge.

Vous indiquez une distance, l'application propose plusieurs boucles cyclables
partant et revenant à votre position, vous en choisissez une, et vous roulez :
grande flèche à chaque changement de direction, annonces vocales, détection de
sortie de parcours, recalcul, enregistrement de la sortie et export GPX.

---

## Sommaire

- [En bref](#en-bref)
- [Fonctionnement](#fonctionnement)
- [Installer et lancer](#installer-et-lancer)
- [Configurer la clé d'accès](#configurer-la-clé-daccès)
- [Structure du projet](#structure-du-projet)
- [Compiler et tester](#compiler-et-tester)
- [Documentation](#documentation)
- [Confidentialité](#confidentialité)

---

## En bref

| | |
|---|---|
| Plateforme | iOS 17 et supérieur, iPhone |
| Langages et cadres | Swift 5.9, SwiftUI, MapKit, Core Location, SwiftData, AVFoundation |
| Moteur d'itinéraires | OpenRouteService (gratuit) — [pourquoi](docs/ROUTING_ENGINE.md) |
| Dépendances externes | aucune |
| Langue | français (structure prête pour l'anglais et l'allemand) |
| Version | 0.5.0 — voir [PROJECT_STATUS.md](PROJECT_STATUS.md) |

**Sans clé d'accès, l'application fonctionne quand même** : elle démarre en mode
démonstration, génère des circuits fictifs et permet d'essayer tout le parcours,
y compris la navigation simulée. C'est aussi ce mode qu'utilisent les tests.

## Fonctionnement

Le parcours principal tient en cinq gestes :

1. ouvrir l'application ;
2. choisir une distance (5, 10, 20, 30, 50 km ou une valeur libre) ;
3. appuyer sur **Créer une boucle** ;
4. comparer les propositions et en sélectionner une ;
5. appuyer sur **Démarrer la navigation**.

### Génération des boucles

L'application ne se contente pas de demander un itinéraire au serveur : elle en
calcule **six à neuf**, en faisant varier la graine de génération et
l'orientation, puis elle les filtre et les classe.

Sont systématiquement écartés :

- les circuits qui ne reviennent pas au point de départ ;
- les allers-retours déguisés — plus de 45 % du tracé emprunté deux fois ;
- les circuits dont la distance s'écarte de plus de 40 % de la demande ;
- le gravier, si vous l'avez refusé dans les réglages.

Les circuits retenus sont notés selon l'écart à la distance visée, la proportion
de tracé répété, les demi-tours, le revêtement, la part de pistes cyclables, le
dénivelé et la densité de manœuvres. Les trois meilleurs — dédoublonnés — vous
sont proposés.

Si aucun ne tombe dans la tolérance de ±5 %, une seconde passe corrige la
longueur demandée au moteur et relance les tentatives les plus prometteuses.
L'écart résiduel est affiché explicitement plutôt que masqué.

Les autoroutes et voies interdites aux vélos ne sont jamais empruntées : les
profils cyclistes d'OpenRouteService s'appuient sur les restrictions d'accès
d'OpenStreetMap.

### Navigation

- position suivie en temps réel, carte orientée dans le sens de marche ou nord
  en haut ;
- grande flèche et consigne en français pour chaque manœuvre, avec le nom de la
  voie et la distance restante avant le virage ;
- annonces vocales optionnelles à 400 m, 150 m et 40 m, et retour haptique avant
  chaque changement de direction ;
- vitesse instantanée, vitesse moyenne, distance parcourue, distance restante,
  temps écoulé et heure d'arrivée estimée ;
- **détection de sortie de parcours** avec seuil adapté à la précision GPS du
  moment et confirmation sur plusieurs relevés, pour éviter les fausses alertes ;
- **recalcul** vers un point de reprise situé *devant* vous — jamais un
  demi-tour quand une solution plus naturelle existe — au choix automatique,
  sur demande, ou désactivé.

L'interface de navigation est pensée pour un téléphone fixé sur un guidon :
gros caractères, chiffres monospacés, quatre boutons de 58 points de haut, et
aucune interaction complexe pendant que vous roulez.

### Enregistrement

Chaque sortie conserve sa date, sa durée, son temps de déplacement, sa distance,
ses vitesses moyenne et maximale, sa trace GPS, le circuit prévu, les écarts
constatés, le dénivelé et une estimation calorique — présentée comme telle.
L'historique permet de renommer, supprimer, exporter en GPX, partager et refaire
un parcours. L'import GPX est également possible.

L'enregistrement se poursuit **écran verrouillé** et en arrière-plan. Si
l'application est fermée involontairement, la sortie est retrouvée au
redémarrage et peut être reprise.

## Installer et lancer

Procédure détaillée : **[docs/INSTALL.md](docs/INSTALL.md)** — comptes Apple,
signature, TestFlight, App Store, autorisations, test sur iPhone réel.

En résumé :

```bash
git clone <ce-dépôt>
cd GPS
cp Secrets.example.xcconfig Secrets.xcconfig   # facultatif, voir ci-dessous
open App/VeloBoucle.xcodeproj
```

Dans Xcode : sélectionnez la cible **VeloBoucle**, choisissez votre équipe dans
*Signing & Capabilities*, remplacez le *Bundle Identifier* `ch.veloboucle.app`
par un identifiant qui vous appartient, branchez votre iPhone et lancez.

> Le projet Xcode est généré par script (`Scripts/generate_xcodeproj.py`) parce
> que ce dépôt est développé depuis Linux. Une fois généré, c'est un projet
> Xcode ordinaire : ouvrez-le, modifiez-le, ajoutez des fichiers normalement.
> Relancez le script seulement si vous préférez régénérer.

## Configurer la clé d'accès

Le calcul d'itinéraires réels utilise OpenRouteService, gratuit jusqu'à
2 000 requêtes par jour (une génération complète en consomme 6 à 9).

1. créez un compte sur <https://openrouteservice.org/dev/#/signup> ;
2. générez un jeton de type *Standard* ;
3. copiez le modèle et renseignez votre clé :

```bash
cp Secrets.example.xcconfig Secrets.xcconfig
# puis remplacez VOTRE_CLE_ICI par votre jeton
```

`Secrets.xcconfig` est exclu du dépôt par `.gitignore`. **Aucune clé ne doit
apparaître dans le code source.** La chaîne de résolution est, dans l'ordre : la
variable d'environnement `ORS_API_KEY`, puis la clé `ORSAPIKey` de l'`Info.plist`
alimentée par `Secrets.xcconfig`. Sans clé, l'application bascule en mode
démonstration et l'explique dans les Réglages.

## Structure du projet

```
GPS/
├── Core/                    paquet Swift « VeloCore » — logique métier pure
│   ├── Sources/VeloCore/
│   │   ├── Models/          coordonnées, circuits, consignes, sorties
│   │   ├── Geo/             géodésie : distances, caps, projections
│   │   ├── Networking/      client HTTP abstrait, erreurs francisées
│   │   ├── Routing/         client OpenRouteService
│   │   ├── LoopGeneration/  génération, filtrage et classement des boucles
│   │   ├── Navigation/      suivi de parcours, écarts, consignes
│   │   ├── Tracking/        filtrage GPS, statistiques de sortie
│   │   ├── GPX/             export et import GPX 1.1
│   │   └── Demo/            données et moteur simulés
│   └── Tests/VeloCoreTests/ 124 tests unitaires
├── App/
│   ├── VeloBoucle.xcodeproj
│   ├── Config/              xcconfig (Base, Debug, Release)
│   ├── VeloBoucle/
│   │   ├── App/             point d'entrée, injection de dépendances, onglets
│   │   ├── Services/        localisation, voix, haptique, secrets, journaux
│   │   ├── Persistence/     SwiftData
│   │   ├── Features/        vues-modèles (planification, sortie)
│   │   ├── Views/           SwiftUI : carte, planificateur, navigation,
│   │   │                    historique, réglages, composants partagés
│   │   ├── Demo/            simulation de déplacement, support des tests
│   │   └── Resources/       Info.plist, textes, traductions, assets
│   ├── VeloBoucleTests/     tests unitaires de la couche application
│   └── VeloBoucleUITests/   tests d'interface
├── Scripts/                 génération et vérification du projet
└── docs/                    architecture, moteur de routage, installation, build
```

Le découpage en deux couches est délibéré et détaillé dans
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Tout ce qui ne dépend pas d'un
framework Apple vit dans `VeloCore` et se teste sans simulateur.

## Compiler et tester

Sur macOS avec Xcode :

```bash
# Compilation
xcodebuild build -project App/VeloBoucle.xcodeproj -scheme VeloBoucle \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Tous les tests (unitaires + interface)
xcodebuild test -project App/VeloBoucle.xcodeproj -scheme VeloBoucle \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

Sur n'importe quelle machine, pour le cœur métier et les vérifications
structurelles :

```bash
./Scripts/check.sh
```

Ce script compile et teste `VeloCore`, analyse la syntaxe de toutes les sources
iOS, vérifie la cohérence du projet Xcode, met à jour les catalogues de
traduction et s'assure qu'aucun secret n'est versionné. Voir
[docs/BUILD.md](docs/BUILD.md) pour le détail, notamment sur la toolchain Swift
sous Docker.

## Documentation

| Fichier | Contenu |
|---|---|
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | plan de développement et découpage en versions |
| [PROJECT_STATUS.md](PROJECT_STATUS.md) | état courant, résultats de compilation et de tests |
| [CHANGELOG.md](CHANGELOG.md) | historique des versions |
| [LIMITATIONS.md](LIMITATIONS.md) | limites connues et améliorations envisagées |
| [PRIVACY.md](PRIVACY.md) | politique de confidentialité |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | architecture et décisions techniques |
| [docs/ROUTING_ENGINE.md](docs/ROUTING_ENGINE.md) | comparaison des moteurs et choix retenu |
| [docs/INSTALL.md](docs/INSTALL.md) | installation sur un iPhone réel |
| [docs/BUILD.md](docs/BUILD.md) | compilation, tests, outils |

## Confidentialité

Vos sorties, vos traces GPS et vos réglages **restent sur votre iPhone**. Aucun
compte n'est requis, aucune donnée n'est envoyée à un serveur de l'application —
il n'y en a pas.

Le service de calcul d'itinéraires ne reçoit que le strict nécessaire : une
seule coordonnée (votre point de départ) et la distance souhaitée pour une
génération ; deux coordonnées pour un recalcul. Jamais votre trace, jamais votre
historique, jamais d'identifiant.

Détail complet dans [PRIVACY.md](PRIVACY.md).

## Données cartographiques

Fonds de carte : Apple Plans. Calcul d'itinéraires : OpenRouteService, à partir
des données © contributeurs OpenStreetMap, sous licence ODbL.
