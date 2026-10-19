# Lab DevOps local

L'objectif : cloner ce dépôt public et lancer tout le lab depuis
PowerShell. L'installation prépare Kubernetes, ArgoCD, l'application, PostgreSQL,
Redis, les sauvegardes et Grafana. Elle teste aussi une restauration.

## Avant de commencer

Le parcours ci-dessous vise **Windows 11 sur processeur Intel/AMD 64 bits**, avec
Internet et un accès administrateur pour préparer Windows. Si les outils sont
déjà installés, passer directement à **Vérifier les prérequis**.

### A. Activer la virtualisation et préparer WSL 2

Ouvrir **Gestionnaire des tâches → Performances → Processeur** :
**Virtualisation : Activée** doit apparaître. Sinon, activer **Intel Virtualization
Technology / VT-x** ou **SVM Mode / AMD-V** dans le BIOS, enregistrer et redémarrer.
Sur MSI, l'accès au BIOS se fait généralement avec **Suppr** dès l'allumage.

Ouvrir **PowerShell en tant qu'administrateur**, puis lancer :

```powershell
wsl --install --no-distribution
```

**Redémarrer Windows**, puis rouvrir PowerShell en administrateur :

```powershell
wsl --update
wsl --set-default-version 2
wsl --version
```

**Attendu :** une version WSL s'affiche sans erreur. Docker demande WSL **2.1.5
ou plus récent**. Il n'est pas nécessaire d'installer Ubuntu pour ce lab.
Voir les [commandes WSL](https://learn.microsoft.com/windows/wsl/basic-commands)
et les [prérequis Docker/WSL 2](https://docs.docker.com/desktop/features/wsl/).

### B. Installer Git, Docker Desktop, kind et kubectl

Dans PowerShell, vérifier que le gestionnaire d'installation Windows est disponible :

```powershell
winget --version
```

Si `winget` est introuvable, installer ou mettre à jour **App Installer
(Programme d'installation d'application)** depuis le Microsoft Store, puis
rouvrir PowerShell. [Aide WinGet](https://learn.microsoft.com/windows/package-manager/winget/).

Lancer ces commandes **une par une**. Attendre la fin de chaque installation et
accepter les demandes de l'installateur. Si une commande échoue, résoudre son
erreur avant de continuer. Un outil déjà installé peut être conservé.

```powershell
winget install --exact --id Git.Git --source winget
winget install --exact --id Docker.DockerDesktop --source winget
winget install --exact --id Kubernetes.kind --source winget
winget install --exact --id Kubernetes.kubectl --source winget
```

Si Docker propose un choix, sélectionner **Use WSL 2 instead of Hyper-V**.
Redémarrer si l'installateur le demande. Ensuite, **fermer et rouvrir PowerShell**
pour rendre les nouvelles commandes disponibles.

Références : [Git/WinGet](https://learn.microsoft.com/windows/package-manager/winget/install),
[paquet Docker Desktop](https://github.com/microsoft/winget-pkgs/tree/master/manifests/d/Docker/DockerDesktop),
[kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation),
[kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/).

### C. Démarrer Docker Desktop

Ouvrir **Docker Desktop** depuis le menu Démarrer, terminer les écrans du premier
lancement et attendre que le moteur soit démarré. Utiliser les **conteneurs Linux**
et le moteur **WSL 2** dans les paramètres. Ne pas activer le Kubernetes intégré
à Docker Desktop : le script du lab crée son propre cluster avec kind.

### D. Vérifier les prérequis

Ces commandes doivent fonctionner :

```powershell
wsl --version
docker version
docker --context desktop-linux info --format '{{.OSType}}'
git --version
kind version
kubectl version --client
```

**Attendu :** les versions s'affichent, Docker montre **Client** et **Server**,
et la commande `docker ... info` retourne **`linux`**.
La lecture du dépôt public ne demande ni compte GitHub, ni clé SSH.
L'objectif des **30 minutes commence avec ces outils installés et Docker démarré**.
La préparation Windows et les redémarrages sont donc mesurés séparément.
Le temps de téléchargement dépend de la connexion ; la durée sur un PC neuf reste à valider.

| Blocage | Action |
| --- | --- |
| Virtualisation désactivée | Activer VT-x ou SVM dans le BIOS, puis redémarrer. |
| WSL demande une mise à jour | Lancer `wsl --update`, puis redémarrer si demandé. |
| `git`, `kind` ou `kubectl` introuvable | Fermer et rouvrir PowerShell ; vérifier le résultat de l'installation WinGet. |
| Docker affiche seulement Client ou une erreur de connexion | Ouvrir Docker Desktop et attendre le démarrage du moteur Linux. |
| Contexte `desktop-linux` absent | Terminer le premier lancement de Docker Desktop et sélectionner les conteneurs Linux. |

## 1. Cloner le projet

Dans PowerShell, cloner le [dépôt public](https://github.com/yazid9871/Devops-lab)
sur le Bureau :

```powershell
Set-Location ([Environment]::GetFolderPath('Desktop'))
git clone https://github.com/yazid9871/Devops-lab.git
Set-Location .\Devops-lab
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

Les scripts détectent automatiquement le dépôt à partir de `origin` et ArgoCD
le lit en HTTPS : aucun fichier de configuration à modifier.
Une copie personnelle reste possible, mais elle doit être publique pour cette installation.

## 2. Lancer l'installation

```powershell
.\scripts\Install-Lab.ps1
```

Le script vérifie l'accès public en HTTPS, puis installe le lab sans clé SSH
ni étape d'autorisation sur GitHub. À la fin : **`PASS`**, les services fonctionnent
et une sauvegarde a été restaurée dans une instance neuve. La durée de chaque
étape est enregistrée dans `work/install-report.json`. Le rapport mesure la commande,
sans l'installation des prérequis ni le clonage. Pour mesurer le parcours complet,
démarrer le chronomètre avant le clonage et l'arrêter après l'ouverture de Grafana.

Les mots de passe du lab restent hors de Git. Le test de restauration
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

- [Comparaison avec Sobrus](docs/comparaison-sobrus.md) : technologies présentes, écarts et tests pour adapter la méthode localement.
- [Runbook court](docs/runbook.md) : publier, revenir en arrière, restaurer et comprendre une alerte.
- [Présentation de 10 minutes](docs/presentation-10-minutes.md) : déroulé, démonstrations et préparation.
- [Note de recul](docs/note-de-recul.md) : limites et risques ([PDF d'une page](docs/note-de-recul.pdf)).
- [Sauvegardes](docs/sauvegarde-restauration.md), [supervision](docs/supervision.md) et [Redis](docs/redis.md) : détails.

La CI de démonstration se lance avec `Publish-Demo.ps1`, comme expliqué dans le
runbook ; l'installation ne publie pas de nouvelle version et ne fait pas de rollback.
Publier et faire un rollback nécessitent un compte GitHub avec les droits d'écriture
sur le dépôt. Si plusieurs labs suivent ce dépôt, ils recevront aussi les changements
de configuration ; chaque PC doit disposer de l'image correspondante dans son registry local.
Le test de relance sur un PC neuf en moins de 30 minutes reste à mesurer avec un collègue.
