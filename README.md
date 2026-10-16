# Lab DevOps local

Projet pédagogique : Kubernetes avec kind, déploiement GitOps avec ArgoCD,
puis sauvegarde et restauration PostgreSQL. Le lab est en cours de construction.

## État validé

- Cluster `devops-lab` : nœud Ready et pods système prêts.
- ArgoCD : pods prêts et connexion à l'interface confirmée par l'utilisateur.
- Le pipeline CI, l'application et PostgreSQL ne sont pas encore configurés.

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
