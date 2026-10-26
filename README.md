# Lab DevOps local

Lab Kubernetes avec **kind, ArgoCD, Helm, Traefik, cert-manager, PostgreSQL,
Redis, Prometheus et Grafana**.

**Windows :** suivre les étapes 1 à 10 ci-dessous, avec PowerShell.
**macOS / Linux :** suivre la section 11, avec Bash (sans PowerShell).

## 1. Préparer le PC

Si les prérequis sont déjà installés, passer à l’étape 2.

Activer la virtualisation dans le BIOS, puis dans **PowerShell administrateur** :

```powershell
wsl --install --no-distribution
```

Redémarrer Windows, puis lancer :

```powershell
wsl --update
wsl --set-default-version 2
winget install --exact --id Git.Git --source winget
winget install --exact --id Docker.DockerDesktop --source winget
winget install --exact --id Kubernetes.kind --source winget
winget install --exact --id Kubernetes.kubectl --source winget
winget install --exact --id Helm.Helm --source winget
```

Exécuter les commandes une par une. Fermer et rouvrir PowerShell après les
installations. Ouvrir **Docker Desktop**, choisir les conteneurs Linux avec
WSL 2 et attendre que le moteur démarre. Laisser son Kubernetes intégré désactivé.

## 2. Vérifier les outils

Dans PowerShell :

```powershell
docker version
git --version
kind version
kubectl version --client
helm version --short
```

Toutes les commandes doivent fonctionner. Docker doit afficher **Client et Server**.

## 3. Récupérer le projet

Pour une première installation :

```powershell
Set-Location ([Environment]::GetFolderPath('Desktop'))
git clone https://github.com/yazid9871/Devops-lab.git
Set-Location .\Devops-lab
```

Si le projet est déjà cloné, entrer dans son dossier puis lancer `git pull --ff-only`.

## 4. Installer le lab

Dans le dossier du projet, dans **le même terminal** :

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
.\scripts\Install-Lab.ps1
```

Accepter la confirmation PowerShell si elle apparaît. Attendre le message **PASS**.
Si une étape échoue, corriger l’erreur avant de relancer.

Le script installe les services et vérifie une restauration PostgreSQL dans une
instance séparée. Une relance conserve les données existantes.
Il approuve aussi l’autorité de certification locale pour ton utilisateur Windows.
Accepter la confirmation de sécurité Windows si elle apparaît.

## 5. Ouvrir l’application

Dans un PowerShell ouvert dans le dossier du projet :

```powershell
.\scripts\Open-Demo.ps1
```

Garder ce terminal ouvert et aller sur **[https://localhost:8443](https://localhost:8443)**.
L'accès à l'application passe uniquement par Traefik. Le port direct 8081 n'est plus utilisé.

Si le navigateur était déjà ouvert pendant l’installation, le fermer puis le rouvrir
pour qu’il prenne en compte le certificat.

## 6. Ouvrir Grafana

Dans un autre PowerShell :

```powershell
kubectl --context kind-devops-lab -n monitoring port-forward svc/grafana 3000:3000
```

Garder ce terminal ouvert. Aller sur **[Grafana](http://localhost:3000/d/devops-lab)**,
compte **admin**. Pour afficher son mot de passe, dans un autre terminal :

```powershell
$encoded = kubectl --context kind-devops-lab -n monitoring get secret lab-grafana-admin -o jsonpath='{.data.admin-password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

## 7. Publier une version et vérifier ArgoCD

Lab installé, Docker démarré, branche `main` propre et synchronisée avec GitHub.
Il faut avoir les droits d’écriture sur le dépôt. Depuis le dossier du projet,
dans un autre terminal :

```powershell
git status --short
.\scripts\Publish-Demo.ps1
```

Le pipeline construit et teste l’image, la publie dans le registry local, puis
met à jour la version dans Git. Si la publication réussit, conserver son commit
et vérifier le déploiement :

```powershell
$deployCommit = git rev-parse HEAD
.\scripts\Test-Deployment.ps1
kubectl --context kind-devops-lab -n argocd get applications
```

Rôle de chaque commande :

- `git status --short` affiche les fichiers modifiés. Aucun résultat signifie
  que le dossier est propre. Si des fichiers apparaissent, enregistrer ou annuler
  les changements avant de lancer le pipeline.
- `.\scripts\Publish-Demo.ps1` choisit une nouvelle version, construit et teste
  l’image Docker, la publie dans le registry local, puis crée et pousse sur GitHub
  un commit avec la nouvelle version.
