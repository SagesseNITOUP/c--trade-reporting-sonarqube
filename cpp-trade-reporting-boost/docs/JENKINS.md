# Automatiser la couverture C++ avec Jenkins

Le `Jenkinsfile` exécute toute la chaîne : **sources → compilation GCC → tests Boost.Test → rapports gcovr → publication SonarQube → Quality Gate**. Un échec de compilation, de test ou de génération de couverture arrête la publication. Un Quality Gate rouge fait échouer le build Jenkins.

Cette installation utilise Jenkins LTS **2.580.2 avec Java 21**, les outils C++ et le même SonarScanner que l'analyse locale. Jenkins et ses plugins sont gratuits et open source. Docker Engine avec Compose sous Linux/WSL permet de lancer cette stack sans dépendre de Docker Desktop.

## Démarrer et lancer un premier build

Depuis le dossier contenant `compose.yaml`, avec un moteur Docker Linux disponible :

```powershell
pwsh -File scripts/jenkins.ps1 all
```

Avec Windows PowerShell :

```powershell
powershell -ExecutionPolicy Bypass -File scripts/jenkins.ps1 all
```

La première construction de l'image et l'installation des plugins peuvent prendre plusieurs minutes. Les actions disponibles sont :

| Action | Résultat |
| --- | --- |
| `start` | Prépare les identifiants et démarre/configure Jenkins |
| `build` | Lance le job et attend son résultat |
| `status` | Affiche l'état de Jenkins et du job |
| `all` | Enchaîne le démarrage et un build complet |

