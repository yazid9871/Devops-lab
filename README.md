# Lab DevOps local

Ce lab permet de déployer une petite application avec ArgoCD, de revenir à une
ancienne version, puis de sauvegarder et restaurer PostgreSQL. Grafana affiche
l'état du lab. Redis est ajouté en option.

Tout tourne sur le PC, sans accès à la production. Le code est sur GitHub.

## Avant de commencer

Il faut Windows, PowerShell, une connexion Internet et ces outils installés :
[Git](https://git-scm.com/downloads/win),
[Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/),
[kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation),
[kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/)
et le [client OpenSSH](https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse).

Démarrer Docker Desktop en mode **Linux containers**, puis ouvrir PowerShell :

```powershell
docker version
git --version
kind version
kubectl version --client
Get-Command ssh-keygen
```

Les cinq commandes doivent fonctionner. Docker doit afficher **Client** et **Server**.
Il faut aussi un accès à ce dépôt privé. Pour ajouter la clé ArgoCD, il faut les
droits d'administration du dépôt ou l'aide de son propriétaire.

## 1. Récupérer le projet

```powershell
Set-Location "$HOME\Desktop"
git clone https://github.com/yazid9871/Devops-lab.git
Set-Location .\Devops-lab
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

Se connecter à GitHub si Git le demande. Si le projet est déjà cloné, ouvrir son
dossier. La dernière commande autorise les scripts uniquement dans ce terminal.
**Pour la suite, rester dans le dossier du projet et lancer une commande à la fois.
Si une commande échoue, lire son message avant de continuer.**

## 2. Préparer le cluster et l'accès GitHub

```powershell
.\scripts\Start-Lab.ps1
.\scripts\Connect-ArgoRepo.ps1
```

Le premier script prépare Kubernetes, le registry local, ArgoCD et l'image de
l'application. Il doit afficher `Infrastructure ready`.

Le second affiche une clé publique qui commence par `ssh-ed25519`.
La copier dans [GitHub → Settings → Deploy keys → Add deploy key](https://github.com/yazid9871/Devops-lab/settings/keys) :

- **Title** : `argocd-devops-lab`.
- **Key** : la ligne publique affichée.
- Laisser **Allow write access** décoché, puis cliquer sur **Add key**.

Sur un autre PC, ajouter sa nouvelle clé publique. La clé privée reste dans
`secrets/`, hors de Git ; elle ne doit pas être partagée.

## 3. Installer les services

Attendre la fin de chaque commande avant de lancer la suivante :

```powershell
.\scripts\Deploy-Demo.ps1
.\scripts\Deploy-Postgres.ps1
.\scripts\Deploy-Monitoring.ps1
```

L'application doit être `Synced / Healthy` et les tests doivent afficher `PASS`.
Si la supervision attend une sauvegarde, attendre la première exécution planifiée
(jusqu'à cinq minutes), puis relancer `Test-Monitoring.ps1`.

Pour ajouter Redis :

```powershell
.\scripts\Deploy-Redis.ps1
```

Les mots de passe sont générés automatiquement, hors de Git. Relancer les scripts
réutilise les ressources compatibles. Redis est un cache temporaire ; l'application
web ne l'utilise pas encore.

## 4. Ouvrir les interfaces

Chaque commande ci-dessous garde son terminal occupé : **utiliser un terminal
séparé par interface** et le laisser ouvert. `Ctrl+C` ferme le tunnel.

**Application :**

```powershell
kubectl --context kind-devops-lab -n demo port-forward svc/devops-demo 8081:80
```

Ouvrir [localhost:8081](http://localhost:8081).

**Grafana :**

```powershell
kubectl --context kind-devops-lab -n monitoring port-forward svc/grafana 3000:3000
```

Ouvrir [le dashboard DevOps Lab](http://localhost:3000/d/devops-lab), compte `admin`.
Pour afficher son mot de passe, dans un autre PowerShell :

```powershell
$encoded = kubectl --context kind-devops-lab -n monitoring get secret lab-grafana-admin -o jsonpath='{.data.admin-password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Le tableau montre tous les pods, tous états confondus, avec `demo` en premier.
Les alertes couvrent les pods en erreur, PostgreSQL, les sauvegardes et Redis
s'il est installé. Elles sont locales, sans envoi d'email.

**ArgoCD :**

```powershell
kubectl --context kind-devops-lab -n argocd port-forward svc/argocd-server 8080:443
```

Ouvrir [localhost:8080](https://localhost:8080), accepter le certificat local,
puis se connecter avec `admin`. Pour obtenir le mot de passe initial :

```powershell
$encoded = kubectl --context kind-devops-lab -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Le changer dans **User Info → Update Password**. S'il a déjà été changé, utiliser
le mot de passe choisi.

## 5. Vérifier le lab

Dans le terminal du projet :

```powershell
.\scripts\Test-Deployment.ps1
.\scripts\Test-Postgres.ps1
.\scripts\Test-Monitoring.ps1
kubectl --context kind-devops-lab get pods -A
```

Les tests doivent afficher `PASS`. Si Redis est installé, lancer aussi
`.\scripts\Test-Redis.ps1`. Un pod de sauvegarde `Completed` est normal.

Pour voir les données PostgreSQL :

```powershell
kubectl --context kind-devops-lab -n data exec postgres-0 -- psql -U lab -d lab -c "TABLE demo_items;"
```

## Tester une nouvelle version et revenir en arrière

Le dépôt doit être propre et poussé sur `main`. Configurer son identité Git si
nécessaire : `git config user.name "Votre nom"` et `git config user.email "votre@email"`.
Dans le même terminal, depuis le projet :

```powershell
.\scripts\Publish-Demo.ps1
$deployCommit = git rev-parse HEAD
.\scripts\Test-Deployment.ps1
```

Le script construit et teste l'image, la publie dans le registry local, puis pousse
la nouvelle version dans Git. ArgoCD la déploie. Après le succès, pour revenir en arrière :

```powershell
git revert --no-edit $deployCommit
git push origin main
.\scripts\Test-Deployment.ps1
```

## Sauvegarder et restaurer PostgreSQL

Une sauvegarde tourne automatiquement toutes les cinq minutes. Pour en lancer
une et en copier l'archive dans le dossier local `backups/` :

```powershell
.\scripts\Backup-Postgres.ps1
```

Pour vérifier qu'une sauvegarde se restaure correctement :

```powershell
.\scripts\Test-Restore.ps1
```

Attendu : `PASS: full database restored`. Le test ajoute une ligne fictive et
restaure dans une nouvelle instance, sans remplacer la base source. Il garde
l'instance de test et son rapport dans `backups/`. Chaque relance crée une cible.
Les sauvegardes planifiées restent dans le cluster ; leur copie sur Windows
se fait avec `Backup-Postgres.ps1`.

## Si ça bloque

- **Commande introuvable** : vérifier son installation et rouvrir PowerShell.
- **Docker ne répond pas** : démarrer Docker Desktop.
- **ArgoCD ne synchronise pas** : vérifier la clé GitHub et les messages de l'application dans ArgoCD.
- **Page inaccessible** : vérifier que son terminal de tunnel est toujours ouvert ; le relancer après un changement de pod.
- **Script refusé** : relancer `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned` dans ce terminal.

Le [runbook](docs/runbook.md) contient les commandes de dépannage.
Les guides [sauvegarde/restauration](docs/sauvegarde-restauration.md),
[supervision](docs/supervision.md) et [Redis](docs/redis.md) expliquent les détails.

Le déploiement, le rollback, la restauration et la supervision ont été vérifiés
sur le lab. La relance complète sur un PC neuf en moins de 30 minutes reste à mesurer.
