# Lab DevOps local

Ce projet reproduit une chaîne de déploiement sur un PC Windows :
Git → image Docker → registry local → ArgoCD → Kubernetes.

Le déploiement, le rollback et la sauvegarde PostgreSQL fonctionnent.
Une restauration complète de la base vers une instance vide a été vérifiée.
Tout reste hors production.

## 1. Prérequis

Installer Git, Docker Desktop, kind, kubectl et le client OpenSSH (`ssh-keygen`).
Démarrer Docker Desktop avec le moteur Linux. Prévoir une connexion Internet
et un compte GitHub autorisé à lire et modifier ce dépôt privé.
L'ajout d'une deploy key nécessite les droits d'administration du dépôt ; sinon,
demander au propriétaire d'ajouter uniquement la clé publique.

Dans PowerShell, vérifier :

```powershell
docker version
git --version
kind version
kubectl version --client
Get-Command ssh-keygen
```

Docker doit afficher **Client** et **Server**. Si une commande est introuvable,
ouvrir un nouveau PowerShell après son installation.

## 2. Récupérer le projet

```powershell
Set-Location "$HOME\Desktop"
git clone https://github.com/yazid9871/Devops-lab.git
Set-Location .\Devops-lab
```

Si le projet est déjà cloné, entrer simplement dans son dossier.
Si GitHub demande une connexion, utiliser un compte autorisé sur le dépôt.

## 3. Préparer le lab

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
.\scripts\Start-Lab.ps1
```

La première commande autorise les scripts locaux uniquement dans ce terminal.
Le script prépare le cluster, le registry, ArgoCD et l'image de l'application.
Il teste l'image et son téléchargement depuis kind.

**Résultat attendu :** `Infrastructure ready`.
Le script réutilise les ressources compatibles et conserve les images existantes.
Il ne supprime aucune donnée. En cas d'erreur, s'arrêter et lire le message.

## 4. Autoriser ArgoCD à lire GitHub

```powershell
.\scripts\Connect-ArgoRepo.ps1
```

Copier la ligne publique affichée, qui commence par `ssh-ed25519`.
Ouvrir [Settings → Deploy keys](https://github.com/yazid9871/Devops-lab/settings/keys)
sur GitHub, puis **Add deploy key** :

- Title : `argocd-devops-lab`.
- Key : la ligne publique copiée.
- **Allow write access : laisser décoché.**

Cliquer sur **Add key**. Sur un autre PC, créer une nouvelle clé avec le script.
La clé privée reste dans `secrets/`, exclu de Git, et dans le cluster.
Ne jamais la copier dans un message ou un commit.

## 5. Déployer et ouvrir l'application

```powershell
.\scripts\Deploy-Demo.ps1
```

**Résultat attendu :** `ArgoCD: Synced / Healthy`, avec un pod prêt.
ArgoCD suit la branche `main` et le dossier `k8s/demo`.

Pour ouvrir la page, lancer ceci et laisser le terminal ouvert :

```powershell
kubectl --context kind-devops-lab -n demo port-forward svc/devops-demo 8081:80
```

Ouvrir [http://localhost:8081](http://localhost:8081).
Dans un autre PowerShell, depuis le projet :

```powershell
.\scripts\Test-Deployment.ps1
```

**Résultat attendu :** `PASS`, la bonne version et une santé `ok`.
Ce test passe par le Service Kubernetes et ne dépend pas du port-forward.

## 6. Ouvrir ArgoCD

Dans un autre terminal qui restera ouvert :

```powershell
kubectl --context kind-devops-lab -n argocd port-forward svc/argocd-server 8080:443
```

Ouvrir [https://localhost:8080](https://localhost:8080).
Accepter le certificat autosigné pour cette adresse locale.

Le compte initial est `admin`. Pour obtenir son mot de passe :

```powershell
$encoded = kubectl --context kind-devops-lab -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Changer ce mot de passe dans **User Info → Update Password**.
Sur une installation existante, utiliser le mot de passe déjà choisi.

## 7. Publier une version et tester un rollback

Les modifications du code doivent d'abord être enregistrées et poussées dans Git.
Si nécessaire, configurer `git config user.name` et `git config user.email`
avec votre identité pour ce dépôt.

