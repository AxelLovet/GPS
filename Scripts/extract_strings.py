#!/usr/bin/env python3
"""Génère les catalogues Localizable.strings à partir de Strings.swift.

Tous les textes visibles par l'utilisateur sont déclarés une seule fois, dans
`App/VeloBoucle/Resources/Strings.swift`, sous la forme :

    static let cancel = value("common.cancel", "Annuler")

Ce script en extrait les couples (clé, texte français) et écrit :

  * `fr.lproj/Localizable.strings` — complet, langue de développement ;
  * `en.lproj/Localizable.strings` et `de.lproj/Localizable.strings` — mêmes
    clés, valeurs existantes préservées, nouvelles clés ajoutées en français et
    signalées par un commentaire `À TRADUIRE`.

Les traductions déjà présentes ne sont jamais écrasées : relancer le script
après avoir traduit est sans risque.

Usage : python3 Scripts/extract_strings.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE = REPO_ROOT / "App/VeloBoucle/Resources/Strings.swift"
RESOURCES = REPO_ROOT / "App/VeloBoucle/Resources"
LANGUAGES = ["fr", "en", "de"]
DEVELOPMENT_LANGUAGE = "fr"

# value("clé", "texte") — le texte peut être sur la ligne suivante.
CALL_PATTERN = re.compile(
    r'value\(\s*"(?P<key>[^"]+)"\s*,\s*"(?P<text>(?:[^"\\]|\\.)*)"\s*\)',
    re.DOTALL,
)
# "clé" = "valeur"; dans un fichier .strings existant.
ENTRY_PATTERN = re.compile(r'^"(?P<key>[^"]+)"\s*=\s*"(?P<value>(?:[^"\\]|\\.)*)"\s*;')


def extract_entries(source: Path) -> list[tuple[str, str]]:
    """Renvoie les couples (clé, texte français), dans l'ordre du fichier."""
    content = source.read_text(encoding="utf-8")
    entries: list[tuple[str, str]] = []
    seen: dict[str, str] = {}

    for match in CALL_PATTERN.finditer(content):
        key = match.group("key")
        text = match.group("text")
        if key in seen:
            if seen[key] != text:
                raise SystemExit(
                    f"Clé dupliquée avec deux textes différents : {key}"
                )
            continue
        seen[key] = text
        entries.append((key, text))

    return entries


def read_existing(path: Path) -> dict[str, str]:
    """Lit les traductions déjà faites, pour ne pas les perdre."""
    if not path.exists():
        return {}
    translations: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = ENTRY_PATTERN.match(line.strip())
        if match:
            translations[match.group("key")] = match.group("value")
    return translations


def write_catalog(
    language: str, entries: list[tuple[str, str]], existing: dict[str, str]
) -> tuple[int, int]:
    directory = RESOURCES / f"{language}.lproj"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "Localizable.strings"

    lines = [
        "/* VéloBoucle — textes de l'interface.",
        f"   Langue : {language}.",
        "   Fichier généré par Scripts/extract_strings.py à partir de Strings.swift.",
        "   Les traductions existantes sont conservées ; seules les clés nouvelles",
        "   sont ajoutées. */",
        "",
    ]

    translated = 0
    pending = 0
    current_prefix = None

    for key, french in entries:
        prefix = key.split(".", 1)[0]
        if prefix != current_prefix:
            lines.append(f"/* MARK: {prefix} */")
            current_prefix = prefix

        if language == DEVELOPMENT_LANGUAGE:
            lines.append(f'"{key}" = "{french}";')
            translated += 1
            continue

        if key in existing and existing[key] != french:
            lines.append(f'"{key}" = "{existing[key]}";')
            translated += 1
        else:
            lines.append(f'/* À TRADUIRE */ "{key}" = "{french}";')
            pending += 1

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return translated, pending


def main() -> int:
    if not SOURCE.exists():
        print(f"Introuvable : {SOURCE}", file=sys.stderr)
        return 1

    entries = extract_entries(SOURCE)
    print(f"{len(entries)} clés extraites de {SOURCE.name}")

    for language in LANGUAGES:
        path = RESOURCES / f"{language}.lproj" / "Localizable.strings"
        translated, pending = write_catalog(language, entries, read_existing(path))
        status = f"{translated} traduites"
        if pending:
            status += f", {pending} à traduire"
        print(f"  {language}.lproj/Localizable.strings — {status}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
