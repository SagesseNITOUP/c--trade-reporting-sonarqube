Plugin communautaire open source sonar-cxx

Version fixee : 2.3.1.1656
Fichier : sonar-cxx-plugin-2.3.1.1656.jar
SHA-256 : b64327bf680a9fe4a04bb04f13ecbe679f4611c6908ec9eb0df027229d183a8a

Source officielle :
https://github.com/SonarOpenCommunity/sonar-cxx/releases/tag/cxx-2.3.1

Depuis PowerShell, scripts/sonar.ps1 start (ou all) telecharge le JAR et
verifie son SHA-256 avant de demarrer SonarQube. Le JAR est ignore par Git.
Pour une installation manuelle Linux/WSL, suivre les commandes curl et
sha256sum du README principal. Ne pas prendre cxx-sslr-toolkit : ce fichier
n'est pas le plugin SonarQube. Ne conserver qu'une version du plugin ici.

Paire documentee par les mainteneurs : SonarQube Community Build
26.1.0.118079 + sonar-cxx 2.3.1, Java 21 cote serveur ET scanner.
Le plugin est tiers, sans support officiel SonarSource. Le projet utilise
sonar.cxx.file.suffixes=.cpp,.hpp pour activer la reconnaissance CXX.

Si le serveur etait deja lance avant l'installation du JAR :
docker compose restart sonarqube

Accepter l'avertissement de plugin tiers dans l'interface si demande.
