# Présentation du lab — 10 minutes

## Message à faire passer

« Dans le cadre de mon stage chez Sobrus, je construis un lab local pour mettre
en pratique les technologies de la documentation d'exploitation. Je montre
comment déployer une application, vérifier son état et contrôler une restauration. »

Ce déroulé décrit le périmètre documenté du lab. Vérifier son état avant la
présentation ; aucune nouvelle validation du cluster n'a été réalisée pour rédiger ce document.

## Déroulé chronométré

| Temps | Montrer | Expliquer simplement |
| --- | --- | --- |
| 0:00–1:00 | Objectif du stage | Reprendre les technologies de référence dans un environnement local avec des données fictives. |
| 1:00–2:00 | Architecture ci-dessous | Rôle de Kubernetes, du registry, de Git et d'ArgoCD. |
| 2:00–4:00 | Application et ArgoCD | Une version d'image est enregistrée dans Git ; ArgoCD applique la configuration. Le rollback passe par un nouveau commit Git. |
| 4:00–6:00 | Rapport de restauration préparé | Une sauvegarde est restaurée dans une nouvelle instance ; les données et le schéma sont comparés. La source reste disponible. |
| 6:00–8:00 | Dashboard Grafana | Prometheus collecte les métriques ; Grafana affiche les pods et leurs états. Présenter une règle d'alerte et son diagnostic. |
| 8:00–9:00 | Runbook | Montrer une procédure : commandes, résultat attendu, contrôles après opération et limites. |
| 9:00–10:00 | Bilan et suite | Compétences démontrées, différences avec l'infrastructure Sobrus et prochaines technologies à intégrer. |

Budget : 10 minutes de présentation, hors questions si le jury leur réserve un temps séparé.

## Architecture à expliquer

```text
PowerShell : construction et tests -> registry Docker local
            configuration versionnée -> GitHub -> ArgoCD -> application Kubernetes

Cluster kind local
  demo        : application Python
  data        : PostgreSQL + volumes + sauvegardes ; Redis temporaire
  monitoring  : Prometheus -> Grafana ; Alertmanager
  argocd      : suivi de la configuration Git
```

Évolution préparée dans les fichiers, encore à déployer et tester : chart Helm
applicatif, Traefik pour l'Ingress HTTPS et cert-manager pour l'autorité locale
et le certificat `localhost`. Voir le [guide HTTPS](https-local.md).

L'application web n'utilise pas encore Redis. PostgreSQL et Redis ont leurs
propres tests ; ne pas présenter de connexion applicative qui n'a pas été démontrée.

## Préparer avant de démarrer le chronomètre

1. Suivre les contrôles de départ du [runbook](runbook.md).
2. Ouvrir l'application, ArgoCD et Grafana avec le [guide des interfaces](acces-interfaces.md).
   Se connecter avant le partage d'écran pour éviter d'afficher les mots de passe.
3. Répéter la publication et le rollback du runbook. Garder les résultats et les
   commits correspondants pour expliquer le changement. La publication exige un dépôt propre.
4. Lancer une fois `scripts/Test-Restore.ps1` et préparer le rapport correspondant
   dans `backups/`. Ce test ajoute une ligne fictive et conserve une nouvelle instance.
5. Préparer le runbook et les rapports de validation déjà disponibles dans `docs/`.
   Utiliser seulement les résultats réellement obtenus, avec leur date et leur contexte.

Pendant les 10 minutes, montrer les interfaces et les preuves préparées. Une
publication en direct peut attendre ArgoCD plusieurs minutes : ne l'inclure
qu'après une répétition chronométrée. Si une interface échoue, montrer le résultat
préparé en précisant sa date et signaler que le contrôle en direct n'a pas abouti.

## Ce que le lab démontre et ce qu'il reste à intégrer

Le lab documente Kubernetes via kind, un registry local, GitOps avec ArgoCD,
Prometheus et Grafana. Il ajoute des exercices PostgreSQL, Redis et une
sauvegarde SQL avec restauration contrôlée.

Le cahier des charges « Plateforme de référence locale » autorise Kustomize et
une sauvegarde par CronJob pg_dump : ces choix satisfont les alternatives prévues.
La présentation dure ici 10 minutes selon la précision donnée, au lieu des
20 minutes du document initial.

Une [migration de l'application vers Helm](helm.md) et un [accès HTTPS avec
Traefik/cert-manager](https-local.md) sont préparés dans les fichiers, mais n'ont
pas été déployés ni testés : ne pas les présenter comme validés.

La documentation Sobrus présente aussi Helm, Traefik, cert-manager, Rook/Ceph,
Velero/Restic, Trivy, Falco et un cleanup operator. Leur intégration au lab reste
à examiner comme extension facultative : ne pas les annoncer comme réalisés. Un dump SQL
ne démontre pas une sauvegarde Velero, et un volume local ne démontre pas Ceph.

Le lab fonctionne sur un seul PC : il ne valide ni la haute disponibilité ni
la reprise après perte du PC. Les sauvegardes restent sur cette machine. Les
alertes ont des tests de règles, mais aucune panne réelle de bout en bout ni
notification externe n'est documentée comme validée. L'installation sur un autre
PC en moins de 30 minutes reste à mesurer.

## Phrase de fin

« Ce lab me permet de démontrer le déploiement GitOps, la supervision et le
contrôle d'une restauration. Le runbook rend ces opérations reproductibles.
La prochaine validation est la reproduction du lab sur un autre PC avec le
README seul. Les technologies supplémentaires de référence sont des pistes
d'amélioration. »
