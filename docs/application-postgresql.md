# Application connectée à PostgreSQL

L'application propose une liste de tâches : ajouter une tâche, afficher les
100 dernières et cocher ou décocher une tâche. Les écritures sont validées en
base avant la réponse HTTP ; aucun stockage dans le pod web n'est utilisé.

Version v3 déployée et contrôlée : voir le [compte rendu de validation](validation-application-postgresql.md).

```text
Navigateur -> Traefik -> Service devops-demo -> application Python
                                              |
                                              v
                      postgres.data.svc.cluster.local:5432
                         base lab / table public.app_tasks
```

Le rôle `devops_app` peut lire, ajouter et modifier les tâches. Il n'est pas
administrateur et n'a pas accès aux écritures de `demo_items`. Son mot de passe
aléatoire est conservé dans le Secret `demo/app-postgres-credentials`, hors Git.
L'application utilise Psycopg avec paramètres SQL et un timeout des requêtes.
Les textes saisis sont affichés comme du texte, sans interprétation HTML.

## Installation et mises à jour

`Install-Lab.ps1` installe PostgreSQL avant l'application. `Deploy-Demo.ps1`
appelle `Connect-AppDatabase.ps1` pour créer la table et le compte de manière
additive : il ne supprime aucune table ni donnée existante.
Un Secret existant est conservé. Si le compte existe mais que son Secret a
disparu, le script demande de récupérer ce Secret au lieu de changer le mot de passe.

Pour mettre à jour un lab existant, préparer la base avant la synchronisation
du nouveau chart, puis construire/publier une nouvelle image et pousser Git.
Un autre PC utilisant ce dépôt doit faire la même préparation et disposer de
l'image dans son propre registry ; l'image d'un PC n'est pas partagée.

```powershell
.\scripts\Connect-AppDatabase.ps1
.\scripts\Deploy-Demo.ps1
```

## Santé et vérification

| Route | Rôle |
| --- | --- |
| `/healthz` | Processus HTTP vivant, même si PostgreSQL est en panne |
| `/readyz` | Connexion et lecture de la table ; 503 si indisponible |
| `/api/tasks` | GET : liste ; POST JSON : ajout d'une tâche |
| `/api/tasks/<id>` | PATCH JSON : modifier `done` (booléen) |

La readiness dépend de PostgreSQL, la liveness reste indépendante pour éviter
des redémarrages en boucle lors d'une panne de base. Aucun mode mémoire ne
remplace silencieusement PostgreSQL. Le navigateur reçoit une erreur si une
écriture échoue.

Contrôles d'intégration (créent une tâche fictive terminée) :

```powershell
Get-Content .\scripts\test_app_database.py -Raw |
  kubectl --context kind-devops-lab -n demo exec -i deployment/devops-demo -- python -
```

Pour la présentation : ajouter une tâche, actualiser la page et montrer qu'elle
est conservée en base. Le remplacement du pod web ne supprime pas les tâches.
Les sauvegardes `pg_dump` incluent toute la table `app_tasks`. Le contrôle de
restauration compare aussi le contenu des tâches ; le champ `ROWS` historique
reste le nombre de lignes de `demo_items`.

## Limites

Redis n'est pas encore utilisé par l'application. Ce lab n'a ni comptes
utilisateurs ni autorisation par tâche : toute personne ayant accès à
l'interface peut lire et modifier les tâches. L'accès est local par tunnel.
La liaison interne PostgreSQL utilise TCP sans TLS. Un retour à l'ancienne
image laisse la table en place ; une restauration sur une autre instance ne
rebascule pas automatiquement l'application et ne recrée pas les rôles/ACL.
