# PostgreSQL : état des vérifications

Tests réalisés le 16 octobre 2026 sur `devops-lab`, avec Windows PowerShell.

| Contrôle | Résultat observé |
| --- | --- |
| Version PostgreSQL | 17.11 |
| Application ArgoCD postgres-lab | Synced / Healthy |
| Pod postgres-0 | 1/1 Running, aucun redémarrage |
| Volume postgres-data-postgres-0 | Bound, 1 Gio, classe standard |
| Connexion TCP par le Service avec mot de passe | Réussie |
| Écriture et lecture d'une donnée temporaire | Réussies |
| Données fictives persistantes | 3 lignes, quantités 10, 20 et 30 |
| Relance de Deploy-Postgres.ps1 | Même Secret, même PVC, mêmes données |
| Empreinte des lignes | `9a4ed7dd82ac54801e46cc3099fb9a25` |

Le mot de passe est généré pour le lab et n'est pas versionné.
L'image officielle PostgreSQL est figée par son empreinte dans le StatefulSet.

Complément : le remplacement du pod, la sauvegarde automatique et la restauration
ont depuis été vérifiés. Voir [les résultats](validation-restauration.md).
La base reste séparée de l'application web ; la page web ne l'utilise pas encore.
