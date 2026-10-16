# Lab DevOps local

L'objectif : copier ce dépôt dans son compte GitHub et lancer tout le lab depuis
PowerShell. L'installation prépare Kubernetes, ArgoCD, l'application, PostgreSQL,
Redis, les sauvegardes et Grafana. Elle teste aussi une restauration.

## Avant de commencer

Utiliser un PC Windows avec [Git](https://git-scm.com/downloads/win),
[Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/),
[kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation),
[kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/)
et le [client OpenSSH](https://learn.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse).
Démarrer Docker Desktop en mode **Linux containers** et ouvrir un nouveau PowerShell.

Ces commandes doivent fonctionner :

```powershell
docker version
git --version
kind version
kubectl version --client
Get-Command ssh-keygen
```

Docker doit afficher **Client** et **Server**. Il faut Internet et un compte GitHub.
L'objectif des **30 minutes commence avec ces outils installés et Docker démarré**.
Le temps de téléchargement dépend de la connexion ; la durée sur un PC neuf reste à valider.

## 1. Créer sa copie sur GitHub

Sur le dépôt modèle, cliquer sur **Use this template → Create a new repository**.
Choisir son compte, le nom **Devops-lab** et la visibilité **Private**.
Le dépôt modèle étant privé, il faut y avoir accès. Le modèle se copie avec sa branche `main`.

Puis remplacer `TON-COMPTE` ci-dessous par son identifiant GitHub :

```powershell
git clone https://github.com/TON-COMPTE/Devops-lab.git
Set-Location .\Devops-lab
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

Se connecter à GitHub si Git le demande. Les scripts détectent automatiquement
le compte et le nom du dépôt : aucun fichier de configuration à modifier.

## 2. Lancer l'installation

```powershell
.\scripts\Install-Lab.ps1
```

Le script prépare le lab, puis affiche une clé publique et le lien GitHub où l'ajouter :

1. Ouvrir le lien **Settings → Deploy keys → Add deploy key** affiché.
2. Donner un nom à la clé et copier la ligne qui commence par `ssh-ed25519`.
3. Laisser **Allow write access** décoché, puis cliquer sur **Add key**.
4. Revenir dans PowerShell, taper **OK** et appuyer sur Entrée.

L'installation reprend seule. À la fin : **`PASS`**, les services fonctionnent
et une sauvegarde a été restaurée dans une instance neuve. La durée de chaque
étape est enregistrée dans `work/install-report.json`.

Les mots de passe et la clé privée restent hors de Git. Le test de restauration
ajoute une ligne fictive et garde sa nouvelle instance, sans remplacer la base source.
Redis est un cache temporaire ; l'application web ne l'utilise pas encore.
Si une étape échoue, lire le message avant de relancer. Une relance conserve les
données existantes et crée une nouvelle cible de test de restauration.

## 3. Ouvrir le lab

Dans un autre PowerShell, garder ce terminal ouvert :

```powershell
kubectl --context kind-devops-lab -n monitoring port-forward svc/grafana 3000:3000
```

Ouvrir [Grafana](http://localhost:3000/d/devops-lab), compte **admin**.
Dans un autre terminal, afficher son mot de passe :

```powershell
$encoded = kubectl --context kind-devops-lab -n monitoring get secret lab-grafana-admin -o jsonpath='{.data.admin-password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Pour ouvrir l'application et ArgoCD : [commandes d'accès aux interfaces](docs/acces-interfaces.md).
Pour voir tous les pods :

```powershell
kubectl --context kind-devops-lab get pods -A
```

Un pod de sauvegarde `Completed` est normal. Le tableau Grafana affiche tous les
pods, tous états confondus, avec `demo` en premier.

## Utiliser le lab

- [Runbook court](docs/runbook.md) : publier, revenir en arrière, restaurer et comprendre une alerte.
- [Note de recul](docs/note-de-recul.md) : limites et risques ([PDF d'une page](docs/note-de-recul.pdf)).
- [Sauvegardes](docs/sauvegarde-restauration.md), [supervision](docs/supervision.md) et [Redis](docs/redis.md) : détails.

La CI de démonstration se lance avec `Publish-Demo.ps1`, comme expliqué dans le
runbook ; l'installation ne publie pas de nouvelle version et ne fait pas de rollback.
Le test de relance sur un PC neuf en moins de 30 minutes reste à mesurer avec un collègue.
