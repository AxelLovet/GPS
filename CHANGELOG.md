# Journal des versions

Les versions suivent le découpage annoncé dans
[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md). Le format s'inspire de
[Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

---

## 0.5.0 — Finalisation

Première version complète. Tous les critères d'acceptation du cahier des charges
sont couverts par le code ; ceux qui n'ont pas pu être vérifiés sur un appareil
réel sont listés dans [PROJECT_STATUS.md](PROJECT_STATUS.md).

### Interface et accessibilité

- Quatre onglets : Parcours, Sortie, Historique, Réglages.
- Interface pensée pour un guidon : boutons de 58 à 60 points, chiffres
  monospacés qui ne sautillent pas, contraste élevé, quatre actions maximum
  pendant la conduite.
- Mode clair et mode sombre, Dynamic Type, libellés VoiceOver sur les tuiles de
  statistiques, les flèches de manœuvre et les fiches de circuit.
- Tous les textes visibles regroupés dans `Strings.swift` ; catalogues `fr`,
  `en` et `de` générés par `Scripts/extract_strings.py`. Le français est complet,
  l'anglais et l'allemand attendent leur traduction.

### Gestion des erreurs

- Dix-neuf cas d'erreur typés, chacun avec un titre, une explication en français
  et au moins une action de récupération : réessayer, modifier la distance,
  changer de départ, ouvrir les Réglages, configurer la clé, passer en
  démonstration, utiliser un parcours enregistré.
- Codes HTTP d'OpenRouteService traduits en erreurs compréhensibles : 401 et 403
  → clé refusée, 429 → quota atteint, 404 et codes 2009/2010 → aucun itinéraire.
- Une réponse dont la longueur annoncée contredit la géométrie reçue est
  corrigée plutôt qu'affichée telle quelle.

### Batterie et qualité GPS

- Précision adaptative : 100 m et filtre de 50 m pour la consultation de la
  carte, meilleure précision possible et filtre de 5 m en navigation, arrêt
  complet quand aucun écran n'en a besoin.
- Arrière-plan activé uniquement pour une sortie réelle et si l'autorisation
  « Toujours » a été accordée.
- Réglage « Garder l'écran allumé », désactivable, avec sa contrepartie
  expliquée.

### Documentation

- `README.md`, `docs/ARCHITECTURE.md`, `docs/ROUTING_ENGINE.md`,
  `docs/INSTALL.md`, `docs/BUILD.md`, `PRIVACY.md`, `LIMITATIONS.md`,
  `PROJECT_STATUS.md`.
- `Scripts/check.sh` rassemble tout ce qui est vérifiable sans macOS.

---

## 0.4.0 — Enregistrement des sorties

### Ajouté

- `RideTracker` : distance, temps écoulé, temps de déplacement, vitesses moyenne
  et maximale, dénivelé positif et négatif, écarts de parcours.
- `LocationFilter` : rejet des positions dont la précision dépasse 65 m, des
  sauts impliquant plus de 90 km/h, des relevés hors séquence et des micro-
  déplacements à l'arrêt. Le dénivelé est cumulé par paliers de 3 m, sans quoi
  une sortie plate en afficherait des centaines de mètres.
- Estimation calorique par la formule MET, explicitement présentée comme une
  estimation.
- Persistance SwiftData de l'historique ; trace et circuit stockés en JSON
  externalisé.
- Instantané de la sortie en cours écrit toutes les dix secondes, et reprise
  proposée au redémarrage après une fermeture involontaire. Le temps passé hors
  de l'application n'est pas compté comme du temps de sortie.
- Historique : liste avec vignette du tracé dessinée sans carte, recherche,
  fiche détaillée, renommage, suppression, « refaire ce parcours ».
- Export GPX 1.1 d'une sortie ou d'un circuit, partage par la feuille système,
  import de fichiers GPX externes.
- Écran de fin de sortie : carte, statistiques, nom modifiable, enregistrement,
  export.

---

## 0.3.0 — Navigation

### Ajouté

- `RouteMatchingService` : projection sur la polyligne avec fenêtre glissante
  (120 m en arrière, 900 m en avant), indispensable sur une boucle qui se
  recoupe — sans elle, la navigation annoncerait l'arrivée dès les premiers
  mètres.
- `DeviationDetector` : seuil adaptatif à la précision GPS, confirmation sur
  trois relevés, hystérésis au retour. Aucune fausse alerte sur une trace suivie
  fidèlement avec ±12 m d'incertitude.
- `RejoinPointSelector` : point de reprise choisi devant l'utilisateur, jamais
  un demi-tour quand une solution plus naturelle existe.
- `RouteSplicer` : après un recalcul, l'itinéraire de rattrapage est recollé à
  la suite du circuit d'origine et les consignes restantes sont réindexées.
- `NavigationEngine` : consigne courante et suivante, distance à la manœuvre,
  distance et durée restantes, heure d'arrivée estimée mêlant l'estimation du
  moteur et l'allure réellement mesurée.
- Annonces vocales à 400 m, 150 m et 40 m, une seule fois par palier, jamais pour
  « continuez tout droit ». Session audio en `duckOthers` : la musique baisse au
  lieu de s'arrêter.
- Retours haptiques : léger à l'approche, marqué à l'imminence, motif
  d'avertissement en cas de sortie de parcours.
- Écran de navigation : carte orientée dans le sens de marche ou nord en haut,
  grande flèche, consigne, vitesse, moyenne, distance parcourue, distance
  restante, heure d'arrivée, pause, fin, recentrage, vue d'ensemble.
- Politique de recalcul configurable : automatique, sur demande, jamais.

---

## 0.2.0 — Génération de circuits

### Ajouté

- `OpenRouteServiceClient` : boucles natives (`options.round_trip`), itinéraires
  multi-points, profils vélo dont `cycling-electric`, instructions en français,
  altitude, revêtement et type de voie.
- `LoopGenerationService` : six à neuf tentatives par génération, mêlant graines
  différentes et boucles polygonales orientées, exécutées avec une concurrence
  bornée à trois requêtes.
- Passe corrective : si aucun candidat n'entre dans la tolérance de ±5 %, la
  longueur demandée est corrigée proportionnellement et les tentatives les plus
  prometteuses sont relancées.
- `RouteScorer` : rejet des boucles non fermées, des allers-retours déguisés
  (plus de 45 % de tracé répété), des écarts de distance supérieurs à 40 % et du
  gravier si l'utilisateur l'a refusé. Note tenant compte de l'écart de
  distance, des répétitions, des demi-tours, du revêtement, des pistes
  cyclables, du dénivelé et de la densité de manœuvres.
- Dédoublonnage géométrique : deux circuits partageant plus de 70 % de leur tracé
  ne sont pas proposés ensemble.
- `WaypointLoopPlanner` : boucles polygonales orientées, seul moyen d'honorer une
  direction de départ préférée, `round_trip` n'exposant qu'une graine.
- Écran de chargement avec progression réelle et annulation ; écran de
  comparaison affichant carte, distance, durée, dénivelé, part de pistes
  cyclables et avertissements pour chaque proposition ; écran d'aperçu avec la
  liste des principales indications.

---

## 0.1.0 — Fondation

### Ajouté

- Paquet SwiftPM `VeloCore`, séparé de l'application, compilable et testable
  sans Xcode.
- Modèles : `GeographicCoordinate`, `CyclingRoute`, `RouteCandidate`,
  `RouteSegment`, `NavigationInstruction`, `RideSession`, `RecordedRide`,
  `CyclingProfile`, `RoutingPreferences`, `LocationSample`, `RouteDeviation`.
- Géodésie : haversine, caps, projection sur segment en plan local, barycentre.
- `HTTPClient` abstrait, permettant de tester le client de routage sans réseau
  ni clé API.
- `LocationService` : gestion complète des états d'autorisation, précision
  adaptative, conversion vers les types de `VeloCore`.
- Projet Xcode généré par script, avec validateur du format `pbxproj`.
- Chaîne de résolution des secrets sans aucune clé dans le code source.
- Mode démonstration entièrement isolé : moteur de routage simulé, fabrique de
  circuits déterministe, simulateur de déplacement.
