# Validation de l'application PostgreSQL — 19 octobre 2026

Périmètre : mise à jour du lab existant sur ce PC, application **v3**, chart
**0.3.0**. Cela ne constitue pas une nouvelle mesure d'installation sur PC neuf.
Image : `localhost:5001/devops-demo:v3`, empreinte
`sha256:60c58bfb167712be8d4bb99f0676e06a73735d43c595e6fd44c57d9d5b4cfa85`.

| Contrôle exécuté | Résultat |
| --- | --- |
| Syntaxe Python/PowerShell, lint et rendu Helm | Réussis |
| Image isolée sans réseau ni base | HTTP 200 sur `/healthz`, 503 sur `/readyz`, version 3, page et 404 corrects |
| Pod de validation séparé du Service applicatif | Ajout, lecture et modification d'une tâche réussis |
| Entrées incorrectes et origine différente | Rejetées (400 et 403) |
| Rôle PostgreSQL | Non administrateur, sans droit INSERT sur `demo_items` |
| Déploiement réel par ArgoCD | Synced / Healthy ; version 3 et readiness PostgreSQL vérifiées par le Service |
| Suppression du seul pod de validation | La tâche reste lisible depuis le nouveau pod applicatif |
| Navigateur via tunnel HTTP de diagnostic 8081 | Ajout et case « terminée » conservés après rechargement de la page |
| HTTPS via Traefik 8443 | API version, readiness et tâches vérifiées avec Python/OpenSSL, autorité locale et nom localhost validés |
| Restauration dans une nouvelle instance | SHA256, données de démonstration, données des tâches et schéma identiques au moment du test |

La restauration `postgres-restore-20261019043929-eb1d6c` a pris **90 ms** pour
`pg_restore` et **12,05 secondes** pour la création de cible et les contrôles,
hors sauvegarde. La source est restée active. Le rapport est conservé hors Git
dans `backups/postgres-restore-20261019043929-eb1d6c-report.json`.
Le compteur `ROWS=5` concerne `demo_items` ; l'empreinte DATA inclut également
la table `app_tasks` (une tâche à cet instant). Une seconde tâche fictive a été
ajoutée ensuite depuis le navigateur pour vérifier l'interface.

Le navigateur de contrôle ne fait pas encore confiance à la racine locale :
sa vérification visuelle a utilisé le tunnel HTTP de diagnostic déjà prévu.
`Test-Https.ps1` avec curl/Schannel a signalé une révocation inconnue, car la PKI
locale ne fournit pas de service de révocation. La vérification Python/OpenSSL
avec la racine explicite a réussi, sans désactiver la vérification TLS. Ces
résultats ne prouvent pas l'approbation de la racine dans tous les navigateurs
ni le renouvellement réel du certificat.

Aucun volume ni donnée existante n'a été supprimé. Une sauvegarde a été exportée
et vérifiée avant l'ajout du schéma. Les instances de restauration sont conservées.
Redis n'est pas connecté à l'application dans cette version.
