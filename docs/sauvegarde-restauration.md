# Sauvegarde et restauration PostgreSQL

## Sauvegarde automatique

Le CronJob `postgres-backup` tourne toutes les cinq minutes, en UTC.
Avant de créer une archive, il vérifie la disponibilité de PostgreSQL avec
`pg_isready` : dix tentatives maximum, espacées de quatre secondes, avec un
timeout de connexion de deux secondes. Cela absorbe un retard de DNS ou de
démarrage. Une indisponibilité persistante fait échouer le Job et reste alertée.
Il utilise `pg_dump -Fc` pour sauvegarder toute la base `lab` dans une archive :
schéma, données et objets de cette base. Un fichier SHA-256 accompagne chaque archive.

Le volume `postgres-backups` (2 Gio) est séparé de `postgres-data-postgres-0` (1 Gio).
Un dossier n'est considéré complet qu'après la réussite du dump et son contrôle.
Les anciennes archives sont conservées ; surveiller l'espace disponible.

Le conteneur PostgreSQL monte les sauvegardes en lecture seule pour leur export.
Le Job de restauration lit directement ce volume : il n'a pas besoin du volume
de données de la base source.

```powershell
kubectl --context kind-devops-lab -n data get cronjob postgres-backup
kubectl --context kind-devops-lab -n data get jobs
```

Une exécution automatique réussie doit apparaître en `Complete`.

## Sauvegarder immédiatement et exporter sur Windows

```powershell
.\scripts\Backup-Postgres.ps1
```

La commande crée un Job à partir du même CronJob. Après sa réussite, elle copie
l'archive dans `backups/` sur Windows et contrôle son SHA-256.
Ce dossier est exclu de Git.

Les sauvegardes planifiées restent dans le volume Kubernetes.
L'export hors de kind est effectué par cette commande manuelle.

## Tester une restauration complète de la base

```powershell
.\scripts\Test-Restore.ps1
```

Le script :

1. Ajoute une ligne fictive de test, absente des données initiales.
2. Sauvegarde la base et vérifie que les données source sont restées stables.
3. Crée une nouvelle instance PostgreSQL, avec un nouveau volume et aucun script de données initiales.
4. Vérifie que la destination est vide et que l'archive est intacte.
5. Exécute `pg_restore` dans une transaction.
6. Compare le nombre de lignes, leur empreinte, les colonnes, les contraintes et les index.
7. Enregistre les durées et les résultats dans `backups/*-report.json`.

Le script ne lance pas de suppression et refuse de restaurer sur une destination
contenant déjà des tables. Les anciennes instances de test sont conservées.
Chaque relance ajoute une ligne fictive et utilise une nouvelle instance.

## Mesure du temps

Deux durées sont distinctes :

- `RestoreMilliseconds` : exécution de `pg_restore`.
- `TotalSeconds` : création de l'instance cible, attente, restauration et contrôles.
  La création de la sauvegarde se fait avant ce chronométrage.

## Limites du scénario

La base source reste disponible pendant le test, mais la restauration ne la lit pas :
elle utilise l'archive et une destination neuve. La comparaison attend un lab sans
écriture concurrente pendant la sauvegarde de test.

Le dump couvre la base `lab`, pas les rôles globaux ni les tablespaces du serveur.
Le rôle de connexion est créé par l'image PostgreSQL à partir du Secret du lab.
La restauration n'applique pas les propriétaires ni les ACL de la source.

Le stockage de kind et les exports Windows restent sur le même PC.
La perte du PC n'est pas couverte. Les exports hors du cluster et la politique
de rétention devront être automatisés pour un environnement réel.

Références : [pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html),
[pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html) et
[CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/).
