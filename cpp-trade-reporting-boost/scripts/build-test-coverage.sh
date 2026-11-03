#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Invalider les anciens rapports meme si un outil manque ou si les tests echouent.
mkdir -p reports
rm -f reports/coverage-sonarqube.xml reports/coverage-summary.json reports/sonarqube-measures.json \
  reports/tests-junit.xml \
  reports/coverage.html reports/coverage.*.html reports/coverage.css
cleanup_failed_report() {
  if [[ "$?" -ne 0 ]]; then
    rm -f reports/coverage-sonarqube.xml reports/coverage-summary.json
  fi
}
trap cleanup_failed_report EXIT

compiler="${CXX:-g++}"
for program in "$compiler" cmake ctest ninja gcovr; do
  command -v "$program" >/dev/null 2>&1 || {
    echo "Outil absent : $program. Lancer bash scripts/verify-environment.sh." >&2
    exit 1
  }
done

# Le gcov fourni avec le compilateur doit lire ses fichiers .gcno/.gcda.
gcov_command="${GCOV:-$("$compiler" -print-prog-name=gcov)}"
command -v "$gcov_command" >/dev/null 2>&1 || {
  echo "gcov absent : $gcov_command. Definir GCOV avec le gcov de la meme version que GCC." >&2
  exit 1
}
echo "Compilateur : $compiler ($("$compiler" -dumpfullversion -dumpversion))"
"$gcov_command" --version

# Repartir de zero empeche l'accumulation des compteurs entre deux executions.
rm -rf -- "$ROOT/build/coverage"

cmake -S . -B build/coverage -G Ninja \
  -DCMAKE_CXX_COMPILER="$compiler" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DENABLE_COVERAGE=ON \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build/coverage
# CTest >= 3.21 : resultat JUnit exploitable par Jenkins, meme si un test echoue.
ctest --test-dir build/coverage --output-on-failure \
  --output-junit "$ROOT/reports/tests-junit.xml"

# Un rapport HTML pour l'exploration locale et un XML générique pour SonarQube.
gcovr --root . \
  --object-directory build/coverage \
  --gcov-executable "$gcov_command" \
  --filter 'src/' \
  --filter 'include/' \
  --sonarqube reports/coverage-sonarqube.xml \
  --html-details reports/coverage.html \
  --json-summary reports/coverage-summary.json \
  --print-summary \
  build/coverage

echo
echo "Rapport HTML : $ROOT/reports/coverage.html"
echo "Rapport SonarQube XML : $ROOT/reports/coverage-sonarqube.xml"
echo "Resume JSON : $ROOT/reports/coverage-summary.json"
echo "Rapport de tests JUnit : $ROOT/reports/tests-junit.xml"
