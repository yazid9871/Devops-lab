# Note de recul — lab DevOps local

**16 octobre 2026 · Périmètre : un PC Windows, un nœud kind, des données fictives.**
Aucun accès à la production n'a été utilisé. Le lab valide une méthode de travail ;
il ne suffit pas à valider l'architecture de notre infrastructure réelle.

## Ce qu'on peut reprendre

Le principe GitOps est réutilisable : décrire la configuration dans Git, relire
les changements et laisser ArgoCD les appliquer. Le lab a vérifié une publication
d'image dans un registry local, un déploiement automatique et un retour à la
version précédente par `git revert`. La CI est un script PowerShell lancé
manuellement ; son hébergement dans une vraie plateforme CI reste à prévoir.

La sauvegarde PostgreSQL et le contrôle par restauration sont aussi transposables.
Une archive `pg_dump` a été restaurée dans une instance vide, sur un nouveau volume,
avec comparaison des données et du schéma. Le test sur quatre lignes a pris
**11,78 s**, dont **58 ms de restauration** ; la sauvegarde est exclue de ce temps.
Cette mesure ne prédit pas le délai d'une restauration de production.

Enfin, le tableau des pods, les alertes et le runbook donnent une base commune
pour diagnostiquer les incidents. Redis est déployé et testé comme cache temporaire ;
l'application de démonstration ne l'utilise pas encore.

## Ce qu'on n'a pas pu vérifier

Sans accès ni inventaire de l'infrastructure réelle, on ne peut pas confirmer
la compatibilité du réseau, du DNS, du stockage, des droits, des certificats ou
du registry avec ces manifests. Les volumes, le trafic et les dépendances réels
n'ont pas été reproduits. Les charges, la haute disponibilité et les migrations
de schéma restent à tester. Le rollback validé concerne seulement l'application web.

Les alertes ont été testées avec des métriques simulées et une collecte réelle,
sans injection de panne de bout en bout. L'envoi de notifications, la perte totale
du cluster, la restauration d'une ancienne archive choisie et la bascule applicative
n'ont pas été validés. La relance sur un autre PC avec le README seul en moins
de 30 minutes reste également à mesurer.

## Risques et suites proposées

Le PC est un point de panne unique : données, archives et exports Windows restent
sur la même machine. L'export des sauvegardes est manuel et leur rétention n'est
pas automatisée. Les archives et les cibles de test peuvent remplir les volumes.
Le dump ne reconstruit pas les rôles globaux, propriétaires et ACL PostgreSQL.
Redis perd ses données au remplacement de son pod.

Les mots de passe sont hors de Git, mais les droits du lab sont larges et le trafic
interne n'est pas chiffré. Prometheus dépend du cluster qu'il surveille : une panne
du PC peut faire disparaître aussi la supervision.

Avant un pilote réel, faire valider avec le DevOps le stockage et les sauvegardes
externes, la gestion des secrets, les accès et les notifications. Fixer les objectifs
de perte de données et de délai de reprise, puis tester une restauration représentative.
Le prochain contrôle du lab est une relance par un collègue, avec le README seul.
