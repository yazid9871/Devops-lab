# Lab DevOps local

Installer sur Windows un lab Kubernetes avec **kind, ArgoCD, Helm, Traefik,
cert-manager, PostgreSQL, Redis, Prometheus et Grafana**.

> Les ajouts Helm et HTTPS sont prêts dans le dépôt ; leur première installation
> complète reste à valider.

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

## 5. Ouvrir l’application

Dans un PowerShell ouvert dans le dossier du projet :

```powershell
.\scripts\Open-Demo.ps1
```

Garder ce terminal ouvert et aller sur **[https://localhost:8443](https://localhost:8443)**.

Pour approuver le certificat du lab pour ton utilisateur Windows, lancer dans
un autre terminal du projet :

```powershell
.\scripts\Export-LabCA.ps1 -Trust
```

Puis fermer et rouvrir le navigateur.

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

## Documentation

- [Schéma d’architecture](docs/diagrams/architecture-locale.png)
- [Documentation d’exploitation (PDF)](output/pdf/Documentation-exploitation-Devops-lab.pdf)
- [Runbook : déployer, restaurer et diagnostiquer](docs/runbook.md)
- [Accès aux interfaces, dont ArgoCD](docs/acces-interfaces.md)
- [Présentation de 10 minutes](docs/presentation-10-minutes.md)
- [Architecture détaillée](docs/architecture.md), [Helm](docs/helm.md) et [HTTPS](docs/https-local.md)
- [Comparaison avec Sobrus](docs/comparaison-sobrus.md) et [limites du lab](docs/note-de-recul.md)
