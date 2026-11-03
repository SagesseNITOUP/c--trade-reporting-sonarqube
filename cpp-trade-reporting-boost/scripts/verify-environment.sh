#!/usr/bin/env bash
set -euo pipefail

missing=0
check_program() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "OK : $1"
  else
    echo "ABSENT : $1" >&2
    missing=1
  fi
}

case "${1:-}" in
  --docker)
    check_program docker
    if [[ "$missing" -eq 0 ]]; then
      if docker compose version >/dev/null 2>&1; then
        echo "OK : Docker Compose"
      else
        echo "ABSENT : Docker Compose v2" >&2
        missing=1
      fi
      if docker info >/dev/null 2>&1; then
        echo "OK : moteur Docker accessible"
      else
        echo "ERREUR : moteur Docker inaccessible. Demarrer Docker et activer l'integration WSL." >&2
        missing=1
      fi
    fi
    exit "$missing"
    ;;
  "") ;;
  *) echo "Usage : bash scripts/verify-environment.sh [--docker]" >&2; exit 2 ;;
esac

compiler="${CXX:-g++}"
for program in "$compiler" cmake ctest ninja gcovr; do
  check_program "$program"
done

if command -v "$compiler" >/dev/null 2>&1; then
  gcov_command="${GCOV:-$("$compiler" -print-prog-name=gcov)}"
  check_program "$gcov_command"
  if printf '#include <boost/test/included/unit_test.hpp>\n' | \
      "$compiler" -x c++ -E - >/dev/null 2>&1; then
    echo "OK : Boost.Test"
  else
    echo "ABSENT : Boost.Test. Installer libboost-test-dev." >&2
    missing=1
  fi
fi

for program in docker sonar-scanner; do
  if command -v "$program" >/dev/null 2>&1; then
    echo "OPTIONNEL DISPONIBLE : $program"
  else
    echo "OPTIONNEL ABSENT : $program (inutile pour le rapport de couverture local)"
  fi
done

exit "$missing"
