# Vérifications du jour 1

Tests réalisés le 16 octobre 2026 sur le cluster local `devops-lab`,
avec Windows PowerShell, Docker Desktop et le registry local.
Ce document décrit les résultats observés ; il ne valide pas encore
une installation complète sur un autre PC.

| Vérification | Résultat |
| --- | --- |
| Construction de l'image v2 | Réussie |
| Tests HTTP avant publication | Page 200, santé ok, version 2, route inconnue 404 |
| Publication au registry local | Réussie |
| Mise à jour du tag dans Git | Commit `5674271` |
| Déploiement automatique par ArgoCD | Synced / Healthy, version HTTP 2 |
| Retour arrière par nouveau commit Git | Commit `ef6cb20` |
| Application après rollback | Synced / Healthy, version HTTP 1, santé ok |
| Relance du script de démarrage avec v2 | Réussie, image existante réutilisée |
| Relance complète sur un PC neuf | Pas encore testée |

Le commit de publication modifie `app/VERSION` et le tag dans
`k8s/demo/kustomization.yaml`. Le rollback annule ces deux modifications.
L'image v2 est conservée dans le registry.

La vérification HTTP passe par le Service Kubernetes via l'API du cluster,
pas par l'ancienne démonstration Docker du port 18080.

Aucune synchronisation ArgoCD manuelle n'a été déclenchée pour la mise à jour
ou le rollback. Aucun `kubectl apply` du Deployment applicatif ni
`kubectl rollout undo` n'a été utilisé pour ces deux opérations.

L'attente de détection du commit par ArgoCD prend quelques minutes dans la
configuration actuelle. La démonstration doit prévoir ce délai.

## Limites

- La CI est un script local lancé manuellement ; elle ne s'exécute pas sur GitHub Actions.
- Les images et le cluster restent sur le même PC.
- Ce rollback concerne une application web sans données, pas une migration de schéma.
- Le test PostgreSQL de sauvegarde et de restauration reste à réaliser.
