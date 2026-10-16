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

## Sauvegarde, restauration et alertes

Ces procédures seront ajoutées après leur réalisation et leur test.
Aucune restauration PostgreSQL ni alerte de supervision n'est validée à ce stade.