- `$deployCommit = git rev-parse HEAD` conserve l’identifiant du dernier commit
  dans une variable. Après une publication réussie, c’est le commit à annuler
  pour revenir en arrière. La variable reste disponible dans ce terminal uniquement.
- `.\scripts\Test-Deployment.ps1` attend le bon commit dans ArgoCD, vérifie
  **Synced / Healthy**, l’image déployée et la réponse HTTPS avec la bonne version.
  Il affiche **PASS** si tout fonctionne. C’est ArgoCD qui déploie ; ce script vérifie.
- `kubectl --context kind-devops-lab -n argocd get applications` affiche l’état
  des applications gérées par ArgoCD.

ArgoCD synchronise automatiquement, sans commande de synchronisation manuelle.
Attendu : **PASS**, puis **Synced / Healthy** pour `devops-demo`. Actualiser
l’application pour voir la nouvelle version.

## 8. Tester un retour arrière

Dans **le même terminal**, après la publication réussie :

```powershell
git revert --no-edit $deployCommit
git push origin main
.\scripts\Test-Deployment.ps1
```

ArgoCD déploie automatiquement l’ancienne version. Attendu : **PASS** et ancienne
version visible après actualisation. L’ancienne image doit rester dans le registry.
Ce retour arrière concerne l’application, pas les données PostgreSQL.

Si le terminal a été fermé, retrouver le commit `Deploy demo v...` avec
`git log --oneline` et remplacer `$deployCommit` par son identifiant.

## 9. Vérifier, sauvegarder et restaurer PostgreSQL

