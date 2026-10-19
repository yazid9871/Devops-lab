# Lab DevOps local

Installer sur Windows un lab Kubernetes avec **kind, ArgoCD, Helm, Traefik,
cert-manager, PostgreSQL, Redis, Prometheus et Grafana**.

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
