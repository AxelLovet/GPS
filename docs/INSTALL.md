# Installer VéloBoucle sur un iPhone

Ce guide part du principe que vous n'avez jamais installé d'application depuis
Xcode. Chaque étape est détaillée.

> **Aucun identifiant Apple ne vous est demandé ici.** Vous vous connecterez
> vous-même dans Xcode, sur votre machine.

---

## Ce qu'il vous faut

- un **Mac** avec **Xcode 15 ou supérieur** (App Store, gratuit) ;
- un **iPhone sous iOS 17 ou supérieur** ;
- un **câble** pour relier l'iPhone au Mac (le sans-fil fonctionne aussi une fois
  l'appareil apparié) ;
- un **identifiant Apple** — un compte personnel gratuit suffit ;
- facultatif : une **clé OpenRouteService** gratuite. Sans elle, l'application
  démarre en mode démonstration et reste entièrement utilisable pour découvrir
  l'interface.

---

## 1. Ouvrir le projet

```bash
git clone <ce-dépôt>
cd GPS
open App/VeloBoucle.xcodeproj
```

Xcode récupère automatiquement le paquet local `VeloCore` (dossier `Core/`). Si
la barre latérale n'affiche pas *Package Dependencies*, faites
**File ▸ Packages ▸ Resolve Package Versions**.

## 2. Choisir votre équipe Apple

1. dans la barre latérale, cliquez sur le projet **VeloBoucle** (icône bleue) ;
2. sélectionnez la cible **VeloBoucle** ;
3. ouvrez l'onglet **Signing & Capabilities** ;
4. cochez **Automatically manage signing** ;
5. dans **Team**, choisissez votre compte. S'il n'apparaît pas :
   **Xcode ▸ Settings ▸ Accounts ▸ +**, puis connectez-vous avec votre
   identifiant Apple.

Répétez pour les cibles **VeloBoucleTests** et **VeloBoucleUITests** si vous
comptez lancer les tests sur l'appareil.

## 3. Changer le Bundle Identifier

L'identifiant fourni, `ch.veloboucle.app`, ne vous appartient pas : Xcode
refusera de signer avec.

Dans **Signing & Capabilities ▸ Bundle Identifier**, remplacez-le par un
identifiant unique, en notation inversée :

```
com.votrenom.veloboucle
```

Utilisez uniquement des lettres, des chiffres, des points et des tirets. Faites
la même chose pour les cibles de test, en conservant leurs suffixes `.tests` et
`.uitests`.

> Vous pouvez aussi modifier `PRODUCT_BUNDLE_IDENTIFIER` dans
> `Scripts/generate_xcodeproj.py` puis régénérer, si vous préférez que le choix
> soit conservé lors d'une régénération.

## 4. Ajouter votre clé OpenRouteService

Sans clé, passez cette étape : l'application fonctionnera en mode démonstration.

1. créez un compte sur <https://openrouteservice.org/dev/#/signup> ;
2. dans le tableau de bord, demandez un jeton (**Request a token**), type
   *Standard* ;
3. à la racine du dépôt :

```bash
cp Secrets.example.xcconfig Secrets.xcconfig
```

4. ouvrez `Secrets.xcconfig` et remplacez `VOTRE_CLE_ICI` par votre jeton :

```
ORS_API_KEY = 5b3ce...votre-jeton...
```

Sans guillemets, sans espace superflu. Le fichier est déjà rattaché aux
configurations Debug et Release et exclu du dépôt par `.gitignore`.

Vérification : lancez l'application, ouvrez **Réglages**. La ligne *Clé d'accès*
doit indiquer « Clé d'accès configurée ».

## 5. Autorisations de localisation

Elles sont déjà déclarées dans `App/VeloBoucle/Resources/Info.plist` et n'ont pas
besoin d'être modifiées :

| Clé | Quand elle s'affiche |
|---|---|
| `NSLocationWhenInUseUsageDescription` | au premier lancement |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | au démarrage d'une sortie, pour le suivi écran verrouillé |
| `NSLocationTemporaryUsageDescriptionDictionary` | si la position exacte est désactivée |

Sur l'iPhone, après installation, vérifiez dans **Réglages ▸ VéloBoucle ▸
Position** que **Position exacte** est activée : sans elle, le guidage manque de
précision et l'application le signale.

## 6. Capacités

Le mode d'arrière-plan **Location updates** est déjà déclaré dans l'`Info.plist`
(clé `UIBackgroundModes`). Xcode l'affiche dans *Signing & Capabilities ▸
Background Modes*. Aucune action n'est nécessaire ; ne le décochez pas, sinon
l'enregistrement s'arrêterait dès l'écran verrouillé.

Aucune autre capacité n'est requise : ni notifications, ni HealthKit, ni iCloud.

## 7. Connecter l'iPhone

1. reliez l'iPhone au Mac ;
2. déverrouillez-le et répondez **Se fier** à la question « Faire confiance à cet
   ordinateur ? » ;
3. sur l'iPhone, activez **Réglages ▸ Confidentialité et sécurité ▸ Mode
   développeur**, puis redémarrez l'appareil (iOS 16 et supérieur) ;