Lab installé et Docker démarré, ouvrir PowerShell dans le dossier du projet :

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
.\scripts\Test-Postgres.ps1
kubectl --context kind-devops-lab -n data get pods,jobs,pvc
```

Le test vérifie la connexion, l’authentification, la lecture/écriture et le volume.
Attendu : **PASS**, `postgres-0` en **Running**, volume **Bound**.
PostgreSQL sert aux exercices de données ; l’application web n’y est pas connectée.

### Sauvegarder maintenant

```powershell
.\scripts\Backup-Postgres.ps1
```

Le script lance un Job qui utilise `pg_dump`, conserve l’archive dans le volume
`postgres-backups`, puis exporte une copie dans le dossier Windows `backups/`.
Il contrôle l’intégrité de cette copie avec **SHA256**.
Attendu : **PASS: backup and local SHA256 verification**.

Une sauvegarde est aussi planifiée toutes les **5 minutes** par le CronJob.
Les archives restent dans le volume après la fin du pod. La copie vers Windows
est effectuée par le script manuel, pas par chaque sauvegarde planifiée.

### Tester la restauration dans une nouvelle instance

```powershell
.\scripts\Test-Restore.ps1
```

Le test ajoute une ligne fictive à la source et crée **une nouvelle sauvegarde**.
Il prépare une instance PostgreSQL séparée avec un nouveau pod, un Service et
un volume vide. Un Job utilise `pg_restore`, puis le test compare les données
de `demo_items` et le schéma contrôlé avec les références de la source.
Il ne sélectionne pas l’archive d’une sauvegarde manuelle précédente.

Attendu : **RESTORE TEST: PASS** et **Source database kept running: True**.
La source reste en place, sans bascule vers la cible restaurée.

Lire le résultat :

- `database.dump: OK` : l’archive a passé le contrôle SHA256.
- `TARGET_EMPTY=1` : aucune table utilisateur n’était présente dans la cible.
- `Rows verified` : nombre de lignes vérifiées dans `demo_items`.
- `Restore` : durée de `pg_restore` seul.
- `Target creation and checks` : création de la cible, restauration et contrôles,
  **hors sauvegarde**.
- `Report` : chemin du rapport enregistré dans `backups/*-report.json`.

Chaque relance ajoute une ligne de test et conserve une nouvelle instance avec
son volume. Les archives et les cibles ne sont pas nettoyées automatiquement.
Les volumes et les copies Windows restent sur le même PC : ils ne protègent
pas contre sa perte. Si un test échoue, lire les logs avant de poursuivre.

## 10. Limiter les requêtes avec Traefik

L’application utilise un Middleware Traefik **RateLimit** : **5 requêtes/seconde
en moyenne**, avec un réservoir de **10 requêtes** pour les rafales. Une fois
épuisé, Traefik répond **HTTP 429 (Too Many Requests)** avant de contacter
l’application. Le réservoir se recharge progressivement, pas à chaque changement
de seconde. La règle couvre tous les chemins de cet Ingress, y compris `/healthz`.
Les sondes Kubernetes accèdent directement au pod et ne passent pas par cette règle.

### Installer la règle sur un lab existant

Depuis le dossier du projet, avec Docker démarré :

```powershell
git pull --ff-only
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
.\scripts\Deploy-Access.ps1
.\scripts\Test-Deployment.ps1
```

`Deploy-Access.ps1` prépare les CRD et active leur lecture par Traefik. ArgoCD
applique le Middleware et son lien avec l’Ingress depuis le chart Helm.
Pour une installation neuve, `Install-Lab.ps1` inclut déjà cette configuration.

### Tester les cas d’utilisation

Fermer les onglets qui rafraîchissent l’application pendant le test pour ne pas
consommer le même quota. L’autorité locale doit être approuvée par Windows,
comme lors de l’installation. Lancer :

```powershell
.\scripts\Test-RateLimit.ps1 -StartTunnel
```

Le script ouvre si nécessaire un tunnel temporaire vers Traefik, utilise HTTPS
avec la vérification normale des certificats, puis exécute ces scénarios :

| Cas | Résultat attendu |
| --- | --- |
| Navigation à faible débit | HTTP 200 |
| Rafale initiale de 10 requêtes | HTTP 200 après recharge complète |
| Envoi de 100 requêtes concurrentes | Certaines acceptées, d’autres en HTTP 429 |
| Budget de requêtes acceptées | Respect de la rafale + recharge pendant le test |
| Pause puis nouvelle requête | Retour à HTTP 200 |
| Alternance `/`, `/version`, `/healthz` | Un quota partagé par source |
| Paramètres d’URL différents | Aucun nouveau quota |
| Faux en-têtes `X-Forwarded-For` | Aucun nouveau quota |
| `User-Agent` différents | Aucun nouveau quota |
| Cookies différents | Aucun nouveau quota |
| Chemin inexistant sous charge | HTTP 404 puis HTTP 429 |
| Navigation après les tests | Application toujours disponible |

Attendu : **RATE LIMIT TEST: PASS (12 cases)**. Le nombre exact de 200/429
dépend de la durée des requêtes : le réservoir se recharge pendant l’envoi.
Le détail est enregistré dans `work/rate-limit-report.json`. Le script ne change
pas la règle et ferme uniquement le tunnel qu’il a lui-même ouvert.

### Changer les seuils et comprendre les limites

Modifier `ingress.rateLimit` dans `charts/devops-demo/values.yaml`, puis créer
et pousser un commit : ArgoCD applique la nouvelle configuration. `average`
divisé par `period` donne le débit ; `burst` donne la capacité du réservoir.
Pour désactiver la règle, mettre `enabled: false`, puis pousser ce changement.
Le script de test demande une règle active et des seuils modestes adaptés au lab.

La source est **l’adresse IP distante vue par Traefik**, pas un utilisateur
authentifié. Plusieurs navigateurs ou terminaux derrière le même tunnel peuvent
donc partager le quota. Changer un cookie ou annoncer une fausse IP ne crée
pas un utilisateur indépendant. Tester l’indépendance entre deux vraies IP
demande un accès réseau distinct ; les tests locaux ne prouvent pas ce cas.

Le quota est en mémoire dans **une seule réplique Traefik**, sans Redis. Il se
réinitialise au redémarrage du contrôleur ; plusieurs répliques auraient des
compteurs séparés. Cette règle limite la fréquence des requêtes, pas leur durée
ni un DDoS réseau. Elle s’applique au trafic qui passe par cet Ingress.

Références : [RateLimit](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/ratelimit/)
et [middlewares sur un Ingress](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/).

## 11. Utiliser le lab sur macOS ou Linux

Le parcours Bash utilise les mêmes manifests, charts, images et règles Traefik.
Il n’utilise ni `curl.exe`, ni le magasin de certificats Windows, ni PowerShell.
Il est écrit pour Bash 3.2 et versions suivantes. `make` est un raccourci facultatif.

### Préparer un Mac

Avec [Homebrew](https://brew.sh/) déjà installé :

```bash
brew install git kind kubectl helm jq
brew install --cask docker
open -a Docker
```

Attendre le démarrage de Docker Desktop en mode Linux. Bash, curl et OpenSSL
doivent être disponibles dans le terminal. Sur Apple Silicon, l’image de
l’application est construite pour l’architecture du nœud kind, sans forcer AMD64.
Chaque PC conserve son propre registry et construit sa propre image.

Sur Linux, installer Docker Engine, Git, Bash, curl, OpenSSL, jq, kind, kubectl
et Helm avant de continuer. Le compte doit pouvoir utiliser Docker sans `sudo`.
Utiliser les instructions officielles de [Docker](https://docs.docker.com/engine/install/),
[kind](https://kind.sigs.k8s.io/docs/user/quick-start/) et [Helm](https://helm.sh/docs/intro/install/).

### Installer et ouvrir

```bash
git clone https://github.com/yazid9871/Devops-lab.git
cd Devops-lab
bash scripts/lab.sh check
bash scripts/lab.sh install
bash scripts/lab.sh open
```

Si le projet est déjà cloné, entrer dans son dossier et faire `git pull --ff-only`.
`install` attend la synchronisation ArgoCD, teste l’application en HTTPS, déploie
PostgreSQL et Redis, teste une restauration et attend les workloads de supervision.
Cette vérification de supervision ne remplace pas les tests détaillés des alertes
du parcours Windows. Le rapport est `work/install-report-unix.json`.

Garder le terminal `open` actif, puis aller sur **https://localhost:8443**.
Sur Mac, l’installation importe l’autorité locale dans le trousseau de session ;
accepter la demande du système et rouvrir le navigateur si nécessaire.
Sur Linux, HTTPS est testé avec le certificat public explicite ; pour approuver
l’autorité dans le système et accéder avec le navigateur, lancer :

```bash
bash scripts/lab.sh trust-ca
```

Cette commande demande `sudo` sous Debian/Ubuntu et Fedora/RHEL. Un navigateur
avec son propre magasin de certificats peut demander un import séparé.
Seul le certificat **public** est exporté, jamais la clé privée de l’autorité.

### Les opérations courantes

| Opération | macOS / Linux |
| --- | --- |
| Préparer ou mettre à jour Traefik et cert-manager | `bash scripts/lab.sh access` |
| Déployer l’application via ArgoCD | `bash scripts/lab.sh deploy` |
| Vérifier la synchronisation et HTTPS | `bash scripts/lab.sh test` |
| Publier une nouvelle version | `bash scripts/lab.sh publish` |
| Sauvegarder et exporter sur le poste | `bash scripts/lab.sh backup` |
| Tester la restauration dans une nouvelle instance | `bash scripts/lab.sh restore` |
| Ouvrir Grafana | `bash scripts/lab.sh grafana` |
| Afficher le mot de passe Grafana | `bash scripts/lab.sh grafana-password` |

Pour publier : droits d’écriture GitHub, branche `main` propre et synchronisée.
Après une publication réussie, conserver le commit, puis vérifier :

```bash
deploy_commit=$(git rev-parse HEAD)
bash scripts/lab.sh test
```

Retour arrière, dans le même terminal :

```bash
git revert --no-edit "$deploy_commit"
git push origin main
bash scripts/lab.sh test
```

Une restauration Bash ajoute une ligne fictive et conserve sa cible et son volume,
comme le parcours Windows. Le rapport mesure la restauration seule en millisecondes
et l’ensemble création/restauration/contrôles en secondes entières, hors sauvegarde.
Les fichiers non suivis ne bloquent pas le parcours Bash ; les modifications des
fichiers suivis bloquent l’installation et la publication pour éviter un écart avec Git.

### Le même client Linux pour les tests de trafic

Sur Mac ou Linux :

```bash
bash scripts/lab.sh test-rate-limit
```

Sur Windows, pour exécuter exactement le même client :

```powershell
.\scripts\Test-RateLimitContainer.ps1
```

Les deux commandes créent un Job temporaire dans `demo`, avec la même image Python
Linux et le même fichier `scripts/tests/rate_limit_client.py`. Aucun Python n’est
nécessaire sur le poste. Le client se connecte au Service Traefik en HTTPS, avec
le nom TLS `localhost`, une autorité explicite et la vérification du certificat.
Le trafic de ce test ne passe pas par `port-forward` et ne dépend pas du trousseau
du poste. Le ConfigMap contient le code, les paramètres et le certificat public.

Attendu : **RATE LIMIT CONTAINER: PASS (12 cases)**. Les rapports datés et les logs
restent dans `work/`, avec une copie du dernier rapport dans
`work/rate-limit-container-report.json`. Le Job et son ConfigMap sont supprimés
à la fin ; les ressources de l’application restent en place.

Ce scénario utilise **un seul pod client** : il ne démontre pas l’indépendance
entre deux IP ni le passage par un Load Balancer OVH. L’ancien script Windows
`Test-RateLimit.ps1 -StartTunnel` reste disponible pour tester le chemin du navigateur.

### État de validation et réception sur Mac

Le client Linux commun est vérifié sur le lab depuis Windows. Le parcours Bash
est contrôlé par analyse statique et par des simulations de commandes sous Linux,
dont sauvegarde, restauration et lancement du client. Ces simulations ne prouvent
pas une installation complète : **une installation réelle sous Linux et sur un
vrai Mac Intel ou Apple Silicon reste à valider**.
La disponibilité d’une image ARM64 ne suffit pas à prouver cette installation.
Pour la réception par l’encadrant, suivre uniquement ce README, puis conserver :

1. Le modèle du Mac et son architecture (`uname -m`), les versions des outils.
2. Le résultat de `install` et son rapport, puis l’accès HTTPS dans le navigateur.
3. Une publication, un contrôle réussi et un retour arrière.
4. Une sauvegarde, une restauration et le rapport des 12 scénarios de trafic.

Tout blocage ou intervention supplémentaire doit être noté. Aucun accès à la
production ni secret de l’entreprise n’est nécessaire pour ces vérifications.

## 12. Observer Traefik dans Grafana

Le dashboard **Traefik - Trafic et limites** complète celui des pods.
Traefik expose ses métriques sur un Service **ClusterIP interne**, port 9100.
Prometheus les collecte toutes les **15 secondes** ; Grafana les affiche.
Il n’est pas nécessaire d’ouvrir le dashboard d’administration de Traefik.

Pour mettre à jour un lab existant, après `git pull --ff-only` :

```powershell
.\scripts\Deploy-Access.ps1
.\scripts\Deploy-Monitoring.ps1
```

Ou sur Mac/Linux :

```bash
bash scripts/lab.sh access
bash scripts/lab.sh monitoring
```

La mise à jour des paramètres de métriques redémarre Traefik et remet ses compteurs
à zéro. Pour une installation neuve, la configuration est déjà incluse.
Ouvrir le tunnel Grafana de la section 6 (ou `bash scripts/lab.sh grafana`), puis
aller sur **[Traefik dans Grafana](http://localhost:3000/d/traefik-lab)** avec
le même compte `admin` que pour le dashboard des pods.

Le dashboard montre :

- L’état de la collecte Traefik : **1 = disponible**, **0 = échec du scrape**.
- Le débit reçu, les codes HTTP et la part des réponses **429**.
- Les requêtes reçues et celles transmises au backend : les refus du Middleware
  ne sont pas envoyés au Service de l’application.
- Les erreurs **5xx**, séparées des refus 429.
- La latence **p95 des réponses 2xx**, en excluant les 429 rapides.
- Le CPU du processus en cœurs et sa mémoire résidente (RSS).

Les débits et la latence utilisent une fenêtre de **2 minutes**. Les nombres sur
**5 minutes** sont des estimations Prometheus : ils ne doivent pas être comparés
à l’unité près avec le compteur exact du générateur. Le p95 est une estimation
par histogramme ; sans trafic 2xx, il peut ne pas être disponible. Une absence de
données n’est pas une latence nulle. Le CPU et la RSS décrivent le processus,
pas toutes les ressources de son conteneur.

### Vérifier avec du trafic réel

Sur Windows :

```powershell
.\scripts\Test-RateLimitContainer.ps1 -ObserveTraefik
```

Sur Mac/Linux :

```bash
bash scripts/lab.sh test-traefik
```

Le client Linux vérifie la cible Prometheus, lance les 12 scénarios, puis attend
que la collecte reflète l’augmentation des requêtes, des 429 et du trafic backend.
Il contrôle aussi le p95, le CPU, la mémoire et la validité des requêtes PromQL
du dashboard. Attendu : **RATE LIMIT CONTAINER: PASS** et
**PASS: Traefik observation**. Le rapport contient une section `Observation`
dans `work/rate-limit-container-report.json` et dans sa copie datée.

Actualiser Grafana après le test. Attendre quelques collectes après un redémarrage.
Le test provoque volontairement des 429 ; cela ne démontre pas une panne de
l’application. Les compteurs observés peuvent aussi inclure d’autres requêtes
concurrentes du lab. La cible actuelle est un Service pour **une réplique** :
avec plusieurs pods Traefik, il faudra collecter chaque pod séparément pour
éviter de mélanger leurs compteurs.
