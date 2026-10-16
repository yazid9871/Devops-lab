# Redis — verification du 16 octobre 2026

Tests effectues sur `kind-devops-lab`, avec Windows PowerShell 5.1.

| Controle | Resultat |
| --- | --- |
| ArgoCD `redis-lab` | `Synced`, `Healthy` |
| Pod Redis | `Running`, deux conteneurs prets sur deux |
| Image serveur | Redis 8.10.2, digest fixe dans le manifest |
| Image exporteur | redis-exporter 1.94.0, digest fixe |
| Client sans mot de passe | Refuse : `NOAUTH` |
| Client authentifie via Service TCP | `PONG` |
| Ecriture / lecture | Valeur identique, cle unique de sonde |
| Expiration | TTL de 60 secondes verifie |
| Prometheus | Quatre cibles `up`, dont Redis ; `redis_up=1` |
| Alertes | Quatre regles saines et inactives sur le lab sain |
| Tests simules | `promtool SUCCESS`, treize groupes dont cinq pour Redis |
| Tableau des pods | Tous les 29 pods presents au moment du controle correspondent a Kubernetes |
| PostgreSQL | Quatre lignes et empreinte `f121a32a1b0ea22fa13675810e2a3b93`, conservees |

Les scenarios simules couvrent Redis en erreur, exporteur en erreur, metrique
absente, Redis sain et Redis optionnel non installe. Ils verifient le delai
d'une minute avant declenchement. Aucune panne Redis n'a ete injectee en direct.

Le tableau et les compteurs de pods excluent les series sans collecte recente
(plus de 60 secondes). Cela evite de recompter d'anciens pods dans la fenetre
de recherche de Prometheus apres le redemarrage du collecteur.

Le cache est volontairement temporaire : pas de test de persistance ou de
restauration Redis. L'application web n'est pas connectee a Redis.
La restauration PostgreSQL reste le scenario de recuperation des donnees du lab.

```powershell
.\scripts\Test-Redis.ps1
.\scripts\Test-Monitoring.ps1
.\scripts\Test-Postgres.ps1
```
