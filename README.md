# Lab DevOps local

Ce lab sert à tester une chaîne de déploiement sur un PC, avant de réfléchir
à son utilisation dans l'infrastructure de l'équipe.

**Le projet est en cours.** Aujourd'hui, le cluster, ArgoCD, le registry et
l'application Docker fonctionnent. ArgoCD ne déploie pas encore l'application.
La CI, le rollback et la sauvegarde PostgreSQL restent à réaliser.

## 1. Avant de commencer

Il faut un PC Windows avec :

- Docker Desktop démarré, en mode conteneurs Linux ;
- Git, kind et kubectl installés et accessibles dans PowerShell ;
- une connexion Internet pour télécharger les images ;
- un compte GitHub autorisé à lire ce dépôt privé.

Pas besoin d'installer Python, Helm ou ArgoCD sur Windows.
Python est inclus dans l'image Docker et ArgoCD tourne dans Kubernetes.

Ouvrir PowerShell et vérifier :

```powershell
docker version
git --version
kind version
kubectl version --client
```

Docker doit afficher **Client** et **Server**. Si une commande est introuvable,
ouvrir un nouveau PowerShell après son installation.

## 2. Récupérer le projet

Pour une première installation :

```powershell
Set-Location "$HOME\Desktop"
git clone https://github.com/yazid9871/Devops-lab.git
Set-Location .\Devops-lab
```

Si GitHub demande une connexion, utiliser un compte qui a accès au dépôt.
Ne pas mettre de token dans la commande.

Si le dossier existe déjà sur ce PC, utiliser simplement :

```powershell
Set-Location "$HOME\Desktop\Devops-lab"
```

## 3. Démarrer le lab

Depuis le dossier du projet, autoriser les scripts locaux dans ce terminal, puis lancer :

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
.\scripts\Start-Lab.ps1
```

Le script prépare les éléments déjà disponibles :

1. Crée le cluster `devops-lab` s'il n'existe pas.
2. Configure le registry local et son stockage.
3. Installe ArgoCD depuis le manifeste conservé dans le dépôt.
4. Construit l'image de l'application et la publie dans le registry.
5. Démarre une démonstration Docker et vérifie sa santé.

Il réutilise les ressources compatibles déjà présentes et ne supprime aucune donnée.
En cas d'erreur, il s'arrête : lire le message avant de continuer.

**Résultat attendu :** le script termine par `Ready: http://localhost:18080`.
Ouvrir [l'application](http://localhost:18080) : elle affiche « DevOps Lab — version 1 ».

## 4. Ouvrir ArgoCD

Dans un PowerShell qui restera ouvert :

```powershell
kubectl --context kind-devops-lab -n argocd port-forward svc/argocd-server 8080:443
```

Ouvrir [ArgoCD](https://localhost:8080). Accepter l'avertissement de certificat
autosigné uniquement pour cette adresse locale.

Pour une première connexion, ouvrir un deuxième PowerShell et récupérer le
mot de passe initial :

```powershell
$encoded = kubectl --context kind-devops-lab -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Se connecter avec `admin`, puis changer le mot de passe dans
**User Info → Update Password**. Pour une installation existante, utiliser le
mot de passe déjà choisi. Ne pas enregistrer les mots de passe dans Git.

## 5. Vérifier le résultat

```powershell
kubectl --context kind-devops-lab get nodes
kubectl --context kind-devops-lab -n argocd get pods
Invoke-RestMethod http://localhost:18080/healthz
Invoke-RestMethod http://localhost:18080/version
Invoke-RestMethod http://localhost:5001/v2/devops-demo/tags/list
```

On doit retrouver :

| Contrôle | Résultat attendu |
| --- | --- |
| Nœud Kubernetes | `Ready` |
| Pods ArgoCD | `Running`, tous les conteneurs prêts |
| Santé de l'application | `ok` |
| Version | `1` |
| Tags du registry | `v1` |

L'application visible sur le port 18080 tourne dans Docker.
Les manifestes pour son futur déploiement Kubernetes sont dans `k8s/demo/`.

## En cas de problème

| Problème | Que faire |
| --- | --- |
| Docker ne montre pas de partie Server | Démarrer Docker Desktop et attendre que le moteur soit prêt. |
| PowerShell bloque les scripts | Après vérification du code, exécuter `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned`, puis relancer le script. Cela ne concerne que ce terminal. |
| Le clone renvoie Repository not found | Vérifier l'accès du compte GitHub au dépôt privé. |
| Un port est déjà utilisé ou un conteneur est incompatible | Lire le message du script et inspecter la ressource ; ne pas la supprimer sans vérifier son contenu. |
| ArgoCD ne s'ouvre plus | Relancer le port-forward de l'étape 4. |
| Un pod reste bloqué | Utiliser `kubectl --context kind-devops-lab -n argocd get events --sort-by=.metadata.creationTimestamp`. |

## Avancement par rapport aux critères de notation

| Attendu | État |
| --- | --- |
| Cluster, ArgoCD et registry | Vérifiés |
| Application Docker | Vérifiée |
| Déploiement automatique et rollback GitOps | À réaliser |
| Pipeline CI local | À réaliser |
| Sauvegarde et restauration PostgreSQL chronométrée | À réaliser |
| Supervision et trois alertes | À réaliser, après les priorités |
| Runbook, note de recul et démonstration de 20 minutes | À compléter au fil des tests |

La commande de démarrage a été testée le 16 octobre 2026 dans Windows PowerShell
sur le lab existant, sans suppression ni recréation du cluster.

Objectif final : relancer le lab avec ce README seul en moins de 30 minutes,
prérequis installés. Le temps d'une installation complète sur un PC neuf
n'a pas encore été mesuré.

Les détails du registry sont dans [docs/registry.md](docs/registry.md).
Les commandes et vérifications sont ajoutées à la documentation après leur test.