Ouvrir [Jenkins](http://localhost:8080/) puis le job [trade-reporting-coverage](http://localhost:8080/job/trade-reporting-coverage/). L'utilisateur et le mot de passe générés se trouvent dans **`.local/jenkins-credentials.json`**. Les identifiants Jenkins sont distincts des identifiants SonarQube.

Le job local est créé automatiquement. Depuis son écran, cliquer sur **Build Now** ou **Build with Parameters** pour une nouvelle exécution. Le paramètre `USE_LOCAL_SOURCE` reste coché pour utiliser la copie locale du projet.

La définition de ce job local est une copie du `Jenkinsfile` au moment de sa création. Les sources C++ et les scripts sont recopiés à chaque build, mais une modification du `Jenkinsfile` lui-même demande de mettre à jour **Configure > Pipeline > Script**, en y collant son nouveau contenu, puis d'enregistrer. Le mode Git décrit plus bas récupère directement le `Jenkinsfile` versionné.

SonarQube doit être démarré et le projet `trade-reporting-boost-demo` initialisé. Pour une nouvelle copie du projet, ces opérations peuvent être effectuées avec `scripts/sonar.ps1 start` puis `scripts/sonar.ps1 init`, comme expliqué dans le [guide principal](../README.md).

## Ce que fait le pipeline

| Étape Jenkins | Travail effectué |
| --- | --- |
| Sources | Nettoie le workspace du job puis copie les sources locales autorisées, ou récupère le dépôt Git |
| Vérifier les outils | Vérifie GCC, CMake, Ninja, Boost.Test, gcov/gcovr et SonarScanner |
| Compilation, tests et couverture | Lance `scripts/build-test-coverage.sh` et produit les rapports |
| SonarQube et Quality Gate | Envoie le XML générique et attend le traitement du serveur |
| Fin du build | Publie les résultats JUnit et archive les rapports disponibles, même après un échec |

Le workspace Jenkins est indépendant du dossier de travail Windows. Seuls les répertoires et fichiers nécessaires sont montés en lecture seule sous `/opt/project`, puis copiés dans le workspace. Les dossiers `.local/`, `build/` et `reports/` du poste ne sont pas copiés.

Pour cette démonstration locale, les outils sont installés dans l'image Jenkins et l'exécution utilise le label **`linux-coverage`**, avec un seul exécuteur. Jenkins n'a pas besoin de lancer Docker pendant un build et ne reçoit aucun socket Docker. Pour un serveur partagé, employer un agent Linux dédié portant le même label et disposant des mêmes outils.

Les plugins Jenkins nécessaires sont Pipeline, Git, Credentials Binding et JUnit. Aucun plugin Jenkins SonarQube ni webhook SonarQube n'est requis ici : **SonarScanner attend lui-même le Quality Gate** avec `sonar.qualitygate.wait=true`.

## Identifiants et communication avec SonarQube

Le jeton SonarQube dédié à Jenkins est préparé dans **`.local/jenkins-sonar-token`** et importé dans le magasin d'identifiants Jenkins comme **Secret text**, sous l'identifiant **`sonar-token`**. Le pipeline ne le reçoit que pendant l'étape de publication, via `withCredentials` ; il ne contient aucun jeton en clair.

Les fichiers de `.local/` contiennent des secrets et sont ignorés par Git. Ne pas les versionner ni les joindre aux rapports. Le volume `jenkins_home` conserve les comptes, les identifiants, le job et l'historique des builds.

Depuis Jenkins, l'adresse du serveur est **`http://sonarqube:9000`**, grâce au réseau Compose. `http://localhost:9000` dans un conteneur Jenkins désignerait le conteneur Jenkins lui-même. Le navigateur Windows continue à utiliser [http://localhost:9000](http://localhost:9000/dashboard?id=trade-reporting-boost-demo).

Sur un Jenkins déjà existant, créer un identifiant **Secret text** avec l'ID `sonar-token`, y coller un jeton autorisé à analyser `trade-reporting-boost-demo`, puis régler le paramètre `SONAR_HOST_URL` avec l'adresse réellement accessible depuis l'agent.

## Lire les résultats

Dans un build Jenkins :

- **Console Output** montre la compilation, CTest, le résumé gcovr, l'import du XML et le résultat du Quality Gate.
- **Test Result** présente le rapport `reports/tests-junit.xml`. CTest déclare une suite qui lance les **12 cas Boost.Test** : Jenkins peut donc afficher un test CTest réussi. Le journal archivé contient le détail des cas Boost.
- **Artifacts** contient `reports/coverage.html`, ses fichiers CSS et HTML voisins, le résumé JSON, le XML SonarQube, le XML JUnit et le journal CTest disponible.

Pour consulter le HTML avec ses fichiers voisins, télécharger les artefacts du build ensemble, puis ouvrir `reports/coverage.html`. Le pipeline conserve les 20 derniers builds et les artefacts des 10 derniers builds.

Sur [le projet SonarQube](http://localhost:9000/dashboard?id=trade-reporting-boost-demo), consulter **Measures / Coverage** et la date de la dernière analyse. La couverture des lignes et la couverture combinée restent des métriques différentes ; voir l'explication du [guide principal](../README.md#rapports-produits-et-lecture-des-résultats).

## Déclencher automatiquement après une modification Git

Le dossier actuel n'est pas encore un dépôt Git. Le job local automatise toutes les étapes après son lancement ; le déclenchement sur modification nécessite une source Git.

Pour passer à ce fonctionnement :

1. Placer le contenu du dossier `cpp-trade-reporting-boost` à la racine d'un dépôt Git accessible depuis Jenkins, en conservant `.gitignore`. Ne pas ajouter les secrets ou les rapports.
2. Dans le `Jenkinsfile` de ce dépôt, modifier **la valeur par défaut de `USE_LOCAL_SOURCE` à `false`**. Cette modification doit être versionnée pour que les builds déclenchés automatiquement utilisent Git.
3. Dans Jenkins, créer un nouveau job de type **Pipeline**, par exemple `trade-reporting-coverage-git`.
4. Dans **Pipeline > Definition**, choisir **Pipeline script from SCM**, puis **Git**. Renseigner l'URL du dépôt et, s'il est privé, ses identifiants Jenkins. Choisir la branche réelle, par exemple `*/main`.
5. Régler **Script Path** sur `Jenkinsfile`, puis enregistrer et lancer un premier build. Ce build enregistre les paramètres et le déclencheur du pipeline.
6. Vérifier que `USE_LOCAL_SOURCE` est désactivé. Le `checkout scm` récupère alors la révision Git et les prochaines modifications déclenchent le pipeline grâce à `pollSCM('H/5 * * * *')`.

L'interrogation Git se fait environ toutes les cinq minutes et lance un build seulement si le dépôt a changé. Une fois l'URL du dépôt connue, ce job peut remplacer l'utilisation manuelle de la copie locale. Si le projet se trouve dans un sous-dossier du dépôt, adapter aussi le répertoire de travail du pipeline avant de compiler.

## Dépannage et arrêt

| Symptôme | Vérification |
| --- | --- |
| Build en attente d'un agent | Vérifier le label `linux-coverage` et la disponibilité d'un exécuteur |
| Identifiant `sonar-token` introuvable | Vérifier **Manage Jenkins > Credentials** et le type Secret text |
| SonarQube injoignable | Utiliser `http://sonarqube:9000` dans cette stack, puis vérifier l'état du serveur |
| Tests en échec | Lire Console Output et Test Result ; la publication SonarQube est volontairement arrêtée |
| Quality Gate rouge | Lire les conditions dans SonarQube ; le rapport peut avoir été importé malgré l'échec du build |
| Rapport JUnit absent en compilation native | Utiliser CTest 3.21 ou plus récent ; l'image Jenkins fournit une version compatible |
| Modifications locales sans nouveau build | Lancer le job local, ou configurer le dépôt Git et son déclencheur |

Pour arrêter seulement Jenkins en conservant son historique :

```bash
docker compose --profile ci stop jenkins
```

Pour le relancer avec le même volume :

```powershell
pwsh -File scripts/jenkins.ps1 start
```

## Références

- [Jenkins dans Docker](https://www.jenkins.io/doc/book/installing/docker/)
- [Syntaxe des pipelines Jenkins](https://www.jenkins.io/doc/book/pipeline/syntax/)
- [Identifiants dans un Jenkinsfile](https://www.jenkins.io/doc/book/pipeline/jenkinsfile/#handling-credentials)
- [Publication JUnit dans Jenkins](https://www.jenkins.io/doc/pipeline/steps/junit/)
- [Attendre le Quality Gate avec SonarScanner](https://docs.sonarsource.com/sonarqube-community-build/analyzing-source-code/analysis-parameters/parameters-not-settable-in-ui)
