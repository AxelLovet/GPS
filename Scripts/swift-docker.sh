#!/usr/bin/env bash
# Exécute le compilateur Swift dans un conteneur Docker.
#
# L'environnement d'intégration continue de ce dépôt tourne sous Linux : il n'y a
# ni Xcode ni toolchain Swift native. Ce script fournit un `swift` utilisable pour
# compiler et tester le paquet VeloCore (code indépendant des frameworks Apple).
#
# Usage : Scripts/swift-docker.sh build|test|... [options]
set -euo pipefail

IMAGE="${VELO_SWIFT_IMAGE:-mirror.gcr.io/library/swift:6.1-noble}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec docker run --rm \
  -v "$REPO_ROOT:/workspace" \
  -w /workspace/Core \
  -e HOME=/tmp \
  "$IMAGE" \
  swift "$@"
