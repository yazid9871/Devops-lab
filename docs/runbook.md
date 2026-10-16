# Runbook du lab

Exécuter les commandes dans PowerShell, depuis la racine du dépôt.
En cas d'erreur, s'arrêter et conserver le message avant de poursuivre.

## Démarrer

```powershell
.\scripts\Start-Lab.ps1
```

Lors d'une première installation, suivre le README pour la clé GitHub.
Ensuite :

```powershell
.\scripts\Deploy-Demo.ps1
.\scripts\Test-Deployment.ps1
```

Attendu : Application `Synced / Healthy`, santé `ok`, version identique à `app/VERSION`.

## Publier une nouvelle version

Le dépôt doit être propre, sur `main`, et synchronisé avec GitHub.

```powershell
.\scripts\Publish-Demo.ps1
$deployCommit = git rev-parse HEAD
.\scripts\Test-Deployment.ps1
```

Le pipeline teste la page, la santé, la version et une route inconnue avant de publier.
Il ne modifie pas directement le Deployment Kubernetes.
Une nouvelle version utilise un nouveau tag ; les tags existants ne sont pas écrasés.

Le script s'arrête au premier échec. Une image peut rester publiée si le push Git
échoue ensuite. Les modifications locales sont conservées pour diagnostic :
utiliser `git status`, `git diff` et le message d'erreur avant de réessayer.

## Revenir à la version précédente

Dans le même terminal, après une publication réussie :

```powershell
git revert --no-edit $deployCommit
git push origin main
.\scripts\Test-Deployment.ps1
```

Si le terminal a été fermé, retrouver le commit de déploiement dans `git log --oneline`
et utiliser son SHA à la place de `$deployCommit`.
Choisir un commit de publication qui n'a pas déjà été annulé.

Le rollback modifie `app/VERSION` et le tag Kustomize dans Git.
ArgoCD déploie l'ancienne image conservée dans le registry.
Ne pas utiliser `kubectl rollout undo` : ce changement serait corrigé par ArgoCD.

## Examiner un échec de déploiement

```powershell
kubectl --context kind-devops-lab -n argocd get application devops-demo -o yaml
kubectl --context kind-devops-lab -n demo get pods
kubectl --context kind-devops-lab -n demo get events --sort-by=.metadata.creationTimestamp
kubectl --context kind-devops-lab -n demo logs deployment/devops-demo --tail=50
```

- Erreur Git : vérifier la deploy key en lecture seule et le Secret de connexion.
- `ImagePullBackOff` : vérifier le registry et le tag attendu dans Git.
- Application non prête : lire les événements et les logs avant toute modification.

Les tests de déploiement et de rollback portent sur l'application web sans données.
Ils ne valident pas un rollback de schéma PostgreSQL.

## Vérifier PostgreSQL

```powershell
.\scripts\Deploy-Postgres.ps1
.\scripts\Test-Postgres.ps1
```

Le déploiement est géré par l'Application ArgoCD `postgres-lab`.
Le test passe par le Service PostgreSQL, utilise le mot de passe du lab,
vérifie une écriture/lecture temporaire, compte les lignes et affiche leur empreinte.
La donnée de contrôle est temporaire ; les trois lignes fictives restent stockées.

```powershell
kubectl --context kind-devops-lab -n data get pods,pvc
kubectl --context kind-devops-lab -n data logs postgres-0 --tail=50
```

Attendu : `postgres-0` prêt et `postgres-data-postgres-0` en `Bound`.
Les identifiants sont dans le Secret `postgres-credentials`.
La relance réutilise ce Secret et le volume.

Si le volume existe mais que le Secret est absent, le script s'arrête :
retrouver les identifiants existants avant de poursuivre.
Changer la variable du mot de passe ne met pas à jour le mot de passe d'une
base déjà initialisée.

Les données sont stockées dans le nœud kind, sur ce PC.
La suppression du cluster ou du PVC peut les faire perdre.
Les données ont été conservées lors du remplacement du pod pendant l'ajout du
volume de sauvegarde. La restauration a aussi été vérifiée sur une nouvelle instance.

## Sauvegarder PostgreSQL

```powershell
.\scripts\Backup-Postgres.ps1
```

Attendu : Job réussi, archive copiée dans `backups/`, SHA-256 conforme.
La commande utilise le modèle du CronJob et affiche le nom du dossier sauvegardé.

Le CronJob tourne toutes les cinq minutes et écrit sur un volume séparé :

```powershell
kubectl --context kind-devops-lab -n data get cronjob postgres-backup
kubectl --context kind-devops-lab -n data get jobs
```

En cas d'échec, lire les logs du Job dont le nom est affiché :

```powershell
kubectl --context kind-devops-lab -n data logs job/NOM_DU_JOB
```

## Restaurer et mesurer

```powershell
.\scripts\Test-Restore.ps1
```

Le script ajoute une ligne fictive de contrôle, fait une sauvegarde et la restaure
sur une nouvelle instance vide. Il refuse une cible contenant déjà des tables.
Il conserve la source, les anciennes instances de test et les archives.

Attendu : `PASS`, mêmes empreintes des données et du schéma.
Le rapport `backups/*-report.json` donne les durées de restauration et de création
de la cible avec ses contrôles. La sauvegarde est faite avant le chronométrage.

La destination ne lit ni le Service ni le volume de données de la source :
le Job utilise seulement l'archive, le Secret du lab et la nouvelle instance.
La source reste en fonctionnement pendant ce scénario.
Le dump concerne la base `lab` ; les rôles globaux et ACL ne sont pas restaurés.

Voir [le scénario détaillé](sauvegarde-restauration.md) et
[les résultats vérifiés](validation-restauration.md).

## Alertes

La supervision et les trois alertes restent à ajouter.

## Supervision

Installer : `.\scripts\Deploy-Monitoring.ps1`. Verifier : `.\scripts\Test-Monitoring.ps1`.

Le [guide de supervision](supervision.md) explique les trois alertes, les interfaces et les commandes de diagnostic.
