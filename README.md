# Lab DevOps local

Projet pédagogique : Kubernetes avec kind, déploiement GitOps avec ArgoCD,
puis sauvegarde et restauration PostgreSQL. Le lab est en cours de construction.

## État validé

- Cluster `devops-lab` : nœud Ready et pods système prêts.
- ArgoCD : pods prêts et connexion à l'interface confirmée par l'utilisateur.
- Application de démonstration validée dans Docker ; manifestes Kubernetes préparés.

## Installation ArgoCD

Prérequis : Docker Desktop démarré avec le moteur Linux, kind et kubectl installés.
Les commandes suivantes ont été exécutées dans PowerShell pendant la mise en place :

```powershell
kind create cluster --name devops-lab --wait 120s
kubectl --context kind-devops-lab get nodes
kubectl --context kind-devops-lab get pods -A
kubectl --context kind-devops-lab create namespace argocd
kubectl --context kind-devops-lab apply --server-side -n argocd -f .\infra\argocd\install.yaml
kubectl --context kind-devops-lab -n argocd get pods
```

Ne pas recréer un cluster déjà existant. Vérifier son existence avec `kind get clusters`.

Le manifeste conservé dans `infra/argocd/install.yaml` utilise ArgoCD v3.5.5.
Il a été téléchargé depuis :
https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
La référence distante `stable` évolue ; la copie versionnée conserve le fichier utilisé.

## Interface locale

```powershell
kubectl --context kind-devops-lab -n argocd port-forward svc/argocd-server 8080:443
```

Laisser ce terminal ouvert et accéder à https://localhost:8080.
Le certificat initial est autosigné. Le compte initial est `admin`.
Ne jamais enregistrer de mot de passe, de kubeconfig ou de sauvegarde de base dans Git.

## Application de démonstration — étape validée

L'application Python utilise uniquement la bibliothèque standard. Elle expose :
- `/` : page « DevOps Lab — version 1 » ;
- `/healthz` : JSON `{"status":"ok"}` ;
- `/version` : JSON `{"version":"1"}`.
Une route inconnue renvoie HTTP 404. La version provient de `app/VERSION`,
copié dans l'image. Le serveur HTTP convient à la démonstration locale.

### Construire et lancer dans PowerShell

Depuis la racine du dépôt, avec Docker Desktop démarré :

```powershell
docker --context desktop-linux build --tag devops-demo:v1 .\app
docker --context desktop-linux run --detach --name devops-demo-preview --label devops.lab=preview --read-only --cap-drop ALL --security-opt no-new-privileges --publish 127.0.0.1:18080:8080 devops-demo:v1
```

Le nom du conteneur doit être disponible. Si la démonstration existe déjà,
vérifier son état avec `docker --context desktop-linux ps -a --filter name=devops-demo-preview`
avant toute nouvelle création. Un conteneur arrêté peut être démarré avec
`docker --context desktop-linux start devops-demo-preview`.

Ouvrir http://localhost:18080 puis vérifier :

```powershell
Invoke-RestMethod -Uri http://127.0.0.1:18080/healthz
Invoke-RestMethod -Uri http://127.0.0.1:18080/version
docker --context desktop-linux inspect devops-demo-preview --format 'User={{.Config.User}} ReadOnly={{.HostConfig.ReadonlyRootfs}} Status={{.State.Status}}'
```

Résultats vérifiés le 16 octobre 2026 : page HTTP 200, santé `ok`, version `1`,
route inconnue HTTP 404, utilisateur `10001:10001`, système de fichiers en lecture seule.
La base Python du Dockerfile est figée par son empreinte SHA-256.
Aucune dépendance pip n'est nécessaire.

Pour arrêter la démonstration sans supprimer le conteneur :

```powershell
docker --context desktop-linux stop devops-demo-preview
```

### Manifestes Kubernetes préparés

`k8s/demo/` contient un Namespace, un Deployment, un Service et le fichier Kustomize.
Le Service relie son port 80 au port 8080 de l'application.
Les sondes de disponibilité et de vie interrogent `/healthz`.

Commandes de validation exécutées avec succès :

```powershell
kubectl kustomize .\k8s\demo
kubectl --context kind-devops-lab apply --dry-run=client -k .\k8s\demo
```

**L'application n'est pas encore déployée dans Kubernetes.**
L'image `devops-demo:v1` a été publiée dans le registry local sous le nom
`localhost:5001/devops-demo:v1`. Son téléchargement depuis kind est validé
(voir ci-dessous). L'accès Git d'ArgoCD et le déploiement GitOps restent à configurer.
Le pipeline CI et PostgreSQL restent à réaliser.

## Registry local — étape validée

Le registry écoute sur `127.0.0.1:5001` côté Windows. Le conteneur
`devops-lab-registry` est également connecté au réseau Docker `kind`.
Les images sont conservées dans le volume nommé `devops-lab-registry-data`.
Le registry est en HTTP, sans authentification : ce choix est limité au lab local.

### Configuration et publication (PowerShell)

Le cluster doit déjà exister. Docker, kind et kubectl doivent être dans le PATH :

```powershell
.\scripts\Setup-Registry.ps1
docker --context desktop-linux tag devops-demo:v1 localhost:5001/devops-demo:v1
docker --context desktop-linux push localhost:5001/devops-demo:v1
docker --context desktop-linux exec devops-lab-control-plane crictl pull localhost:5001/devops-demo:v1
Invoke-RestMethod -Uri http://127.0.0.1:5001/v2/devops-demo/tags/list
```

Ces commandes ont été testées le 16 octobre 2026. Le tag `v1` est publié et le
téléchargement depuis le nœud kind réussit. La relance du script de configuration
réutilise le conteneur, le réseau et le volume existants.

### Pourquoi une configuration spéciale pour kind ?

`localhost` sur Windows et `localhost` dans le nœud Kubernetes sont deux adresses
distinctes. Le fichier `infra/registry/hosts.toml`, copié dans
`/etc/containerd/certs.d/localhost:5001/hosts.toml` sur chaque nœud, associe
le nom d'image `localhost:5001/...` à `http://devops-lab-registry:5000`.

Sur le nœud actuel, le chemin de configuration des registries était vide.
Le script a sauvegardé le fichier containerd en
`/etc/containerd/config.toml.devops-lab.bak`, ajouté `config_path`, puis redémarré
le service containerd. Le cluster et les pods ArgoCD sont restés opérationnels.
Le script s'arrête s'il rencontre une configuration différente qu'il ne sait pas modifier.

Le ConfigMap `local-registry-hosting` dans `kube-public` documente l'adresse.
Il ne configure pas à lui seul l'accès des nœuds au registry.

Références :
- https://kind.sigs.k8s.io/docs/user/local-registry/
- https://github.com/containerd/containerd/blob/main/docs/hosts.md

**Étape suivante :** autoriser ArgoCD à lire le dépôt privé, puis créer son
Application GitOps. Aucun déploiement applicatif n'a été effectué pendant cette étape.
