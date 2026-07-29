#!/usr/bin/env bash
# Contrôles exécutables sans macOS ni Xcode.
#
# Ce script rassemble tout ce qui peut être vérifié depuis Linux :
#
#   1. compilation et tests du paquet VeloCore (Swift 6.1 via Docker) ;
#   2. analyse syntaxique de toutes les sources de l'application iOS ;
#   3. cohérence du projet Xcode généré ;
#   4. absence de secret dans le code versionné.
#
# Ce qui exige macOS — compilation complète de l'application, tests XCUITest —
# est documenté dans docs/BUILD.md.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE="${VELO_SWIFT_IMAGE:-mirror.gcr.io/library/swift:6.1-noble}"
failures=0

section() {
  echo
  echo "═══ $1"
}

check() {
  local label="$1"
  shift
  if "$@"; then
    echo "  ✓ $label"
  else
    echo "  ✗ $label"
    failures=$((failures + 1))
  fi
}

section "VeloCore — compilation"
check "swift build" ./Scripts/swift-docker.sh build

section "VeloCore — tests unitaires"
check "swift test" ./Scripts/swift-docker.sh test

section "Application iOS — analyse syntaxique"
# `swiftc -parse` ne résout pas les imports : il valide la syntaxe sans avoir
# besoin du SDK iOS, ce qui est exactement ce qui est possible ici.
if docker run --rm -v "$REPO_ROOT:/workspace" -w /workspace "$IMAGE" bash -c '
    status=0
    for file in $(find App -name "*.swift" | sort); do
      output=$(swiftc -parse "$file" 2>&1)
      if [ -n "$output" ]; then
        echo "$file"
        echo "$output" | head -5
        status=1
      fi
    done
    exit $status
  '; then
  echo "  ✓ toutes les sources analysées"
else
  echo "  ✗ erreurs de syntaxe"
  failures=$((failures + 1))
fi

section "Projet Xcode — cohérence"
check "validate_pbxproj" python3 Scripts/validate_pbxproj.py

section "Traductions — catalogues à jour"
check "extract_strings" python3 Scripts/extract_strings.py

section "Secrets — aucun jeton versionné"
# Recherche des motifs de clés OpenRouteService (jetons hexadécimaux longs) dans
# les fichiers suivis par git. Le fichier d'exemple ne contient qu'un texte
# substitutif et n'est donc jamais détecté.
if git grep -nIE '5b3ce3597851110001cf6248[0-9a-f]{8,}|ORS_API_KEY[[:space:]]*=[[:space:]]*[0-9a-f]{24,}' \
     -- . ':(exclude)Scripts/check.sh' > /dev/null 2>&1; then
  echo "  ✗ une clé API semble présente dans un fichier versionné"
  failures=$((failures + 1))
else
  echo "  ✓ aucun secret détecté"
fi

if git ls-files --error-unmatch Secrets.xcconfig > /dev/null 2>&1; then
  echo "  ✗ Secrets.xcconfig est suivi par git — il doit rester local"
  failures=$((failures + 1))
else
  echo "  ✓ Secrets.xcconfig non versionné"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "Tous les contrôles disponibles sont au vert."
else
  echo "$failures contrôle(s) en échec."
fi
exit "$failures"
