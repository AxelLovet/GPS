# Politique de confidentialité — VéloBoucle

*Dernière mise à jour : juillet 2026. Version de l'application : 0.5.0.*

## En une phrase

VéloBoucle ne collecte rien. Vos sorties, vos traces GPS et vos réglages restent
sur votre iPhone ; la seule information qui sort de l'appareil est le point de
départ que vous demandez de calculer, envoyé au service de cartographie le temps
d'une requête.

---

## 1. Aucun compte, aucun serveur

VéloBoucle ne demande ni inscription, ni adresse électronique, ni identifiant.
L'application ne dispose d'aucun serveur : il n'existe nulle part de base de
données contenant vos trajets.

## 2. Ce qui est enregistré, et où

Tout est stocké **localement sur votre iPhone**, dans l'espace privé de
l'application, protégé par le chiffrement du système :

| Donnée | Emplacement | Quand elle est écrite |
|---|---|---|
| Sorties terminées : date, durée, distance, vitesses, dénivelé, trace GPS complète, circuit prévu, écarts | base SwiftData de l'application | à l'enregistrement d'une sortie |
| Sortie en cours | fichier JSON dans le dossier Application Support | toutes les 10 secondes pendant une sortie |
| Réglages : profil de vélo, préférences de parcours, voix, haptique, politique de recalcul, poids | `UserDefaults` | à chaque modification |
| Clé d'accès OpenRouteService | `Info.plist`, issue de `Secrets.xcconfig` | à la compilation |

Ces données ne sont **jamais** transmises, ni à nous, ni à un tiers. Elles sont
supprimées avec l'application.

Elles peuvent figurer dans une **sauvegarde iCloud ou iTunes** de votre iPhone,
si vous en faites : c'est un mécanisme du système, hors du contrôle de
l'application.

## 3. Ce qui est envoyé à l'extérieur

Un seul service externe est contacté : **OpenRouteService**
(<https://openrouteservice.org>), qui calcule les itinéraires.

Il reçoit exactement ceci, et rien d'autre :

| Action | Données transmises |
|---|---|
| Créer une boucle | **une seule coordonnée** — votre point de départ —, la distance souhaitée, le profil de vélo, vos préférences de parcours, une graine numérique |
| Recalculer après une sortie de parcours | **deux coordonnées** — votre position actuelle et le point du circuit à rejoindre |

Ne sont **jamais** transmis : votre trace GPS, votre historique, la durée ou la
vitesse de vos sorties, votre poids, un identifiant d'appareil, votre nom.

Les requêtes portent votre clé d'accès OpenRouteService, qui permet à ce service
de compter votre usage au regard de son quota gratuit. L'usage que fait
OpenRouteService de ces requêtes relève de sa propre politique de
confidentialité : <https://openrouteservice.org/privacy-policy/>.

Le fond de carte est fourni par **Apple Plans**, intégré au système iOS. Les
requêtes de tuiles sont gérées par Apple selon sa politique de confidentialité.
L'application ne leur ajoute aucune information.

**En mode démonstration, aucune requête réseau n'est émise.**

## 4. Localisation

L'application demande l'accès à votre position pour trois usages, et aucun autre :

1. **placer le départ** de la boucle et centrer la carte ;
2. **vous guider** pendant la navigation, mesurer la distance restante et
   détecter une sortie de parcours ;
3. **enregistrer la trace** de votre sortie.

L'autorisation « Toujours » n'est demandée qu'au démarrage d'une sortie, et
uniquement pour que l'enregistrement se poursuive écran verrouillé. Vous pouvez
la refuser : l'application reste utilisable, l'enregistrement s'interrompt
simplement quand l'application passe en arrière-plan.

Si vous refusez toute localisation, vous pouvez encore choisir un point de départ
à la main sur la carte, générer des circuits et consulter votre historique.

Le suivi GPS est **arrêté** dès qu'aucun écran n'en a besoin, et sa précision est
réduite lorsque vous consultez simplement la carte.

## 5. Journaux de développement

Les journaux techniques de l'application (`OSLog`) ne contiennent :

- **aucune clé d'accès** ;
- **aucune position précise** — les rares coordonnées journalisées sont arrondies
  à quatre décimales, soit environ 11 mètres, ce qui ne permet pas d'identifier
  une adresse ;
- **aucune donnée personnelle**.

Ils restent sur l'appareil et ne sont transmis nulle part.

## 6. Ni publicité, ni mesure d'audience

Aucune régie publicitaire, aucun outil d'analyse, aucun traceur, aucun kit tiers
n'est intégré. L'application ne comporte aucune dépendance externe.

## 7. Vos données vous appartiennent

- **Consulter** : l'onglet Historique montre l'intégralité de ce qui est
  enregistré.
- **Exporter** : chaque sortie s'exporte en GPX, un format ouvert lisible par
  Garmin Connect, Strava, Komoot et la plupart des logiciels de cartographie.
- **Supprimer une sortie** : balayez sa ligne dans l'historique, ou utilisez le
  menu de sa fiche détaillée. La suppression est immédiate et définitive.
- **Tout supprimer** : désinstallez l'application. Toutes les données locales
  disparaissent avec elle.

## 8. Enfants

L'application ne s'adresse pas spécifiquement aux enfants et ne collecte aucune
donnée permettant d'identifier qui que ce soit.

## 9. Évolutions

Toute modification de cette politique sera publiée dans ce fichier et mentionnée
dans le [journal des versions](CHANGELOG.md). Aucune fonctionnalité de collecte
de données ne sera ajoutée sans que ce document soit mis à jour au préalable.

## 10. Contact

Ce projet est distribué sous forme de code source. Les questions relatives à la
confidentialité relèvent de la personne qui compile et installe l'application —
c'est-à-dire, dans le cas d'une installation personnelle, vous-même.