Dans le même PowerShell, lancer :

```powershell
.\scripts\Publish-Demo.ps1
$deployCommit = git rev-parse HEAD
.\scripts\Test-Deployment.ps1
```

Le pipeline choisit le prochain numéro disponible, construit et teste l'image,
la publie dans le registry, puis pousse la version souhaitée dans Git.
ArgoCD la déploie automatiquement. La détection peut prendre quelques minutes.
Les anciens tags sont conservés.

Pour revenir à la version précédente :

```powershell
git revert --no-edit $deployCommit
git push origin main
.\scripts\Test-Deployment.ps1
```

Le rollback ajoute un commit dans Git. L'ancienne image est réutilisée.
Si le port-forward s'arrête pendant le changement de pod, relancer celui de l'étape 5.
En cas d'erreur du pipeline, ne pas poursuivre ; examiner `git status` et `git diff`.

## 8. Déployer PostgreSQL

Depuis le dossier du projet :

```powershell
.\scripts\Deploy-Postgres.ps1
```

Le script crée les identifiants du lab dans Kubernetes, puis ArgoCD déploie
PostgreSQL dans le namespace `data`. La base et l'utilisateur s'appellent `lab`.
Le mot de passe est généré automatiquement et reste hors de Git.

**Résultat attendu :** `PASS`, au moins trois lignes de démonstration et un volume `Bound`.
La relance conserve le mot de passe, le volume et les données déjà présents.

Pour vérifier plus tard :

```powershell
.\scripts\Test-Postgres.ps1
```

Pour afficher les données fictives :

```powershell
kubectl --context kind-devops-lab -n data exec postgres-0 -- psql -h postgres.data.svc.cluster.local -U lab -d lab -c "TABLE demo_items;"
```

Les trois produits fictifs sont créés uniquement lors de l'initialisation d'un
volume vide. Modifier `init.sql` ne modifie pas une base déjà initialisée.
PostgreSQL est accessible à l'intérieur du cluster ; aucun port n'est ouvert sur Windows.

Le stockage persistant et les sauvegardes utilisent deux volumes distincts.
La sauvegarde et la restauration sont expliquées à l'étape suivante.

## 9. Sauvegarder et tester une restauration

La commande `Deploy-Postgres.ps1` installe aussi un CronJob de sauvegarde :
il s'exécute toutes les cinq minutes dans le cluster.

Pour faire une sauvegarde immédiatement et en garder une copie sur Windows :

```powershell
.\scripts\Backup-Postgres.ps1
```

**Résultat attendu :** `PASS`. L'archive et son SHA-256 sont copiés dans
`backups/`, un dossier exclu de Git. Les sauvegardes planifiées restent dans le
volume Kubernetes ; leur export sur Windows se fait avec cette commande.

Pour tester la restauration :

```powershell
.\scripts\Test-Restore.ps1
```

Le script ajoute une ligne fictive, sauvegarde, puis restaure dans une **nouvelle
instance vide**, avec son propre volume. Il compare les données et la structure,
et affiche la durée. La base source est conservée.

**Résultat attendu :** `PASS: full database restored`.
Le rapport est enregistré dans `backups/*-report.json`.
Les instances de test sont conservées ; chaque relance en crée une nouvelle.

Test vérifié le 16 octobre 2026 : quatre lignes restaurées, structure identique,
**11,78 s** pour créer la cible, restaurer et contrôler, dont **58 ms** de `pg_restore`.
Une sauvegarde planifiée a aussi été vérifiée.
Les [résultats](docs/validation-restauration.md) et
[les détails du scénario](docs/sauvegarde-restauration.md) sont dans le dépôt.

## 10. Voir l'etat du lab dans Grafana

Apres PostgreSQL et la sauvegarde, lancer :

```powershell
.\scripts\Deploy-Monitoring.ps1
```

Le script installe Prometheus, Grafana et les outils de collecte avec ArgoCD.
Il cree aussi le mot de passe Grafana. Aucun nouvel outil a installer sur Windows.
Sur une installation neuve, attendre la premiere sauvegarde planifiee si le test
le demande (cinq minutes maximum), puis relancer `Test-Monitoring.ps1`.

Pour ouvrir Grafana, garder ce terminal ouvert :

