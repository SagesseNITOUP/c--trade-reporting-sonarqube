#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${SONAR_TOKEN:-}" ]]; then
  echo "Definir SONAR_TOKEN avec le jeton du projet SonarQube." >&2
  exit 1
fi
if ! command -v sonar-scanner >/dev/null 2>&1; then
  echo "Installer SonarScanner CLI dans WSL et l'ajouter au PATH." >&2
  exit 1
fi

# Toujours regenerer la couverture ; set -e empeche le scan si un test echoue.
bash "$ROOT/scripts/build-test-coverage.sh"
sonar-scanner -Dsonar.host.url="${SONAR_HOST_URL:-http://localhost:9000}" \
  -Dsonar.qualitygate.wait=true
