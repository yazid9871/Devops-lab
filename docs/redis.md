# Redis : cache local de demonstration

Redis stocke des paires cle/valeur en memoire. Ce lab permet de verifier son
deploiement, son authentification et sa supervision. L'application web ne l'utilise
pas encore : aucun gain de performance applicatif n'a ete mesure.

## Installer

Depuis le dossier du projet, avec le cluster et ArgoCD deja disponibles :

```powershell
.\scripts\Deploy-Redis.ps1
```

Le script genere un mot de passe fictif dans le Secret `data/redis-credentials`,
puis ArgoCD deploie l'application `redis-lab`. Le mot de passe reste hors de Git.
Une relance le reutilise. Le pod contient Redis et son exporteur Prometheus.
Si la supervision est installee, le script la verifie aussi.

Redis est accessible uniquement depuis le cluster :
`redis.data.svc.cluster.local:6379`. Aucun port Redis n'est publie sur Windows.

## Tester

```powershell
.\scripts\Test-Redis.ps1
```

Le test verifie qu'un client sans mot de passe est refuse. Il teste ensuite PING,
ecrit une cle de sonde unique via le Service Kubernetes, relit sa valeur et verifie
son expiration. Cette cle expire seule au bout de 60 secondes. Il ne vide pas le cache.

Les [resultats verifies](validation-redis.md) sont conserves dans le depot.

Pour refaire les controles de supervision :

```powershell
.\scripts\Test-Monitoring.ps1
```

Dans Grafana, le panneau **Redis disponible (1 = oui)** doit afficher **1**.
La liste des pods affiche aussi Redis et ses deux conteneurs.

## Comprendre l'alerte Redis

`LabRedisUnavailable` se declenche apres une minute si Redis est declare dans
Kubernetes et que `redis_up=0`, l'exporteur ne repond plus, ou sa metrique manque.
Cela peut indiquer une panne Redis ou un probleme de collecte/authentification.
L'alerte reste desactivee si le Redis optionnel n'a jamais ete installe.

```powershell
kubectl --context kind-devops-lab -n data get pods -l app=redis
kubectl --context kind-devops-lab -n data describe deployment redis
kubectl --context kind-devops-lab -n data logs deployment/redis -c redis --tail=50
kubectl --context kind-devops-lab -n data logs deployment/redis -c redis-exporter --tail=50
.\scripts\Test-Redis.ps1
```

Lire les evenements et les logs avant toute modification. L'alerte se resout
automatiquement lorsque la collecte et Redis repondent a nouveau.

## Choix et limites

- Redis **8.10.2**, exporteur **1.94.0**, images fixees par digest SHA-256.
- Instance unique, sans haute disponibilite, sans TLS interne au lab.
- Cache limite a 96 Mo, eviction `allkeys-lru`. Limite du conteneur : 256 Mio.
- Stockage temporaire `emptyDir`, pas de sauvegarde Redis. Les cles peuvent
  disparaitre a l'eviction ou au remplacement du pod. Ce choix convient seulement
  a des donnees de cache regenerables ; les donnees importantes restent dans PostgreSQL.
- Le mot de passe protege l'acces, mais le compte du lab a des droits larges.
  Les interfaces de metriques sont accessibles dans le cluster.
- La persistance Redis et son integration a l'application ne sont pas validees.
- Redis 8 propose notamment la licence libre AGPLv3 ; le lab utilise l'image
  officielle, sans modification du serveur.

References : [Redis](https://redis.io/docs/latest/),
[licences Redis](https://redis.io/legal/licenses/),
[redis-exporter](https://github.com/oliver006/redis_exporter).
