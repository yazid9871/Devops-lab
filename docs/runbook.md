# Runbook court - DevOps Lab

À utiliser sur le lab **déjà installé**, depuis PowerShell dans le dossier du
projet. Docker Desktop doit être démarré. Si une commande échoue, s'arrêter et
lire le message avant de poursuivre.

```powershell
Set-Location C:\Users\pc\Desktop\Devops-lab
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
kubectl --context kind-devops-lab get nodes
kubectl --context kind-devops-lab -n argocd get applications
```

Attendu : nœud `Ready`, applications `Synced / Healthy`. L'application est une
page simple, indépendante de PostgreSQL et Redis. Accès web uniquement via
Traefik : `https://localhost:8443` avec `scripts/Open-Demo.ps1` dans un terminal
séparé à garder ouvert. Voir les [accès aux interfaces](acces-interfaces.md).

## 1. Déployer une nouvelle version

Prérequis : branche `main`, dépôt propre et synchronisé avec GitHub, compte
avec droits d'écriture et registry local disponible. `git status --short` doit
être vide. Chaque PC doit disposer de l'image dans son propre registry.

```powershell
git status --short
.\scripts\Publish-Demo.ps1
$deployCommit = git rev-parse HEAD
.\scripts\Test-Deployment.ps1
```

Le script construit et teste l'image, la pousse dans le registry, puis pousse
le nouveau tag dans Git. ArgoCD déploie la configuration du chart Helm.

**Attendu :** `PASS`, bonne version accessible en HTTPS via Traefik et ArgoCD
`Synced / Healthy`. Conserver `$deployCommit` pour le retour arrière.

## 2. Revenir à la version précédente

Dans le même terminal, après une publication réussie :

```powershell
git revert --no-edit $deployCommit
git push origin main
.\scripts\Test-Deployment.ps1
```

**Attendu :** l'ancienne version revient, avec `PASS` et ArgoCD `Synced / Healthy`.
L'ancienne image doit toujours être présente dans le registry.

Si le terminal a été fermé, retrouver le commit `Deploy demo v...` avec
`git log --oneline` et remplacer `$deployCommit` par son SHA. Vérifier qu'il n'a
pas déjà été annulé. Ne pas utiliser `kubectl rollout undo` : ArgoCD réapplique
l'état de Git. Ce retour arrière ne restaure pas une base de données.

## 3. Restaurer une sauvegarde PostgreSQL

Pour créer une sauvegarde et exporter une copie vérifiée dans `backups/` :

```powershell
.\scripts\Backup-Postgres.ps1
```

Pour tester la restauration complète dans une nouvelle instance :

```powershell
.\scripts\Test-Restore.ps1
```

Le test ajoute une ligne fictive, crée une nouvelle sauvegarde, vérifie son
SHA256, prépare une instance vide, restaure la base et compare les données de
`demo_items` ainsi que le schéma contrôlé avec la source.

**Attendu :** `RESTORE TEST: PASS`, lignes vérifiées et
`Source database kept running: True`. Noter `Restore` et `Target creation and
checks` : cette seconde durée inclut la restauration mais exclut la sauvegarde.
Le rapport est enregistré dans `backups/*-report.json`.

La source reste en place ; la cible et son volume sont conservés. Chaque
relance ajoute une ligne de test et une instance. Le script ne sélectionne pas
une ancienne archive et ne réalise aucune bascule. Les rôles globaux et ACL
ne sont pas restaurés. [Détails](sauvegarde-restauration.md).

## 4. Comprendre une alerte

Ouvrir les alertes Prometheus avec ce tunnel, à garder ouvert :

```powershell
kubectl --context kind-devops-lab -n monitoring port-forward svc/prometheus 9090:9090
```

Aller sur [http://localhost:9090/alerts](http://localhost:9090/alerts).
`pending` = condition présente, délai en cours ; `firing` = condition présente
depuis au moins une minute ; `inactive` = condition absente. `health: ok`
signifie que la règle s'évalue correctement, pas que l'incident est résolu.

| Alerte | Premières vérifications |
| --- | --- |
| `LabPodError` | Pods en erreur dans `demo` ou `data` : logs et événements. |
| `LabPostgresUnavailable` | PostgreSQL, son Service et son exporteur. |
| `LabBackupFailed` | Job échoué, logs, stockage ; absence de succès depuis 15 min ou métrique absente. |
| `LabRedisUnavailable` | Redis et son exporteur lorsque Redis est demandé actif. |

```powershell
kubectl --context kind-devops-lab get pods -A
kubectl --context kind-devops-lab -n data get cronjob,jobs,pvc
kubectl --context kind-devops-lab -n data logs postgres-0 --tail=50
```

Pour un pod précis, remplacer `NOM_DU_POD` et choisir le bon namespace :

```powershell
kubectl --context kind-devops-lab -n data describe pod NOM_DU_POD
kubectl --context kind-devops-lab -n data logs NOM_DU_POD --all-containers --tail=50
```

Conserver les logs, corriger la cause, puis lancer le contrôle adapté dans
`scripts/` : `Test-Deployment.ps1`, `Test-Postgres.ps1`, `Test-Redis.ps1` ou
`Test-Monitoring.ps1`. Attendre le retour de l'alerte à `inactive`. Un ancien Job
échoué peut maintenir une alerte malgré une sauvegarde suivante réussie.
Les notifications sont locales, sans email. [Diagnostic détaillé](supervision.md).

Ne supprimer aucun cluster, volume ou sauvegarde pour masquer une erreur.
