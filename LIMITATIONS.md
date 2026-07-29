# Limites connues et améliorations futures

Ce document est délibérément franc : mieux vaut une limite écrite noir sur blanc
qu'une mauvaise surprise à 30 km de chez soi.

---

## 1. Ce qui n'a pas pu être vérifié ici

Le dépôt est développé depuis Linux, sans macOS ni Xcode.

**Vérifié réellement :**

- `VeloCore` compile (Swift 6.1) et ses **124 tests unitaires passent** ;
- les **29 sources de l'application iOS** passent l'analyse syntaxique du
  compilateur Swift (`swiftc -parse`) ;
- le projet Xcode est **structurellement cohérent** — analysé, toutes ses
  références résolues, toutes les sources rattachées à une cible.

**Non vérifié, faute d'environnement :**

- la **compilation complète de l'application iOS**. La syntaxe est validée, mais
  la vérification de types des appels SwiftUI, MapKit, CoreLocation et SwiftData
  exige le SDK Apple. Des erreurs de compilation résiduelles sont possibles —
  signature d'API légèrement différente, ambiguïté de surcharge — et se
  corrigeront à la première ouverture dans Xcode ;
- les tests de la couche application (`App/VeloBoucleTests`) et les tests
  d'interface (`App/VeloBoucleUITests`), écrits mais jamais exécutés ;
- le rendu visuel, l'ergonomie réelle sur un guidon, la consommation de batterie
  et le comportement du GPS en conditions réelles.

Les commandes exactes pour tout exécuter sur macOS sont dans
[docs/BUILD.md](docs/BUILD.md).

## 2. Limites du moteur de routage

- **La distance visée n'est pas garantie.** `round_trip` d'OpenRouteService
  traite la longueur comme un objectif approximatif ; l'écart brut atteint
  couramment 5 à 20 %. L'application le compense en générant plusieurs candidats
  et en appliquant une passe corrective, mais un écart résiduel supérieur à ±5 %
  reste possible. Il est alors **affiché explicitement**, jamais masqué.
- **Quota de 2 000 requêtes par jour** sur l'offre gratuite. Une génération
  complète en consomme 6 à 9 : environ 200 générations quotidiennes. Le
  dépassement produit un message clair et l'invitation à réutiliser un parcours
  enregistré.
- **Aucun calcul hors ligne.** Sans connexion, il est impossible de créer un
  nouveau circuit. En revanche, un circuit déjà chargé reste navigable et
  l'historique reste consultable.
- **La qualité dépend d'OpenStreetMap.** En Suisse et en Europe de l'Ouest la
  couverture cyclable est excellente ; ailleurs, une piste cyclable non
  cartographiée sera ignorée.
- **Départ imposé et points de passage ne se combinent pas** avec `round_trip`,
  qui n'accepte qu'une coordonnée. Le mode « points de passage » utilise donc une
  requête classique, en repli.

## 3. Limites fonctionnelles

- **Anglais et allemand non traduits.** L'infrastructure est complète — 169 clés
  extraites, trois catalogues générés, aucune chaîne en dur dans les vues — mais
  seul le français est renseigné. Traduire les fichiers `en.lproj` et `de.lproj`
  suffit ; aucun code n'est à modifier.
- **Pas d'icône d'application.** L'emplacement existe dans le catalogue d'assets,
  l'image reste à fournir.
- **Le dénivelé du circuit vient du moteur**, pas d'un modèle de terrain local :
  il est indisponible si la requête n'a pas demandé l'altitude.
- **Les calories sont une estimation grossière**, calculée par la formule MET à
  partir du poids et du temps de déplacement. Elle ignore le vent, la pente
  réelle, le matériel et la condition physique. L'interface le dit explicitement.
- **Pas de capteurs externes** : ni cardiofréquencemètre, ni capteur de puissance,
  ni cadence, ni ANT+ ou Bluetooth.
- **Pas de synchronisation** avec Strava, Komoot ou Garmin Connect. L'export GPX
  permet un transfert manuel.
- **Pas de widget, ni d'activité en direct, ni d'application Apple Watch.**
- **Le mode démonstration ne remplace pas la réalité** : ses circuits sont
  synthétiques et ne suivent aucune route existante. Il sert à découvrir
  l'interface et à faire tourner les tests, jamais à rouler.