```powershell
kubectl --context kind-devops-lab -n monitoring port-forward svc/grafana 3000:3000
```

Ouvrir **http://localhost:3000/d/devops-lab**, utilisateur **admin**.
Dans un autre terminal, afficher le mot de passe local :

```powershell
$encoded = kubectl --context kind-devops-lab -n monitoring get secret lab-grafana-admin -o jsonpath='{.data.admin-password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Le dashboard **DevOps Lab** montre la base, les pods et les sauvegardes.
Il affiche aussi le nombre total de pods, les pods actifs et les pods termines,
avec un tableau : nom, namespace, etat, conteneurs prets et redemarrages.
Le tableau affiche toujours tous les pods et tous les etats, avec **demo en premier**.
Le filtre **Namespace des compteurs** concerne uniquement les compteurs.
Trois alertes surveillent : pod en erreur, PostgreSQL inaccessible et sauvegarde
échouée ou sans succès depuis quinze minutes. Les alertes sont visibles dans
Prometheus et Alertmanager ; aucun message externe n'est envoyé.

Pour verifier la supervision :

```powershell
.\scripts\Test-Monitoring.ps1
```

**Resultat attendu :** `PASS`, les cibles requises `UP` et les regles chargees.
Les scenarios de panne sont testes avec des metriques simulees.
Les [resultats de verification](docs/validation-supervision.md) sont conserves dans le depot.
Les [commandes pour consulter et comprendre les alertes](docs/supervision.md)
sont dans le guide de supervision.

## 11. Ajouter Redis (optionnel)

Depuis le dossier du projet :

```powershell
.\scripts\Deploy-Redis.ps1
```

Le script genere un mot de passe local hors de Git. ArgoCD installe Redis et son
exporteur, puis le script teste la connexion, l'ecriture, la lecture et l'expiration
d'une cle fictive. Une relance conserve le mot de passe.

**Resultat attendu :** `PASS: Redis requires authentication`, puis les controles
de supervision passent si elle est installee. Dans Grafana, **Redis disponible**
affiche **1**. Une quatrieme alerte detecte Redis indisponible.

Pour verifier Redis plus tard :

```powershell
.\scripts\Test-Redis.ps1
```

Redis est ici un cache temporaire : ses donnees peuvent disparaitre. L'application
web n'utilise pas encore Redis. Les [details et le diagnostic](docs/redis.md)
sont dans le guide Redis.

## En cas de problème

| Problème | Vérification |
| --- | --- |
| Docker ne répond pas | Démarrer Docker Desktop, puis relancer `docker version`. |
| GitHub refuse l'accès | Vérifier le compte Git pour la CI et la deploy key pour ArgoCD. |
| ArgoCD ne se synchronise pas | `kubectl --context kind-devops-lab -n argocd get application devops-demo -o yaml` |
| Un pod reste bloqué | `kubectl --context kind-devops-lab -n demo get events --sort-by=.metadata.creationTimestamp` |
| Un port est déjà occupé | Vérifier les terminaux de port-forward déjà ouverts. |
| Le script signale une ressource incompatible | Inspecter son contenu avant toute suppression. |

## Avancement

| Critère | État |
| --- | --- |
| Déploiement automatique | Vérifié |
| CI locale et rollback GitOps | Vérifiés : version 1 → 2 → 1 |
| PostgreSQL et son volume | Vérifiés |
| Redis optionnel et sa supervision | Vérifiés : authentification, écriture/lecture et disponibilité |
| Sauvegarde automatique et restauration PostgreSQL | Vérifiées |
| Supervision et trois alertes | Vérifiées : collecte réelle et tests de règles simulés |
| Runbook, note de recul, démo de 20 minutes | En cours |
| Relance complète sur un PC neuf en moins de 30 minutes | À mesurer en fin de lab |

La publication de la version 2 et le retour à la version 1 ont été vérifiés le 16 octobre 2026.
Les [résultats des tests](docs/validation-jour1.md) sont conservés dans le dépôt.
La relance sur le lab existant a été testée dans Windows PowerShell.
Le [runbook](docs/runbook.md) regroupe les opérations courantes.
Les détails du registry sont dans [docs/registry.md](docs/registry.md).
