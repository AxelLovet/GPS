#!/usr/bin/env python3
"""Vérifie la cohérence de App/VeloBoucle.xcodeproj/project.pbxproj.

Le format `pbxproj` est un plist « ancien style » (OpenStep), que `plistlib` ne
sait pas lire. Comme le projet est généré depuis Linux, sans Xcode pour ouvrir
le fichier et signaler une erreur, ce script en fait l'analyse syntaxique
complète puis vérifie les invariants qui, s'ils sont rompus, produiraient un
projet corrompu :

  * la syntaxe est valide et le fichier entièrement consommé ;
  * chaque identifiant référencé correspond à un objet existant ;
  * chaque objet possède un `isa` ;
  * `rootObject` désigne bien un PBXProject ;
  * chaque cible a ses phases de compilation, sa liste de configurations et son
    produit ;
  * tous les fichiers référencés existent réellement sur le disque.

Usage : python3 Scripts/validate_pbxproj.py
Code de sortie 0 si tout est correct, 1 sinon.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PROJECT_FILE = REPO_ROOT / "App/VeloBoucle.xcodeproj/project.pbxproj"
APP_DIR = REPO_ROOT / "App"

IDENTIFIER_PATTERN = re.compile(r"^[0-9A-F]{24}$")


class ParseError(Exception):
    pass


class OpenStepParser:
    """Analyseur du plist ancien style utilisé par Xcode."""

    def __init__(self, text: str) -> None:
        self.text = text
        self.position = 0

    def parse(self):
        self.skip_whitespace()
        value = self.parse_value()
        self.skip_whitespace()
        if self.position != len(self.text):
            raise ParseError(
                f"contenu inattendu à la position {self.position} : "
                f"{self.text[self.position:self.position + 60]!r}"
            )
        return value

    def skip_whitespace(self) -> None:
        while self.position < len(self.text):
            char = self.text[self.position]
            if char in " \t\n\r":
                self.position += 1
            elif self.text.startswith("//", self.position):
                end = self.text.find("\n", self.position)
                self.position = len(self.text) if end == -1 else end + 1
            elif self.text.startswith("/*", self.position):
                end = self.text.find("*/", self.position + 2)
                if end == -1:
                    raise ParseError("commentaire /* non fermé")
                self.position = end + 2
            else:
                return

    def parse_value(self):
        if self.position >= len(self.text):
            raise ParseError("fin de fichier inattendue")
        char = self.text[self.position]
        if char == "{":
            return self.parse_dict()
        if char == "(":
            return self.parse_array()
        if char == '"':
            return self.parse_quoted_string()
        return self.parse_bare_string()

    def parse_dict(self) -> dict:
        self.position += 1  # {
        result: dict = {}
        while True:
            self.skip_whitespace()
            if self.position >= len(self.text):
                raise ParseError("dictionnaire non fermé")
            if self.text[self.position] == "}":
                self.position += 1
                return result

            key = self.parse_value()
            self.skip_whitespace()
            if self.position >= len(self.text) or self.text[self.position] != "=":
                raise ParseError(f"'=' attendu après la clé {key!r}")
            self.position += 1
            self.skip_whitespace()
            value = self.parse_value()
            self.skip_whitespace()
            if self.position < len(self.text) and self.text[self.position] == ";":
                self.position += 1
            else:
                raise ParseError(f"';' attendu après la valeur de {key!r}")
            result[key] = value

    def parse_array(self) -> list:
        self.position += 1  # (
        result: list = []
        while True:
            self.skip_whitespace()
            if self.position >= len(self.text):
                raise ParseError("tableau non fermé")
            if self.text[self.position] == ")":
                self.position += 1
                return result
            result.append(self.parse_value())
            self.skip_whitespace()
            if self.position < len(self.text) and self.text[self.position] == ",":
                self.position += 1

    def parse_quoted_string(self) -> str:
        self.position += 1  # "
        characters: list[str] = []
        while self.position < len(self.text):
            char = self.text[self.position]
            if char == "\\":
                self.position += 1
                characters.append(self.text[self.position])
            elif char == '"':
                self.position += 1
                return "".join(characters)
            else:
                characters.append(char)
            self.position += 1
        raise ParseError("chaîne entre guillemets non fermée")

    def parse_bare_string(self) -> str:
        start = self.position
        while self.position < len(self.text) and self.text[self.position] not in " \t\n\r;,=(){}":
            self.position += 1
        if self.position == start:
            raise ParseError(
                f"jeton vide à la position {start} : {self.text[start:start + 40]!r}"
            )
        return self.text[start:self.position]


def collect_identifiers(value, found: set[str]) -> None:
    """Rassemble tous les identifiants de 24 hexadécimaux présents dans l'arbre."""
    if isinstance(value, str):
        if IDENTIFIER_PATTERN.match(value):
            found.add(value)
    elif isinstance(value, list):
        for item in value:
            collect_identifiers(item, found)
    elif isinstance(value, dict):
        for key, item in value.items():
            if IDENTIFIER_PATTERN.match(key):
                # Une clé du dictionnaire `objects` définit un objet ; les autres
                # (TargetAttributes) le référencent. Les deux sont vérifiées.
                found.add(key)
            collect_identifiers(item, found)


