# Installation du lab : parcours actuel et validation historique

## Parcours public HTTPS (modification du 19 octobre 2026)

1. Installer les outils du README et demarrer Docker Desktop.
2. Cloner le depot public en HTTPS, comme indique dans le README.
3. Lancer `scripts/Install-Lab.ps1`, sans cle SSH ni autorisation GitHub.
4. Attendre `PASS`, puis ouvrir Grafana avec la commande du README.

Les scripts lisent `git remote get-url origin`. Les quatre Applications ArgoCD
utilisent ce depot en HTTPS, sans identifiants et sans modification des fichiers suivis par Git.
Les chemins de runbook des alertes designent les documents de la copie locale.
Un cluster deja connecte a un autre depot est refuse plutot que reconfigure.
Une Application SSH du meme depot peut passer en HTTPS. Les anciennes cles et
leur Secret ne sont pas supprimes par cette modification.

Le nouveau parcours doit etre teste par l'utilisateur sur l'autre PC. Les mesures
ci-dessous concernent l'ancien parcours SSH ; elles ne valident pas cette modification.

## Verifications historiques du 16 octobre 2026 (depot alors prive, parcours SSH)

Le depot source est un modele GitHub (`is_template=true`) et reste prive.
Le test hors ligne `Test-Repository.ps1` a valide cinq formats d'URL GitHub,
les quatre Applications pour chacun, et le rejet de deux origines invalides.
Il utilise le nom fictif `colleague/custom-lab` : aucun compte de collegue
n'a ete utilise et aucun depot de test distant n'a ete cree.

Le parcours complet a ete execute sous **Windows PowerShell 5.1**, sur le PC
du lab existant, avec Docker disposant d'environ 16 Go de memoire et 16 CPU.
Les images etaient deja en cache et la cle GitHub etait deja autorisee.

| Controle | Resultat |
| --- | --- |
| Duree de la commande complete | 1,53 minute, soit environ 1 min 32 s |
| Cluster, registry, ArgoCD et image de demo | Verifies |
| Application web | HTTP, version et sante : PASS |
| PostgreSQL | Authentification, lecture/ecriture et volume : PASS |
| Redis | Authentification, lecture/ecriture et expiration : PASS |
| Restauration | Six lignes et schema compares sur une nouvelle instance vide : PASS |
| Duree du scenario de restauration | 12,17 s, dont 85 ms de pg_restore ; sauvegarde exclue |
| Supervision | Quatre cibles UP et quatre regles saines ; tests promtool : SUCCESS |
| Inventaire des pods | 33 pods compares a Kubernetes, tous etats confondus |

Le rapport detaille est genere dans `work/install-report.json`, hors de Git.
La commande ne publie pas de nouvelle version ni de rollback de l'application :
ces operations de CI sont decrites dans le runbook et ont ete validees separement.
Chaque scenario de restauration conserve sa nouvelle instance et ajoute une ligne fictive.

## Ce qu'il reste a mesurer

**Cette duree est celle d'une relance sur un lab existant.** Elle ne prouve pas
encore qu'un collegue recree tout en moins de trente minutes sur un autre PC.

Pour le test de reception : utiliser un PC avec les prerequis installes, demarrer
le chronometre avant la copie du depot et le clonage, suivre uniquement le README,
puis l'arreter apres `PASS` et l'ouverture du dashboard. Conserver le rapport,
la duree totale, les ressources Docker et les eventuels blocages.

Le rapport du script mesure son execution et l'attente d'autorisation de la cle ;
il exclut l'installation des outils, la creation de la copie et son clonage.
La duree du premier telechargement des images depend aussi de la connexion Internet.
