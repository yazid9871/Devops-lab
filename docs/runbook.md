# Runbook du lab

Commandes à lancer dans **PowerShell, depuis le dossier du projet**.
Docker Desktop doit être ouvert et le lab installé avec le [README](../README.md).
Si une commande échoue, s'arrêter et lire son message.

## Périmètre et correspondance avec la référence Sobrus

Ce runbook contient les opérations déjà implémentées dans le lab. Son extension
vers les technologies Sobrus est suivie dans la [comparaison détaillée](comparaison-sobrus.md).
Le cahier des charges « Plateforme de référence locale » reste prioritaire : il
autorise Kustomize et CronJob pg_dump. Les compléments du tableau ci-dessous sont
des extensions possibles, pas des prérequis supplémentaires pour ce livrable.
Les résultats historiques se trouvent dans les comptes rendus `validation-*.md`.
Au contrôle du 19 octobre 2026, Docker et l'API Kubernetes étaient inaccessibles :
les procédures n'ont pas été rejouées à cette date.

| Rubrique d'exploitation | Procédure locale disponible | Complément à implémenter et tester |
| --- | --- | --- |
| Registry | [Registry local](registry.md), publication ci-dessous | Authentification/TLS ; fonctions Harbor à examiner |
| Accès web et certificats | [Traefik et cert-manager préparés](https-local.md), tunnel HTTPS local | Déploiement, validation HTTPS et observation du renouvellement à réaliser |
| Stockage | Contrôle des PVC ci-dessous | Exercice Rook/Ceph séparé, selon les ressources |
| Supervision | Diagnostic ci-dessous et [guide](supervision.md) | Collecte des nouveaux composants et test d'alerte de bout en bout |
| Sauvegardes SQL | Sauvegarde et restauration PostgreSQL ci-dessous | Restic vers stockage objet, archive choisie ; exercice MySQL si retenu |
| Sauvegarde Kubernetes | Pas encore de procédure Velero | Backup et restauration dans un namespace témoin distinct |
| GitOps et environnements | Publication et rollback ci-dessous ; [chart Helm préparé](helm.md), non déployé | Valider la transition Helm ; valeurs dev/staging, AppProjects et RBAC restent à ajouter |
| Sécurité | Pas encore de procédure Trivy/Falco | Rapports Trivy Operator et événement de test Falco |
| Nettoyage et VPN | Pas de procédure implémentée | Identifier l'opérateur ; examiner un exercice VPN séparé |

Chaque nouvelle procédure doit préciser objectif, prérequis, effets, commandes,
résultat attendu, diagnostic, retour arrière et preuve datée. Une rubrique
« à implémenter » ne doit pas être présentée comme validée.

## 0. Vérifier le lab avant une opération

```powershell
git status --short
git branch --show-current
kubectl --context kind-devops-lab get nodes
kubectl --context kind-devops-lab get pods -A
kubectl --context kind-devops-lab -n argocd get applications
kubectl --context kind-devops-lab -n data get pvc
```

**Attendu :** nœud `Ready`, applications ArgoCD `Synced / Healthy`, volumes
PostgreSQL et sauvegardes `Bound`. Un pod de Job en état `Completed` est normal.
Avant une publication, la branche doit être `main` et `git status --short` vide.
Le script de publication vérifie aussi la synchronisation avec `origin/main`.

En cas de pod en erreur, relever son namespace et son nom, puis utiliser
`kubectl --context kind-devops-lab -n <namespace> describe pod <nom>` et
`kubectl --context kind-devops-lab -n <namespace> logs <nom> --all-containers --tail=50`
en remplaçant les valeurs entre chevrons. Conserver le message d'erreur avant correction.
Ne supprimer aucune donnée, aucun cluster ni volume sans accord.