def resolve_file_path(objects: dict, file_ref_id: str) -> Path | None:
    """Reconstruit le chemin disque d'une PBXFileReference en remontant ses groupes."""
    reference = objects.get(file_ref_id)
    if not reference or reference.get("isa") != "PBXFileReference":
        return None
    if reference.get("sourceTree") == "BUILT_PRODUCTS_DIR":
        return None

    parts = [reference.get("path", "")]
    current = file_ref_id
    # Remonte au maximum dix niveaux : très au-delà de la profondeur réelle.
    for _ in range(10):
        parent = None
        for identifier, obj in objects.items():
            if obj.get("isa") in ("PBXGroup", "PBXVariantGroup"):
                if current in obj.get("children", []):
                    parent = (identifier, obj)
                    break
        if parent is None:
            break
        _, group = parent
        if group.get("path"):
            parts.insert(0, group["path"])
        current = parent[0]

    return APP_DIR / Path(*[p for p in parts if p])


def main() -> int:
    if not PROJECT_FILE.exists():
        print(f"Introuvable : {PROJECT_FILE}", file=sys.stderr)
        print("Lancez d'abord : python3 Scripts/generate_xcodeproj.py", file=sys.stderr)
        return 1

    text = PROJECT_FILE.read_text(encoding="utf-8")
    if not text.startswith("// !$*UTF8*$!"):
        print("En-tête d'encodage manquant en tête de fichier", file=sys.stderr)
        return 1

    try:
        root = OpenStepParser(text).parse()
    except ParseError as error:
        print(f"Syntaxe invalide : {error}", file=sys.stderr)
        return 1

    problems: list[str] = []
    objects = root.get("objects", {})
    print(f"Syntaxe valide — {len(objects)} objets")

    # 1. Tout identifiant référencé doit exister.
    referenced: set[str] = set()
    collect_identifiers(root, referenced)
    missing = sorted(referenced - set(objects))
    for identifier in missing:
        problems.append(f"identifiant référencé mais non défini : {identifier}")

    # 2. Tout objet a un isa.
    for identifier, obj in objects.items():
        if not isinstance(obj, dict):
            problems.append(f"objet {identifier} n'est pas un dictionnaire")
        elif "isa" not in obj:
            problems.append(f"objet {identifier} sans clé isa")

    # 3. rootObject désigne un PBXProject.
    root_object = root.get("rootObject")
    project = objects.get(root_object, {})
    if project.get("isa") != "PBXProject":
        problems.append(f"rootObject {root_object} n'est pas un PBXProject")

    # 4. Chaque cible est complète.
    targets = project.get("targets", [])
    if len(targets) != 3:
        problems.append(f"3 cibles attendues, {len(targets)} trouvées")

    for target_id in targets:
        target = objects.get(target_id, {})
        name = target.get("name", target_id)
        for key in ("buildPhases", "buildConfigurationList", "productReference", "productType"):
            if key not in target:
                problems.append(f"cible {name} : clé {key} manquante")

        for phase_id in target.get("buildPhases", []):
            phase = objects.get(phase_id, {})
            for build_file_id in phase.get("files", []):
                build_file = objects.get(build_file_id, {})
                if build_file.get("isa") != "PBXBuildFile":
                    problems.append(
                        f"cible {name} : {build_file_id} n'est pas un PBXBuildFile"
                    )
                elif "fileRef" not in build_file and "productRef" not in build_file:
                    problems.append(
                        f"cible {name} : PBXBuildFile {build_file_id} sans fileRef ni productRef"
                    )

        configuration_list = objects.get(target.get("buildConfigurationList"), {})
        names = {
            objects.get(config, {}).get("name")
            for config in configuration_list.get("buildConfigurations", [])
        }
        if names != {"Debug", "Release"}:
            problems.append(f"cible {name} : configurations {sorted(names)} au lieu de Debug/Release")

    # 5. Les fichiers référencés existent sur le disque.
    checked = 0
    for identifier, obj in objects.items():
        if obj.get("isa") != "PBXFileReference":
            continue
        path = resolve_file_path(objects, identifier)
        if path is None:
            continue
        checked += 1
        if not path.exists():
            problems.append(f"fichier introuvable sur le disque : {path.relative_to(REPO_ROOT)}")
    print(f"{checked} références de fichiers vérifiées sur le disque")

    # 6. Toute source Swift présente doit être compilée par une cible.
    compiled: set[Path] = set()
    for obj in objects.values():
        if obj.get("isa") != "PBXSourcesBuildPhase":
            continue
        for build_file_id in obj.get("files", []):
            file_ref = objects.get(build_file_id, {}).get("fileRef")
            path = resolve_file_path(objects, file_ref) if file_ref else None
            if path:
                compiled.add(path.resolve())

    on_disk = {
        path.resolve()
        for path in APP_DIR.rglob("*.swift")
        if ".build" not in path.parts
    }
    for path in sorted(on_disk - compiled):
        problems.append(
            f"source Swift absente du projet : {path.relative_to(REPO_ROOT)} "
            "(relancez Scripts/generate_xcodeproj.py)"
        )
    print(f"{len(compiled)} sources Swift compilées")

    if problems:
        print(f"\n{len(problems)} problème(s) :", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print("\nProjet cohérent.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
