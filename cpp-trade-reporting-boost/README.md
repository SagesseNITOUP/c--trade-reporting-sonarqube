# Couverture C++ : Boost.Test → GCC/gcov → gcovr → SonarQube

Ce projet C++17 valide des transactions fictives. Il contient **12 cas de test Boost.Test** et une chaîne complète pour mesurer leur couverture, consulter les lignes couvertes dans un rapport HTML et importer le résultat dans SonarQube.

Les règles métier sont pédagogiques ; elles ne constituent pas une implémentation EMIR, MiFIR ou DTCC.

## Les outils et leur rôle

| Étape | Outil gratuit et open source | Résultat |
| --- | --- | --- |
| Compilation | GCC/G++, CMake, Ninja | Bibliothèque instrumentée avec `--coverage -O0 -g` |
| Tests | Boost.Test, lancé par CTest | Exécution des 12 cas unitaires |
| Mesure | GCC/gcov | Compteurs `.gcno` et `.gcda` |
| Rapports | gcovr | HTML, XML générique SonarQube, résumé JSON |
| Analyse C++ | SonarQube Community Build + sonar-cxx | Reconnaissance des fichiers C++ et import de la couverture |
| Envoi | SonarScanner CLI | Analyse du projet et attente du Quality Gate |

**SonarQube n'exécute pas les tests et ne calcule pas lui-même leur couverture** : il importe le rapport produit après leur exécution. La propriété utilisée ici est :

```properties
sonar.coverageReportPaths=reports/coverage-sonarqube.xml
```

Le XML provient de `gcovr --sonarqube`. JaCoCo concerne Java et n'intervient pas ici.

L'analyse C++ repose sur le **plugin tiers sonar-cxx**, gratuit et open source, sans abonnement SonarQube Developer Edition. Les versions sont fixées à **SonarQube Community Build 26.1.0.118079**, **sonar-cxx 2.3.1.1656** et **SonarScanner CLI 12.0.0.3214_8.0.1**. Le plugin exige Java 21 côté serveur et scanner ; cette paire serveur/plugin est documentée par ses mainteneurs. [Compatibilité sonar-cxx](https://github.com/SonarOpenCommunity/sonar-cxx/releases/tag/cxx-2.3.1)

## Démarrage Windows avec PowerShell

Se placer dans **`cpp-trade-reporting-boost/`**, le dossier qui contient `compose.yaml`. Il faut un moteur Docker Linux démarré et Docker Compose v2 accessible avec `docker compose`.