Pour les interfaces : [commandes d'accès](acces-interfaces.md).
Pour la soutenance : [déroulé de 10 minutes](presentation-10-minutes.md).

## 1. Déployer l'application

Pour le premier déploiement sur un lab déjà préparé :

L'application utilise désormais le chart `charts/devops-demo`. Les fichiers de
cette évolution doivent être publiés sur GitHub avant de lancer le script.
La transition Helm n'a pas encore été déployée ni testée : voir le [guide Helm](helm.md).
Les contrôleurs Traefik et cert-manager ainsi que l'autorité locale doivent être
préparés avant l'application, via `scripts/Deploy-Access.ps1`. L'installation
complète le fait automatiquement. Aucune de ces nouvelles procédures n'a été exécutée.

```powershell
.\scripts\Deploy-Demo.ps1
```

Pour publier une nouvelle version, les changements doivent être enregistrés et
poussés sur `main`, avec un dépôt propre et une identité Git configurée :

La lecture publique en HTTPS ne donne pas le droit de pousser : le compte utilisé
doit avoir les droits d'écriture sur le dépôt. Plusieurs labs suivant le même dépôt
recevront les modifications de configuration, mais leurs registries restent propres
à chaque PC. Vérifier la présence de l'image sur les PC concernés avant ce scénario.

```powershell
.\scripts\Publish-Demo.ps1
$deployCommit = git rev-parse HEAD
.\scripts\Test-Deployment.ps1
```

**Attendu :** `PASS`, nouvelle version accessible et ArgoCD `Synced / Healthy`.
Le script construit et teste l'image, la publie dans le registry local, puis pousse
son tag dans Git. ArgoCD applique le changement ; cela peut prendre quelques minutes.
Le commit de publication modifie `app/VERSION` et `charts/devops-demo/values.yaml`.
Les autres composants restent gérés avec Kustomize.

## 2. Revenir à la version précédente

Après une publication réussie, dans le même terminal :

```powershell
git revert --no-edit $deployCommit
git push origin main
.\scripts\Test-Deployment.ps1
```

**Attendu :** `PASS` avec l'ancienne version. Le rollback ajoute un commit et
réutilise l'ancienne image. Si le terminal a été fermé, retrouver le commit de
publication avec `git log --oneline` et utiliser son SHA à la place de `$deployCommit`.
Vérifier qu'il n'a pas déjà été annulé. Le retour arrière passe par Git, car
ArgoCD corrigerait un changement fait avec `kubectl rollout undo`.
Ce scénario ne valide pas le retour arrière d'une migration de base de données.

## 3. Restaurer une sauvegarde PostgreSQL

Les sauvegardes automatiques tournent toutes les cinq minutes. Pour en créer une
immédiatement et exporter son archive dans `backups/` sur Windows :

```powershell
.\scripts\Backup-Postgres.ps1
```

Pour exécuter le scénario de restauration testé :

```powershell
.\scripts\Test-Restore.ps1
```

Ce script ajoute une ligne fictive, crée une nouvelle sauvegarde, puis la restaure
sur une **nouvelle instance vide**, avec son propre volume. La base source reste
en place. La cible doit être vide et le SHA-256 de l'archive conforme.

**Attendu :** `PASS: full database restored`, données et schéma identiques.
Le nom de la cible, l'archive et les durées figurent dans `backups/*-report.json`.
Le test conserve sa cible ; chaque relance crée une instance supplémentaire.

Ce script ne permet pas de choisir une ancienne archive ni de basculer
l'application sur la cible. Les rôles globaux, propriétaires et ACL ne sont pas
restaurés. Voir le [scénario détaillé](sauvegarde-restauration.md).

## 4. Comprendre une alerte

Pour voir les règles, garder ce terminal ouvert :

```powershell
kubectl --context kind-devops-lab -n monitoring port-forward svc/prometheus 9090:9090
```

Ouvrir [localhost:9090/alerts](http://localhost:9090/alerts).
`pending` signifie que la condition attend confirmation ; `firing`, qu'elle dure
au moins une minute. Les alertes restent locales, sans notification externe.

| Alerte | Ce qu'il faut vérifier |
| --- | --- |
| `LabPodError` | Pod en erreur dans `demo` ou `data` : événements et logs du pod. |
| `LabPostgresUnavailable` | PostgreSQL et son exporteur : une panne de collecte peut aussi déclencher l'alerte. |
| `LabBackupFailed` | Logs du Job, CronJob actif, espace disponible. Aucun succès depuis 15 minutes ou une métrique absente déclenche aussi l'alerte. |
| `LabRedisUnavailable` | Redis et son exporteur, si Redis est installé. |

Premières commandes utiles, dans un autre terminal du projet :

```powershell
kubectl --context kind-devops-lab get pods -A
kubectl --context kind-devops-lab -n data get cronjob,jobs
kubectl --context kind-devops-lab -n demo logs deployment/devops-demo --tail=50
kubectl --context kind-devops-lab -n data logs postgres-0 --tail=50
```

Après correction, relancer le test concerné : `Test-Deployment.ps1`,
`Test-Postgres.ps1`, `Test-Monitoring.ps1` ou `Test-Redis.ps1`, dans `scripts/`.
Une règle revenue à la normale se résout automatiquement. Un ancien Job échoué
peut garder l'alerte de sauvegarde active tant que son historique est conservé.
Les [diagnostics détaillés](supervision.md) donnent les commandes par alerte.

## 5. Accès HTTPS et problème de certificat

Ouvrir le tunnel depuis le projet :

```powershell
.\scripts\Open-Demo.ps1
```

Ouvrir `https://localhost:8443`. Pour approuver l'autorité locale, utiliser
explicitement `scripts/Export-LabCA.ps1 -Trust` dans un second terminal, puis
rouvrir le navigateur. Cela ajoute uniquement son certificat public au magasin
de confiance de l'utilisateur Windows courant.

Lors de la phase de tests ultérieure, tunnel ouvert :

```powershell
.\scripts\Test-Https.ps1
```

**Attendu :** validation du nom et de l'autorité, santé `ok`, version identique
à `app/VERSION`. Résultat non encore obtenu : ces scripts sont préparés, non exécutés.

Si l'accès échoue, relever l'état avant correction :

```powershell
kubectl --context kind-devops-lab -n demo describe ingress devops-demo
kubectl --context kind-devops-lab -n demo describe certificate devops-demo-tls
kubectl --context kind-devops-lab get clusterissuer devops-lab-ca
kubectl --context kind-devops-lab -n traefik logs deployment/traefik --tail=50
```

Une connexion refusée indique d'abord un problème de tunnel ou de disponibilité.
Une 404 oriente vers le routage ; une 503, vers le Service applicatif et ses pods.
Un avertissement du navigateur demande de contrôler la confiance et le certificat
présenté. Ne pas effacer l'autorité ou les Secrets pour contourner l'erreur.
Le [guide HTTPS](https-local.md) précise les commandes, le renouvellement configuré,
le retrait de la confiance Windows et les limites du lab.
