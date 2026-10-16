# Test de sauvegarde et de restauration

Vérifications réalisées le 16 octobre 2026 sur le cluster local `devops-lab`.
PostgreSQL 17.11, base `lab`, jeu de données fictif.

## Sauvegarde

| Contrôle | Résultat |
| --- | --- |
| Job lancé immédiatement | Réussi |
| Format | Archive complète de la base avec pg_dump -Fc |
| Taille de l'archive du test | 1 829 octets |
| Copie dans backups/ sur Windows | Réussie, SHA-256 vérifié |
| Volume de sauvegarde | postgres-backups, 2 Gio, distinct du volume de données |
| Exécution automatique observée | 16 octobre 2026 à 06:25 UTC |
| Job planifié | postgres-backup-29868865, succeeded=1 |

La date de l'exécution automatique provient de l'annotation Kubernetes
`batch.kubernetes.io/cronjob-scheduled-timestamp`.
Elle est distincte du Job lancé manuellement.

## Restauration

La destination `postgres-restore-20261016062443-65ae37` a été créée sur un nouveau
volume. Aucun script `init.sql` n'y a chargé les données initiales.
Le Job a confirmé qu'aucune table utilisateur n'existait avant la restauration.

| Contrôle | Résultat |
| --- | --- |
| Archive avant restauration | SHA-256 conforme |
| Nombre de lignes source et cible | 4 |
| Donnée ajoutée après l'initialisation | id 1914326197, quantité 42, retrouvée dans la cible |
| Empreinte des données | f121a32a1b0ea22fa13675810e2a3b93, identique |
| Empreinte du schéma | 5712e672d1efea2c565d196c5d1482d0, identique |
| Temps pg_restore | 58 ms |
| Création de la cible, restauration et contrôles | 11,78 s |
| Source après le test | En fonctionnement, données relues et conformes |

Le contrôle du schéma couvre les colonnes, contraintes et index des tables du lab.
La durée globale commence après la sauvegarde et inclut l'attente Kubernetes.
Le fichier du rapport est conservé dans `backups/*-report.json`, hors de Git.

La mise à jour du StatefulSet source pour monter le volume de sauvegarde a
également remplacé son pod. Les trois lignes initiales et leur empreinte
`9a4ed7dd82ac54801e46cc3099fb9a25` étaient toujours présentes après ce remplacement,
avant l'ajout de la ligne de restauration.

## Ce que ce test ne prouve pas

- Le temps mesuré sur quatre lignes ne prédit pas une restauration de production.
- La source est restée disponible ; une panne totale du cluster n'a pas été simulée.
- Les rôles globaux, tablespaces, propriétaires et ACL ne sont pas reconstruits par ce test.
- Les données et les copies Windows restent sur le même PC.
- L'export hors de kind est manuel ; seules les sauvegardes dans le volume sont planifiées.
- La relance complète du lab sur un PC neuf reste à tester.
