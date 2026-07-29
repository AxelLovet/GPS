# Choix du moteur de calcul d'itinéraire

## Le point de départ : MapKit ne suffit pas

MapKit est excellent pour **afficher** une carte sur iOS, et l'application
l'utilise pour cela. En revanche, il ne peut pas servir de moteur d'itinéraire
ici, pour une raison simple et bloquante :

`MKDirectionsRequest.transportType` n'accepte que `.automobile`, `.walking`,
`.transit` et `.any`. **Il n'existe pas de type « vélo ».** Il en découle que
MapKit ne permet ni de produire un itinéraire cyclable, ni d'exclure les voies
interdites aux vélos, ni de connaître le revêtement, ni de générer une boucle.
`MKDirections` est de plus limité à un nombre restreint de requêtes par
application et par période, ce qui est incompatible avec un algorithme qui teste
une dizaine d'itinéraires candidats par génération.

Un moteur externe est donc indispensable.

## Comparaison des moteurs

| Critère | **OpenRouteService** | GraphHopper (API) | Valhalla (hébergé) | Mapbox Directions | Apple MapKit |
|---|---|---|---|---|---|
| Profils vélo | 4 (`regular`, `road`, `mountain`, `electric`) | 4 (`bike`, `racingbike`, `mtb`, `foot`) | 3 (`bicycle` avec sous-types) | 1 (`cycling`) | **aucun** |
| Génération de boucle native | **oui** (`options.round_trip`) | oui (`algorithm=round_trip`) | non | non | non |
| Exclusion des autoroutes | implicite (profils vélo OSM) | implicite | implicite | implicite | — |
| Instructions de navigation | oui, typées, **traduites en français**, n° de sortie de giratoire | oui, traduites | oui, verbeuses, très bonnes | oui, très bonnes | oui (mais pas vélo) |
| Recalcul hors parcours | requête A→B standard | idem | idem | endpoint dédié | — |
| Altitude / dénivelé | **oui** (`elevation: true`) | oui (payant selon offre) | oui | oui | — |
| Revêtement, type de voie | **oui** (`extra_info`: `surface`, `waytype`, `steepness`) | partiel (`details`) | partiel | non | — |
| Coût | **gratuit** — 2 000 req/j, 40 req/min | gratuit 500 req/j puis payant | gratuit si auto-hébergé | 100 000 req/mois gratuits puis payant | inclus |
| Couverture Suisse / Europe | OSM, très bonne | OSM, très bonne | OSM, très bonne | OSM + propriétaire | bonne (mais pas vélo) |
| Intégration iOS | REST/JSON, aucune dépendance | REST/JSON | REST/JSON | SDK lourd, ou REST | natif |
| Auto-hébergement possible | oui (AGPL) | partiel | oui (permissif) | non | non |

## Décision : OpenRouteService

**OpenRouteService** est retenu pour la première version.

Les arguments décisifs :

1. **La boucle est native.** ORS accepte une requête à une seule coordonnée
   accompagnée de `options.round_trip = {length, points, seed}` et renvoie un
   circuit fermé. C'est exactement la fonctionnalité centrale de l'application.
   Le paramètre `seed` permet, à distance et point de départ identiques,
   d'obtenir des circuits **réellement différents** — c'est ce qui alimente les
   propositions « recommandé / alternatif 1 / alternatif 2 ».
2. **Le profil `cycling-electric` existe.** Le cahier des charges demande de
   privilégier le vélo de route électrique ; ORS est le seul des moteurs
   comparés à proposer un profil électrique distinct, qui modélise
   l'assistance dans le calcul des durées en montée.
3. **Les métadonnées nécessaires aux écrans de comparaison sont fournies** :
   `ascent`/`descent` pour le dénivelé, `extra_info: ["surface","waytype","steepness"]`
   pour le pourcentage de pistes cyclables et le type de revêtement.