4. dans Xcode, sélectionnez votre iPhone dans le menu des destinations, en haut
   de la fenêtre.

## 8. Compiler et installer

Appuyez sur **⌘R**, ou sur le bouton ▶.

Depuis le terminal, l'équivalent est :

```bash
xcodebuild build \
  -project App/VeloBoucle.xcodeproj \
  -scheme VeloBoucle \
  -destination 'platform=iOS,name=Nom de votre iPhone'
```

## 9. Autoriser le développeur sur l'iPhone

Au premier lancement, iOS affiche « Développeur non fiable ». C'est normal avec
un compte gratuit.

Sur l'iPhone : **Réglages ▸ Général ▸ VPN et gestion de l'appareil ▸ [votre
identifiant Apple] ▸ Faire confiance**.

Relancez ensuite l'application depuis l'écran d'accueil.

## 10. Tester la localisation réelle

Dans le simulateur, il n'y a pas de vrai GPS. Deux possibilités :

- **Features ▸ Location ▸ Custom Location…** pour fixer une position (par
  exemple 46.5197 / 6.6323 pour Lausanne) ;
- ou, plus complet, activez le **mode démonstration** dans les Réglages de
  l'application : les boutons *Simuler un déplacement* et *Simuler une sortie de
  parcours* rejouent une sortie entière, consignes et recalcul compris.

Sur un iPhone réel, sortez à l'extérieur, attendez que la pastille d'état de
localisation disparaisse, puis créez une boucle de 5 km et démarrez la
navigation. Vérifiez :

- la position bleue se déplace ;
- la carte pivote dans le sens de marche ;
- la distance avant la prochaine manœuvre décroît ;
- écran verrouillé, l'indicateur bleu de localisation reste visible et la
  distance continue d'augmenter au retour dans l'application.

---

## Les quatre façons de distribuer l'application

| | Compte Apple personnel (gratuit) | Apple Developer Program (99 $/an) | TestFlight | App Store |
|---|---|---|---|---|
| Coût | gratuit | 99 $/an | inclus dans le programme | inclus dans le programme |
| Validité de l'installation | **7 jours**, à réinstaller ensuite | 1 an | 90 jours par version | illimitée |
| Nombre d'appareils | 3 applications actives, appareils enregistrés à la main | 100 appareils | 100 testeurs internes, 10 000 externes | tout le monde |
| Installation | câble + Xcode | câble + Xcode, ou distribution ad hoc | lien ou invitation par courriel | recherche dans l'App Store |
| Revue Apple | non | non | légère pour les testeurs externes | complète, plusieurs jours |
| Adapté à | usage personnel, essai | petite équipe, famille | bêta ouverte | diffusion publique |

### Compte personnel gratuit

Le plus simple pour commencer, et suffisant pour un usage personnel. La seule
contrainte réelle est la **péremption au bout de sept jours** : passé ce délai,
l'application refuse de s'ouvrir et il faut la réinstaller depuis Xcode. Aucun
réglage ni aucune sortie enregistrée n'est perdu lors d'une réinstallation.

### Apple Developer Program

Porte la validité à un an, permet TestFlight et la publication. C'est le choix
naturel si vous utilisez l'application régulièrement et ne voulez pas la
réinstaller chaque semaine.

### TestFlight

Distribution par lien, sans câble, mises à jour automatiques. Il faut téléverser
une archive (**Product ▸ Archive**, puis *Distribute App ▸ TestFlight*). Une
politique de confidentialité publique est exigée : [PRIVACY.md](../PRIVACY.md)
en fournit le contenu.

### App Store

Revue complète par Apple. Pour une application de navigation, prévoyez d'être
précis sur trois points : la justification de la localisation en arrière-plan
(l'enregistrement de la sortie), l'attribution des données OpenStreetMap, et le
fait que les calories affichées sont une estimation.

---

## Problèmes courants

**« Signing for VeloBoucle requires a development team »**
Étape 2 : sélectionnez votre équipe dans *Signing & Capabilities*.

**« Failed to register bundle identifier »**
L'identifiant est déjà pris. Étape 3 : choisissez-en un autre.

**« Untrusted Developer » au lancement**
Étape 9 : faites confiance au développeur dans les Réglages de l'iPhone.

**L'application se ferme au bout de sept jours**
Comportement normal d'un compte gratuit. Réinstallez depuis Xcode, ou souscrivez
au programme développeur.

**Aucun circuit n'est généré, message « Clé d'accès manquante »**
Étape 4, ou activez le mode démonstration dans les Réglages.

**La position n'apparaît pas**
Vérifiez **Réglages ▸ VéloBoucle ▸ Position**, et que **Position exacte** est
activée. À l'intérieur d'un bâtiment, le GPS peut mettre une minute à converger.

**L'enregistrement s'arrête quand l'écran se verrouille**
L'autorisation « Toujours » n'a pas été accordée. Réglages de l'iPhone ▸
VéloBoucle ▸ Position ▸ **Toujours**.
