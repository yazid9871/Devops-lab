# Verification de la supervision — 16 octobre 2026

Verification sur le cluster local `kind-devops-lab`, sous Windows PowerShell 5.1.

| Controle | Resultat |
| --- | --- |
| Application ArgoCD `monitoring-lab` | `Synced`, `Healthy` |
| Prometheus, Grafana, Alertmanager, kube-state-metrics | Quatre Deployments disponibles dans `monitoring` |
| Exporteur PostgreSQL | Deployment disponible dans `data` |
| Cibles Prometheus | `prometheus`, `kube-state-metrics`, `postgres` : toutes `up` |
| Mesure PostgreSQL | `pg_up{job="postgres"}=1` |
| Sauvegarde planifiee | Metrique de dernier succes presente |
| Regles d'alerte | Trois regles chargees, saines et inactives sur le lab sain |
| Configuration et tests `promtool` | `SUCCESS` |
| Grafana | Authentification avec le Secret local reussie ; dashboard `devops-lab` avec six panneaux |
| Source Grafana | API de sante : `OK`, requete Prometheus reussie |
| Volumes | Prometheus 2 Gi et Grafana 1 Gi, tous deux `Bound` |
| Donnees PostgreSQL apres installation | Quatre lignes, empreinte `f121a32a1b0ea22fa13675810e2a3b93`, identique avant/apres |
| Autres applications ArgoCD | `devops-demo` et `postgres-lab` toujours `Synced`, `Healthy` |

## Ce que les tests d'alertes prouvent

Les huit groupes de tests de `k8s/monitoring/tests.yaml` utilisent le fichier de
regles reel, avec des series simulees. Ils verifient : pod Failed, CrashLoopBackOff,
base signalee indisponible, collecte PostgreSQL indisponible, Job de sauvegarde
echoue, sauvegarde trop ancienne, metriques absentes, et absence de fausse alerte
sur un lab sain avec une sauvegarde terminee. Le delai d'une minute est controle
dans les scenarios de panne immediatement visible.

Il n'y a eu ni arret de la base ni injection de panne reelle. Le delai complet
collecte → Prometheus → Alertmanager pendant une vraie panne reste a mesurer.
Les notifications externes ne sont pas configurees.

## Refaire les controles

```powershell
.\scripts\Test-Monitoring.ps1
.\scripts\Test-Postgres.ps1
kubectl --context kind-devops-lab -n argocd get applications
```

Les tests de l'API Grafana authentifiee et de sa source ont ete effectues
separement via le tunnel local, en lisant le Secret sans l'afficher.
Le script controle automatiquement sa sante HTTP et celle de sa base interne.

## Versions installees

Les manifests fixent aussi le digest SHA-256 de chaque image.

| Outil | Version |
| --- | --- |
| Prometheus | 3.15.0 |
| Grafana | 13.2.4 |
| Alertmanager | 0.34.1 |
| kube-state-metrics | 2.20.0 |
| postgres-exporter | 0.20.1 |

La relance complete depuis un PC neuf en moins de trente minutes n'a pas encore
ete mesuree. Ce controle porte sur l'installation et la relance sur le lab existant.
