# Runbook du lab

Commandes à lancer dans **PowerShell, depuis le dossier du projet**.
Docker Desktop doit être ouvert et le lab installé avec le [README](../README.md).
Si une commande échoue, s'arrêter et lire son message.

## 1. Déployer l'application

Pour le premier déploiement sur un lab déjà préparé :

```powershell
.\scripts\Deploy-Demo.ps1
```

Pour publier une nouvelle version, les changements doivent être enregistrés et
poussés sur `main`, avec un dépôt propre et une identité Git configurée :

```powershell
.\scripts\Publish-Demo.ps1
$deployCommit = git rev-parse HEAD
.\scripts\Test-Deployment.ps1
```

**Attendu :** `PASS`, nouvelle version accessible et ArgoCD `Synced / Healthy`.
Le script construit et teste l'image, la publie dans le registry local, puis pousse
son tag dans Git. ArgoCD applique le changement ; cela peut prendre quelques minutes.

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
