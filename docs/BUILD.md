# Compiler, tester, vérifier

## Ce qui est vérifiable, et où

| Vérification | macOS + Xcode | Linux (ce dépôt) |
|---|---|---|
| Compilation de `VeloCore` | oui | **oui** |
| Tests unitaires de `VeloCore` (124) | oui | **oui** |
| Analyse syntaxique des sources iOS | oui | **oui** |
| Cohérence du projet Xcode | oui | **oui** |
| Compilation de l'application iOS | oui | non — SDK iOS absent |
| Tests unitaires de la couche application | oui | non — SwiftData, UIKit |
| Tests d'interface XCUITest | oui | non — simulateur absent |

La séparation en deux couches (voir [ARCHITECTURE.md](ARCHITECTURE.md)) fait que
l'essentiel de la logique est dans la colonne « vérifiable partout ».

## Sur macOS

```bash
# Compilation
xcodebuild build \
  -project App/VeloBoucle.xcodeproj \
  -scheme VeloBoucle \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Tous les tests : VeloCore, couche application, interface
xcodebuild test \
  -project App/VeloBoucle.xcodeproj \
  -scheme VeloBoucle \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Tests d'interface seuls
xcodebuild test \
  -project App/VeloBoucle.xcodeproj \
  -scheme VeloBoucle \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:VeloBoucleUITests

# Tests de VeloCore seuls, sans simulateur
swift test --package-path Core
```

Aucune clé API n'est nécessaire : les tests d'interface lancent l'application
avec l'argument `-VeloBoucleUITesting`, qui force le générateur de circuits hors
ligne et injecte une position simulée.

## Sur Linux (ou n'importe quelle machine avec Docker)

```bash
./Scripts/check.sh
```

Ce script enchaîne :

1. `swift build` sur `VeloCore` ;
2. `swift test` sur `VeloCore` (124 tests) ;
3. `swiftc -parse` sur les 29 sources de l'application iOS — la syntaxe est
   validée sans avoir besoin du SDK Apple, puisque `-parse` ne résout pas les
   imports ;
4. `Scripts/validate_pbxproj.py` ;
5. `Scripts/extract_strings.py` ;
6. la recherche de secrets dans les fichiers versionnés.

### La toolchain Swift

`download.swift.org` est bloqué par la politique de sortie réseau de cet
environnement. La toolchain provient donc d'une image Docker officielle,
récupérée via le miroir Google de Docker Hub :

```bash
docker pull mirror.gcr.io/library/swift:6.1-noble
```

`Scripts/swift-docker.sh` encapsule l'appel :

```bash
./Scripts/swift-docker.sh build
./Scripts/swift-docker.sh test
./Scripts/swift-docker.sh test --filter NavigationTests
```

Pour utiliser une autre image ou une toolchain locale :

```bash
VELO_SWIFT_IMAGE=swift:6.0-noble ./Scripts/swift-docker.sh test
# ou, si swift est installé nativement :
swift test --package-path Core
```

## Le projet Xcode

### Pourquoi il est généré

`project.pbxproj` ne peut pas être produit par l'interface graphique depuis
Linux. `Scripts/generate_xcodeproj.py` le construit à partir de l'arborescence
des sources, de façon déterministe : les identifiants dérivent d'un hachage des
chemins, donc régénérer sans changement ne produit aucune différence.

```bash
python3 Scripts/generate_xcodeproj.py
python3 Scripts/validate_pbxproj.py
```

**Le projet généré est un projet Xcode ordinaire.** Une fois ouvert dans Xcode,
ajoutez des fichiers, changez des réglages, créez des cibles — tout fonctionne
normalement. Relancer le générateur écraserait ces modifications ; ne le faites
que si vous préférez rester sur le flux « génération ».

### Le validateur

`Scripts/validate_pbxproj.py` implémente un analyseur du format plist ancien
style — que `plistlib` ne sait pas lire — puis vérifie les invariants qui, s'ils
étaient rompus, produiraient un projet corrompu :

- syntaxe valide, fichier entièrement consommé ;
- chaque identifiant référencé correspond à un objet existant ;
- chaque objet possède un `isa` ;
- `rootObject` désigne bien un `PBXProject` ;
- chaque cible a ses phases, ses configurations Debug et Release, son produit ;
- chaque fichier référencé existe sur le disque ;
- **chaque source Swift présente sur le disque est compilée par une cible** —
  c'est le contrôle qui rattrape l'oubli le plus fréquent, un fichier ajouté mais
  jamais régénéré.

Sortie attendue :

```
Syntaxe valide — 127 objets
37 références de fichiers vérifiées sur le disque
29 sources Swift compilées

Projet cohérent.
```

## Traductions

```bash
python3 Scripts/extract_strings.py
```

Extrait les clés de `App/VeloBoucle/Resources/Strings.swift` et met à jour les
trois catalogues `fr` / `en` / `de`. **Les traductions déjà faites ne sont jamais
écrasées** : les clés nouvelles sont ajoutées en français, préfixées d'un
commentaire `À TRADUIRE`. Relancer après avoir traduit est sans risque.

## Ajouter un fichier au projet

```bash
# 1. créez le fichier au bon endroit
touch App/VeloBoucle/Views/Shared/MonComposant.swift

# 2. régénérez et vérifiez
python3 Scripts/generate_xcodeproj.py
python3 Scripts/validate_pbxproj.py
```

Depuis Xcode, l'ajout habituel par l'interface fonctionne aussi ; le validateur
le confirmera.

## Formatage et analyse statique

SwiftLint et swift-format ne sont pas intégrés : ils ajouteraient une dépendance
d'outillage sans bénéfice immédiat pour un projet d'une seule personne, et le
style est déjà homogène. Si vous souhaitez les ajouter, le point d'accroche
naturel est `Scripts/check.sh`.