## 4. Limites techniques

- **Précision du suivi en tunnel ou en canyon urbain.** Le filtre écarte les
  positions aberrantes, mais une perte prolongée de signal interrompt la
  progression jusqu'au retour du GPS.
- **Sortie de parcours en cas de perte de signal.** Si le GPS revient loin du
  tracé, l'application peut brièvement annoncer une sortie de parcours. Les trois
  relevés de confirmation et l'élargissement de la fenêtre de recherche limitent
  le phénomène sans l'éliminer.
- **Consommation de batterie.** Une navigation active avec l'écran allumé et le
  GPS en précision maximale reste coûteuse : comptez trois à cinq heures
  d'autonomie sur un iPhone récent. Désactiver « Garder l'écran allumé » aide
  nettement ; l'enregistrement se poursuit écran éteint.
- **Concurrence en mode Swift 5.** Le code est écrit pour être correct sous
  concurrence stricte, mais le projet est compilé avec
  `SWIFT_STRICT_CONCURRENCY = minimal`. Le passage au mode Swift 6 n'a pas pu
  être validé sans compilateur Apple.
- **Migration SwiftData non éprouvée.** Le schéma est simple et volontairement
  stable, mais aucune migration n'a encore été testée. En cas d'échec de
  chargement, l'application bascule sur un conteneur en mémoire plutôt que de
  refuser de démarrer.
- **Un seul instantané de sortie.** Deux sorties simultanées ne sont pas
  envisagées — cela n'aurait pas de sens à vélo.

## 5. Améliorations futures

Par ordre de valeur ajoutée décroissante, telle que je l'estime.

### Priorité haute

1. **Compiler et exécuter la suite complète sur macOS**, corriger ce que la
   vérification de types révélera, puis rouler une vraie sortie.
2. **Traduire l'anglais et l'allemand** — l'infrastructure est prête.
3. **Cache hors ligne des circuits générés**, pour repartir sans connexion.
4. **Écran de profil altimétrique** du circuit avant de partir : savoir où sont
   les montées change une sortie.

### Priorité moyenne

5. **Activité en direct et île dynamique** : consigne suivante sur l'écran
   verrouillé, sans déverrouiller le téléphone.
6. **Application Apple Watch** pour les consignes au poignet.
7. **Retour du sens de parcours** : proposer la même boucle dans l'autre sens,
   souvent très différente en dénivelé et en circulation.
8. **Favoris** : marquer des circuits sans avoir à les avoir roulés.
9. **Ajustement de la distance après génération** : allonger ou raccourcir une
   proposition sans tout relancer.
10. **Statistiques agrégées** : totaux hebdomadaires et mensuels, progression.

### Priorité basse

11. Import de circuits depuis Komoot ou Strava.
12. Partage d'un circuit par lien.
13. Capteurs Bluetooth (cardio, cadence, puissance).
14. Choix du moteur de routage dans les Réglages — l'abstraction existe déjà,
    seule l'implémentation d'un second client manque.
15. Moteur auto-hébergé, pour s'affranchir du quota.
16. Écriture d'un `LoopGenerationService` réellement hors ligne, sur un extrait
    OpenStreetMap embarqué.

## 6. Ce qui a été écarté, et pourquoi

- **MapKit comme moteur d'itinéraire** : `MKDirectionsTransportType` n'a pas de
  type vélo. Impossible d'obtenir un itinéraire cyclable, d'exclure les voies
  interdites ou de générer une boucle. Voir
  [docs/ROUTING_ENGINE.md](docs/ROUTING_ENGINE.md).
- **Un SDK de navigation tiers** (Mapbox Navigation) : plusieurs dizaines de
  mégaoctets, un modèle économique contraignant, et la perte du contrôle sur la
  détection de sortie de parcours — précisément la partie qu'il fallait bien
  faire.
- **Lissage de la trace GPS** : raccourcirait la distance réellement parcourue.
  Filtrer l'impossible sans déformer le reste est un meilleur compromis.
- **Un compte utilisateur** : inutile pour la première version, et contraire à la
  promesse que les données restent sur l'appareil.
- **SwiftLint** : dépendance d'outillage sans bénéfice immédiat sur un projet
  d'une seule personne au style déjà homogène.
