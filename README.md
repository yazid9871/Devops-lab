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

## 5. Relier ArgoCD au dépôt privé

Cette autorisation est distincte de votre connexion GitHub personnelle.
ArgoCD a seulement besoin de lire ce dépôt.

Depuis le dossier du projet :

```powershell
.\scripts\Connect-ArgoRepo.ps1
```

Le script génère une clé dédiée et affiche uniquement sa **clé publique**.
La clé privée reste dans `secrets/`, exclu de Git, et dans un Secret du cluster.

Dans [les clés de déploiement du dépôt](https://github.com/yazid9871/Devops-lab/settings/keys) :

1. Cliquer sur **Add deploy key**.
2. Saisir le titre `argocd-devops-lab`.
3. Coller la ligne publique affichée par le script, qui commence par `ssh-ed25519`.
4. Laisser **Allow write access** décoché et valider avec **Add key**.

Ensuite, lancer :

```powershell
.\scripts\Deploy-Demo.ps1
```

Ce script crée l'Application ArgoCD et attend **Synced / Healthy**.
ArgoCD lit la branche `main`, dans le dossier `k8s/demo`, puis déploie
l'application dans le namespace `demo`.
La synchronisation automatique corrige les écarts ; la suppression automatique
des ressources retirées de Git est désactivée.

Pour ouvrir l'application déployée par Kubernetes :

```powershell
kubectl --context kind-devops-lab -n demo port-forward svc/devops-demo 8081:80
```

Laisser ce terminal ouvert. Ouvrir [la version Kubernetes](http://localhost:8081).
Dans un autre terminal, vérifier :

```powershell
Invoke-RestMethod http://localhost:8081/healthz
kubectl --context kind-devops-lab -n argocd get application devops-demo
```

**Validation en cours :** la création de la clé, son enregistrement dans ArgoCD
et le manifeste Application ont été vérifiés. Le déploiement de bout en bout
reste à tester après l'ajout de la clé publique dans GitHub.

Sur un autre PC, générer une nouvelle clé avec le script et l'ajouter au dépôt.
Ne jamais copier la clé privée dans le README, un message ou un commit.

## 6. Vérifier le résultat

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