Cette route utilise Docker déjà accessible depuis Windows. **Docker Desktop est facultatif** : son utilisation dépend de ses conditions de licence. Pour une chaîne entièrement open source, utiliser Docker Engine et Compose dans Ubuntu/WSL ou sur Linux, comme décrit plus bas. [Conditions Docker Desktop](https://docs.docker.com/subscription/desktop-license/)

Avec PowerShell 7 :

```powershell
pwsh -File scripts/sonar.ps1 all
```

Avec Windows PowerShell :

```powershell
powershell -ExecutionPolicy Bypass -File scripts/sonar.ps1 all
```

Le premier lancement télécharge les images et le JAR sonar-cxx, vérifie le SHA-256 du JAR, démarre SonarQube, initialise le projet, compile le code, exécute les tests, génère les rapports et envoie l'analyse. Prévoir plusieurs minutes et suffisamment de mémoire pour SonarQube et la compilation.

Sur une **instance neuve** dont le compte est encore `admin` / `admin`, `init` remplace ce mot de passe par une valeur aléatoire, crée le projet privé `trade-reporting-boost-demo` et génère son jeton d'analyse. Les identifiants sont conservés dans **`.local/sonar-credentials.json`** pour les prochaines exécutions. Ce fichier contient des secrets en clair et est ignoré par Git : ne pas le partager.

Ouvrir ensuite [le projet SonarQube](http://localhost:9000/dashboard?id=trade-reporting-boost-demo) et consulter **Measures / Coverage**. Pour la connexion au navigateur, utiliser le compte et le mot de passe du fichier local.

Les actions peuvent aussi être lancées séparément :

| Commande | Effet |
| --- | --- |
| `pwsh -File scripts/sonar.ps1 coverage` | Compile dans un conteneur et produit les rapports, sans démarrer SonarQube |
| `pwsh -File scripts/sonar.ps1 start` | Installe le plugin vérifié et démarre SonarQube |
| `pwsh -File scripts/sonar.ps1 init` | Initialise le projet et les identifiants d'une instance neuve |
| `pwsh -File scripts/sonar.ps1 analyze` | Recalcule la couverture, lance le scanner et attend le Quality Gate |
| `pwsh -File scripts/sonar.ps1 all` | Enchaîne `start`, `init` et `analyze` |
| `pwsh -File scripts/sonar.ps1 status` | Affiche l'état de l'instance |

Pour une instance déjà configurée dont le mot de passe administrateur a changé, créer le projet et un jeton d'analyse dans son interface, puis définir `SONAR_TOKEN` dans l'environnement PowerShell. Le script privilégie ce jeton et n'utilise pas les identifiants locaux. La clé attendue reste `trade-reporting-boost-demo`.

## Rapports produits et lecture des résultats

Les sorties restent dans le projet, même lorsque les outils tournent en conteneur :

| Fichier | Utilisation |
| --- | --- |
| `reports/coverage.html` et ses fichiers voisins | Rapport détaillé, avec les lignes couvertes ou manquantes |
| `reports/coverage-sonarqube.xml` | Couverture générique importée par SonarQube |
| `reports/coverage-summary.json` | Résumé des compteurs et pourcentages pour l'automatisation |
| `reports/sonarqube-measures.json` | Mesures relues sur le serveur après une analyse PowerShell réussie |
| `reports/tests-junit.xml` | Résultat CTest au format JUnit, exploitable par Jenkins |
| `build/coverage/` | Exécutable de test et données brutes de couverture |

Depuis PowerShell :

```powershell
Start-Process reports/coverage.html
```

CTest lance **un exécutable contenant 12 cas Boost.Test** : l'affichage `1/1 tests passed` est donc normal. Les tests vérifient les devises EUR/USD/GBP, l'UTI manquant, les montants nul/négatif/infini/NaN, la devise interdite, la classe d'actif inconnue, la contrepartie inactive et la priorité de validation.

La **couverture des lignes** et la **couverture des branches** sont distinctes. GCC peut compter des branches liées aux exceptions ou au code généré par C++, même si toutes les règles métier ont été exercées. La métrique SonarQube **Coverage** combine les informations de lignes et de conditions ; elle peut donc différer du seul pourcentage de lignes affiché par gcovr. Comparer les mêmes métriques avant de conclure à un problème d'import. [Définition des métriques SonarQube](https://docs.sonarsource.com/sonarqube-community-build/user-guide/code-metrics/metrics-definition#coverage)

Lors de la première analyse, consulter la couverture de **l'ensemble du code**. Le panneau **New Code** dépend de la période et de la référence du nouveau code ; il peut ne pas afficher le même résultat.

Chaque analyse via les scripts recommence la compilation et les tests. Les anciens compteurs sont supprimés, la recherche des données est limitée à ce build, et les anciens XML/JSON sont invalidés afin qu'un échec ne réutilise pas une mesure précédente.

### Résultats vérifiés le 3 novembre 2026

L'exécution complète de `scripts/sonar.ps1 analyze` a réussi : les 12 cas Boost.Test passent, le scanner reconnaît trois fichiers CXX et importe la couverture de `src/trade_validator.cpp`. Le **Quality Gate est validé**.

| Mesure | gcovr 7.0 | SonarQube |
| --- | --- | --- |
| Lignes couvertes | 100 % — 15/15 | 100 % — aucune ligne non couverte |
| Fonctions couvertes | 100 % — 2/2 | — |
| Branches / conditions couvertes | 81,2 % — 26/32 | 81,3 % — six conditions non couvertes |
| Coverage combinée | — | 87,2 % |

L'écart de 0,1 point sur les branches vient de l'arrondi de **81,25 %**. Les 87,2 % combinent les 15 lignes couvertes et les 26 conditions couvertes sur un total de 47 éléments. Les mesures du serveur sont enregistrées dans `reports/sonarqube-measures.json`.

Le header actuel contient seulement des déclarations. Si du code métier inline ou des templates sont ajoutés et compilés uniquement par les tests, instrumenter aussi les unités concernées pour les mesurer. Les avertissements CXX sur les includes standard observés lors du scan n'ont pas empêché l'import de couverture ; leur résolution concerne la précision de l'analyse statique.

## Route entièrement open source : Docker Engine dans Ubuntu/WSL ou Linux

Installer **Docker Engine et le plugin Compose**, puis vérifier que le moteur est accessible à l'utilisateur courant. Suivre les [instructions officielles pour Ubuntu](https://docs.docker.com/engine/install/ubuntu/) et, si nécessaire, la [configuration après installation](https://docs.docker.com/engine/install/linux-postinstall/). Docker Desktop n'est pas nécessaire pour cette route.

Dans Ubuntu/WSL, se placer dans le même dossier projet et vérifier :

```bash
bash scripts/verify-environment.sh --docker
```

Ce mode contrôle Docker, Compose et l'accès au moteur. GCC, Boost et gcovr seront installés **dans l'image de compilation**, à partir d'Ubuntu 24.04.

Télécharger le plugin avant de démarrer le serveur :

```bash
mkdir -p sonar-extensions/plugins
curl -fL \
  https://github.com/SonarOpenCommunity/sonar-cxx/releases/download/cxx-2.3.1/sonar-cxx-plugin-2.3.1.1656.jar \
  -o sonar-extensions/plugins/sonar-cxx-plugin-2.3.1.1656.jar
echo 'b64327bf680a9fe4a04bb04f13ecbe679f4611c6908ec9eb0df027229d183a8a  sonar-extensions/plugins/sonar-cxx-plugin-2.3.1.1656.jar' | sha256sum --check
```

Continuer uniquement si la vérification affiche `OK` :

```bash
docker compose up -d sonarqube
docker compose logs -f sonarqube
```

Après le démarrage, `Ctrl+C` arrête le suivi des logs ; le serveur continue à fonctionner. Sur [SonarQube local](http://localhost:9000), se connecter avec `admin` / `admin` pour une instance neuve, changer le mot de passe, créer le projet local de clé **`trade-reporting-boost-demo`** et générer un jeton d'analyse dans **My Account > Security**.

Calculer puis envoyer la couverture :

```bash
read -rsp 'Jeton SonarQube : ' SONAR_TOKEN
echo
export SONAR_TOKEN
docker compose build coverage
docker compose run --rm coverage && docker compose run --rm scanner
unset SONAR_TOKEN
```

Le `&&` empêche l'envoi si la compilation, les tests ou la génération des rapports échouent. Le scanner rejoint SonarQube sur le réseau Compose et attend le résultat du Quality Gate.

## Variante : compiler directement dans Ubuntu/WSL

Cette variante conserve le même serveur SonarQube et remplace le conteneur de compilation par les outils Linux locaux :

```bash
sudo apt update
sudo apt install -y build-essential cmake ninja-build libboost-test-dev gcovr
bash scripts/verify-environment.sh
bash scripts/build-test-coverage.sh
```

Pour de meilleures performances sous WSL, on peut copier le projet dans le système de fichiers Linux, par exemple `~/dev/cpp-trade-reporting-boost`. Les chemins du XML sont relatifs au projet : scanner la même copie que celle utilisée pour le calcul de couverture.

Ouvrir le rapport depuis WSL :

```bash
explorer.exe "$(wslpath -w "$PWD/reports/coverage.html")"
```

Pour utiliser également le scanner en local, installer [SonarScanner CLI](https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/scanners/sonarscanner), avec **Java 21**, et placer `sonar-scanner` dans le `PATH`. Puis :

```bash
read -rsp 'Jeton SonarQube : ' SONAR_TOKEN
echo
export SONAR_TOKEN
export SONAR_HOST_URL='http://localhost:9000'
bash scripts/analyze-sonar.sh
unset SONAR_TOKEN
```

`analyze-sonar.sh` relance les tests et les rapports avant l'envoi. Si plusieurs versions de GCC sont installées, sélectionner un couple cohérent, par exemple `CXX=g++-13 GCOV=gcov-13 bash scripts/build-test-coverage.sh`. Les fichiers de couverture doivent être lus par le gcov correspondant au compilateur.

## Vérification et dépannage

- **La couverture manque dans SonarQube :** vérifier que `reports/coverage-sonarqube.xml` contient des éléments `<file path="src/...">`, que le scanner indexe les fichiers en langue `cxx` et que son capteur `Generic Coverage Report` importe le XML. Les chemins doivent correspondre aux sources du projet analysé.
- **La langue CXX manque :** vérifier le JAR dans `sonar-extensions/plugins/`, puis `docker compose restart sonarqube`. La propriété `sonar.cxx.file.suffixes=.cpp,.hpp` active le capteur communautaire, désactivé par défaut. Accepter l'avertissement relatif au plugin tiers dans l'interface si SonarQube le demande.
- **Le scanner demande Java :** utiliser l'image fixée dans `compose.yaml`, ou Java 21 pour le scanner local. Le serveur et le scanner ont chacun leur environnement Java.
- **Docker ou SonarQube ne démarre pas :** vérifier `docker info`, puis `docker compose logs --tail 100 sonarqube`. Le port local `9000` doit être libre. Cette configuration avec base embarquée et contrôles Elasticsearch simplifiés sert à l'apprentissage local.
- **Le Quality Gate échoue :** consulter les conditions du projet. Un rapport correctement importé peut coexister avec un Quality Gate rouge ; le scanner renvoie alors un échec parce qu'il attend ce résultat.
- **Les tests réussissent mais l'écran affiche peu de tests :** la couverture est importée ici ; l'import d'un rapport d'exécution des tests est un mécanisme séparé. Le nombre de cas Boost n'est pas transmis par le XML de couverture.

Pour arrêter les conteneurs en conservant les données SonarQube :

```bash
docker compose down
```

Les volumes conservent projets et comptes. L'option `-v` supprimerait ces données ; elle n'est pas nécessaire pour relancer une analyse.

## Exercice et automatisation

Commenter temporairement le cas `DeviseNonSupportee`, relancer `coverage` puis l'analyse et comparer les lignes manquantes dans le HTML et SonarQube. Rétablir ensuite le test et recalculer les rapports.

La chaîne est aussi disponible dans un **pipeline Jenkins**, avec publication des résultats JUnit, archivage des rapports et attente du Quality Gate. Le [guide Jenkins](docs/JENKINS.md) décrit le lancement local et le déclenchement automatique après une modification Git.

```powershell
pwsh -File scripts/jenkins.ps1 all
```

Ouvrir ensuite [le job Jenkins](http://localhost:8080/job/trade-reporting-coverage/). Les identifiants se trouvent dans `.local/jenkins-credentials.json`. Le jeton SonarQube utilise l'identifiant Jenkins `sonar-token` ; les secrets restent hors des sources et des artefacts.

## Références

- [Boost.Test](https://www.boost.org/doc/libs/release/libs/test/)
- [Options et filtres gcovr](https://gcovr.com/en/stable/manpage.html)
- [Format XML SonarQube de gcovr](https://gcovr.com/en/stable/output/sonarqube.html)
- [Plugin open source sonar-cxx](https://github.com/SonarOpenCommunity/sonar-cxx)
- [Installation des plugins SonarQube Community Build](https://docs.sonarsource.com/sonarqube-community-build/server-installation/plugins/install-a-plugin)
- [SonarScanner CLI](https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/scanners/sonarscanner)