4. **Gratuit et suffisant.** 2 000 requêtes par jour couvrent très largement un
   usage personnel : une génération complète consomme 6 à 9 requêtes.
5. **Aucune dépendance.** Une requête `POST` JSON avec `URLSession` suffit ;
   aucun SDK tiers n'est ajouté au projet, conformément à la consigne de ne pas
   créer de dépendance inutile.

GraphHopper était le concurrent le plus proche (il propose aussi `round_trip`),
mais son offre gratuite de 500 requêtes/jour est plus contraignante et son
profil électrique n'existe pas.

## Ce que l'application envoie à OpenRouteService

C'est le seul service externe contacté par l'application, et il ne reçoit que
le strict nécessaire :

- pour une génération : **une seule coordonnée** (le point de départ), la
  distance visée, le profil vélo et une graine numérique ;
- pour un recalcul : **deux coordonnées** (position actuelle et point de
  reprise sur le circuit).

Aucun identifiant, aucun nom, aucune trace enregistrée, aucun historique n'est
transmis. La trace GPS de la sortie ne quitte jamais l'iPhone. Voir `PRIVACY.md`.

## Détails d'intégration

- Point d'entrée : `POST https://api.openrouteservice.org/v2/directions/{profil}/geojson`
- En-têtes : `Authorization: <clé>`, `Content-Type: application/json`,
  `Accept: application/geo+json`
- Profils utilisés : `cycling-electric` (défaut), `cycling-road`,
  `cycling-regular`, `cycling-mountain`
- Corps d'une génération de boucle :

```json
{
  "coordinates": [[6.6323, 46.5197]],
  "options": { "round_trip": { "length": 20000, "points": 5, "seed": 42 },
               "avoid_features": ["ferries"] },
  "instructions": true, "language": "fr", "elevation": true,
  "extra_info": ["surface", "waytype", "steepness"],
  "units": "m", "geometry_simplify": false
}
```

- Types d'instruction ORS pris en charge (`properties.segments[].steps[].type`) :

| Code | Manœuvre | Rendu français |
|---|---|---|
| 0 | Left | Tournez à gauche |
| 1 | Right | Tournez à droite |
| 2 | Sharp left | Tournez franchement à gauche |
| 3 | Sharp right | Tournez franchement à droite |
| 4 | Slight left | Serrez à gauche |
| 5 | Slight right | Serrez à droite |
| 6 | Straight | Continuez tout droit |
| 7 | Enter roundabout | Au rond-point, prenez la N<sup>e</sup> sortie |
| 8 | Exit roundabout | Quittez le rond-point |
| 9 | U-turn | Faites demi-tour |
| 10 | Goal | Vous êtes arrivé |
| 11 | Depart | Départ |
| 12 | Keep left | Restez à gauche |
| 13 | Keep right | Restez à droite |

## Limites connues du moteur retenu

- `round_trip` ne garantit pas la distance demandée : l'écart constaté est
  couramment de 5 à 20 %. L'application compense en générant plusieurs
  candidats avec des graines différentes et en corrigeant la longueur demandée
  (voir `LoopGenerationService`), puis affiche l'écart réel s'il dépasse ±5 %.
- `round_trip` est incompatible avec plusieurs coordonnées : un départ imposé
  et des points de passage choisis ne peuvent pas être combinés dans la même
  requête. Le mode « points de passage » utilise donc une requête classique
  multi-points, utilisée en repli.
- Le quota est appliqué par minute **et** par jour ; le client sérialise les
  requêtes et traduit les réponses `429` en une erreur explicite.

## Remplacer le moteur

Tout passe par le protocole `RoutingService` (`Core/Sources/VeloCore/Routing/RoutingService.swift`).
Écrire un client GraphHopper ou Valhalla revient à fournir une autre
implémentation de ce protocole et à la déclarer dans `AppDependencies`. Aucun
autre fichier n'a connaissance d'OpenRouteService.
