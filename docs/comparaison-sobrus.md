# Sobrus et lab local : comparaison et validation de la méthode

Comparaison du 19 octobre 2026, à partir du dépôt et de la documentation
d'exploitation Sobrus fournie, version 1.2. Les numéros ci-dessous sont ceux des
pages du fichier PDF (couverture comprise).

## Objectif et ordre des références

Le cahier des charges principal est **Plateforme de référence locale (2 jours)**,
fourni et lu le 19 octobre 2026. La documentation d'exploitation Sobrus est une
source d'inspiration technique. Les extensions proposées plus bas ne sont donc
pas toutes des exigences du travail demandé.

Le livrable doit reproduire une chaîne de déploiement miniature et documentée :
cluster local, ArgoCD, application, CI minimale, registry local, rollback,
PostgreSQL, sauvegarde automatique, restauration contrôlée et supervision.
Le premier PDF autorise explicitement **Helm ou Kustomize** et **CronJob pg_dump
ou Velero**. Redis est optionnel. Si le temps manque, le déploiement ArgoCD et
la sauvegarde avec restauration sont prioritaires ; la supervision devient un bonus.

La durée de présentation retenue est **10 minutes**, conformément à la précision
de l'utilisateur, qui remplace les 20 minutes du document initial.

## Correspondance avec le travail demandé

| Attendu du premier PDF | Éléments présents dans le projet | Preuve ou réserve |
| --- | --- | --- |
| Cluster local, ArgoCD, application Helm ou Kustomize | kind, ArgoCD, application Python et Kustomize | Choix permis ; validations enregistrées dans `validation-jour1.md`, état courant à revérifier |
| CI minimale : build, publication et mise à jour de configuration | `Publish-Demo.ps1` | Chaîne scriptée lancée manuellement ; aucune CI hébergée ni déclenchement automatique sur commit |
| Synchronisation automatique et rollback | Applications ArgoCD et retour arrière par Git | Preuves historiques à présenter ; ne pas confondre rollback applicatif et migration de base |
| PostgreSQL, Redis si possible | Manifests, scripts et tests des deux services | Services testés indépendamment de l'application web |
| Sauvegarde automatique et restauration complète chronométrée | CronJob pg_dump, `Test-Restore.ps1`, rapports | Restauration de la base dans une cible distincte ; ancienne archive au choix, rôles globaux et bascule applicative non couverts |
| Prometheus/Grafana et trois alertes | Stack et quatre règles, dont les trois demandées | Tests de règles et collecte documentés ; panne réelle de bout en bout non validée |
| README pour relance en moins de 30 minutes | `Install-Lab.ps1`, README, compte rendu d'installation | Mesure disponible sur lab existant ; réception sur un autre PC avec README seul à faire |
| Runbook court et note d'une page | `runbook.md`, `note-de-recul.md` et PDF | Relire avec les commandes réellement rejouées et les résultats retenus |
| Tout en local, sans production ni secrets réels | Exécution locale, données fictives, secrets de lab hors de Git | Le dépôt GitHub distant reste une dépendance : signaler cette interprétation du cadre ; le lab n'est pas autonome hors ligne |

**Priorité de clôture :** rendre Docker/cluster accessibles, rejouer les scénarios
requis, faire relancer le lab par un collègue avec le README seul, conserver les
preuves et répéter la présentation de 10 minutes. La ressemblance avec la stack
Sobrus ne remplace pas ces critères de fonctionnement et de reproductibilité.

Le document de référence décrit une infrastructure et certaines procédures.
Il ne fournit pas tous les manifests, valeurs Helm, versions ou critères de test.
Il faut donc construire et tester une adaptation locale, plutôt que copier ses
commandes de maintenance telles quelles.

## État de la vérification

Les scripts, manifests, le runbook et les comptes rendus locaux ont été lus.
Les validations disponibles datent notamment du 16 octobre 2026. Au contrôle du
19 octobre, le moteur Docker `desktop-linux` est inaccessible et l'API du contexte
`kind-devops-lab` refuse la connexion. L'état actuel des pods, des volumes et des
ressources Docker n'a donc pas pu être confirmé. Cela ne démontre pas une perte de données.

Dans le tableau, « présent » signifie présent dans les fichiers du projet ;
cela ne signifie pas qu'un nouveau test en fonctionnement vient de réussir.

## Technologies et écarts

| Référence Sobrus | Lab actuel | Adaptation locale à réaliser ou à vérifier |
| --- | --- | --- |
| Kubernetes managé OVH, clusters admin et production (p. 6, 13–14, 21) | kind sur Docker Desktop ; une configuration de cluster, namespaces séparés | Conserver kind ; documenter la différence entre namespaces et clusters distincts. Aucune haute disponibilité physique sur un seul PC. |
| Registry privé ; Harbor cité pour les scans (p. 10, 26) | Distribution `registry:3`, volume Docker, port Windows lié à `127.0.0.1:5001` ; aucune authentification configurée dans le script | Le stockage et la publication sont représentés, mais pas les fonctions Harbor ni ses accès. Ajouter authentification/TLS ; étudier Harbor comme extension distincte. |
| Traefik, accès HTTP et terminaison TLS (p. 10) | Accès documentés par `kubectl port-forward`, aucun manifest Traefik | Installer Traefik et exposer l'application par un Ingress local. Un tunnel vers Traefik peut transporter le trafic sur le cluster existant sans le recréer ; le routage doit réellement passer par Traefik. |
| cert-manager et certificats TLS (p. 27–28) | Aucun manifest cert-manager ; certificat ArgoCD local | Installer cert-manager avec une autorité de certification de lab. Tester émission et renouvellement. Cette autorité locale remplace l'émetteur public dans l'exercice ; son certificat doit être explicitement approuvé par le client de test. |
| Rook/Ceph et stockage OVH Cinder (p. 9, 11–13) | PVC PostgreSQL, sauvegardes, Grafana et Prometheus ; aucune configuration Rook/Ceph | Tester d'abord la persistance locale. Préparer un exercice Rook/Ceph séparé après contrôle du stockage, du noyau et des ressources. Ne pas migrer les volumes existants pour cet exercice. |
| Prometheus et Grafana (p. 13–14) | Manifests et dashboard provisionnés ; exporteurs PostgreSQL, Redis et kube-state-metrics | Même famille d'outils. Vérifier collecte, panneaux et alertes ; le lab ne reproduit pas la supervision de deux clusters ni tous les dashboards du PDF. |
| Sauvegarde SQL planifiée ; MySQL explicitement cité (p. 15–16) | PostgreSQL, `pg_dump`, CronJob toutes les 5 minutes, restauration contrôlée | Même exercice de sauvegarde logique, autre moteur. Conserver PostgreSQL ; si la fidélité MySQL est recherchée, ajouter une instance MySQL fictive et son scénario de dump/restauration dans un périmètre séparé. |
| Restic vers S3, rétention 7 quotidiennes / 4 hebdomadaires / 12 mensuelles (p. 15–16) | Archives sur PVC puis export Windows ; aucun dépôt Restic, aucun stockage S3 ni rétention d'archives automatisée | Ajouter Restic pour les dumps SQL et un service S3 compatible de lab à sélectionner et versionner. Tester une restauration depuis un snapshot choisi. Un S3 local sur le même PC ne constitue pas une copie hors site. |
| Velero, sauvegarde de ressources et restauration dans un autre namespace (p. 16–18) | Scripts de restauration PostgreSQL uniquement | Ajouter Velero et sa destination objet. Valider d'abord les ressources d'un namespace témoin, puis les données d'un volume compatible. Une restauration SQL seule ne valide pas Velero. |
| ArgoCD, Projects, Applications, environnements et RBAC (p. 19–23) | Quatre Applications sur `main`, projet `default`, auto-sync/self-heal, `prune: false` ; scripts adaptés à HTTPS public le 19 octobre | Même protocole Git que la référence ; parcours modifié à tester. AppProjects, droits limités et configurations dev/staging restent des extensions possibles. |
| Charts Helm personnalisés et valeurs par environnement (p. 24–26) | Manifests Kustomize, pas de chart applicatif | Ajouter un chart de démonstration et des valeurs dev/staging ; faire rendre ce chart par ArgoCD. Adapter le script de publication et son test avant de changer la source de l'Application existante. |
| Gestion du code et CI/CD (p. 26) | GitHub et pipeline PowerShell manuel : construire, tester, publier, pousser la configuration | GitOps est représenté ; aucun workflow CI hébergé dans le dépôt. Le PDF ne donne pas de pipeline complet réutilisable : définir séparément les étapes et l'accès du runner au registry local. |
| Trivy dans le cluster et scans Harbor (p. 26) | Aucun manifest ni script Trivy | Ajouter Trivy Operator pour produire les rapports des images du cluster ; un scan CLI seul serait un premier exercice, pas l'équivalent du déploiement décrit. |
| Falco et Falcosidekick (p. 26) | Absents des manifests | Vérifier la compatibilité avec le noyau Linux Docker/WSL2, puis installer et produire un événement de test inoffensif. L'installation d'un pod seul ne prouve pas la détection. |
| Cleanup operator (p. 27) | Historique de Jobs limité dans le CronJob ; les cibles de restauration sont conservées | Le PDF ne précise pas l'éditeur ni les règles de cet opérateur. Ne pas en choisir arbitrairement : commencer par un inventaire et des règles proposées. Aucune suppression automatique ni de volume sans accord. |
| pfSense/OpenVPN, routes vers les ressources (p. 27) | Aucun lab VPN | Extension réseau séparée si nécessaire ; accès local par loopback pour le socle. Ne pas présenter celui-ci comme une validation du VPN Sobrus. |

Redis est un exercice complémentaire du lab : il n'est pas décrit comme composant
dans le texte du PDF examiné. L'application Python actuelle ne se connecte ni à
PostgreSQL ni à Redis ; les tests de ces services sont indépendants.

## Extensions possibles pour se rapprocher de Sobrus

Ces étapes complètent le socle demandé. Elles ne sont pas un préalable à sa
validation et ne doivent pas retarder les preuves prioritaires ci-dessus.
Helm, MySQL, Ceph, Harbor, Velero, Falco et le VPN ne deviennent pas obligatoires
du seul fait qu'ils apparaissent dans la référence Sobrus.

### 1. Accès et déploiement proches de la référence

Rendre Docker et le cluster accessibles, refaire les contrôles existants et
mesurer les ressources disponibles. Ajouter Helm, Traefik, cert-manager et un
environnement de démonstration séparé avant toute transition de l'application.
Conserver les données et les volumes actuels.

Critères : chart rendu et contrôlé, Application ArgoCD saine, accès HTTPS local
à travers Traefik avec vérification du certificat, changement de version puis
rollback par Git, émission et renouvellement de certificat observés. Enregistrer
la version d'image, le commit, les commandes, les résultats et les durées.

### 2. Sauvegardes et restauration proches de la référence

Ajouter le stockage objet de lab, Restic pour les dumps et Velero pour les
ressources Kubernetes. Commencer dans un namespace témoin. Pour les données,
choisir une méthode compatible avec le volume effectivement utilisé ; ne pas
supposer qu'un PVC kind supporte les snapshots OVH. Les volumes `hostPath` ne
sont pas pris en charge par la sauvegarde de fichiers Velero documentée.

Critères : sauvegarde terminée, snapshot/backup identifiable, restauration dans
une cible distincte, ressources et données vérifiées, source disponible, durées
enregistrées. Pour une base active, conserver un dump cohérent ; la copie à chaud
des fichiers de la base n'est pas un remplacement automatique de ce dump.

Restic pour les dumps et le mécanisme de transfert des volumes de Velero sont
deux configurations distinctes. Choisir ce dernier selon la version de Velero
(notamment Kopia), sans imposer une ancienne intégration Restic.

### 3. Supervision, sécurité et accès

Étendre la supervision aux nouveaux composants, tester une alerte de bout en
bout dans un périmètre témoin, ajouter Trivy Operator et tester Falco si le noyau
le permet. Ajouter AppProjects et un compte de consultation limité.

Critères : rapport de vulnérabilités réellement produit et expliqué, événement
Falco visible, alerte reçue dans Alertmanager puis résolue, opération autorisée
réussie et opération interdite refusée pour le compte limité.

### 4. Extensions de fidélité à examiner

Rook/Ceph, Harbor, MySQL et pfSense/OpenVPN restent visibles dans la comparaison.
Leur priorité dépend des attentes du tuteur et des ressources disponibles. Un
exercice Ceph sur le même PC peut montrer la gestion du stockage ; il ne prouve
pas une résistance à la perte du PC ou d'un datacenter. Identifier précisément
le cleanup operator avant de préparer ses règles.

## Comment vérifier que la méthode marche

Pour chaque procédure du runbook, conserver une fiche :

| Champ | Contenu requis |
| --- | --- |
| Objectif et périmètre | Service, contexte Kubernetes et namespace concernés |
| Prérequis | Versions, état initial et accès nécessaires |
| Effets | Ressources créées/modifiées, données ajoutées et risque d'interruption |
| Exécution | Commandes PowerShell réellement testées |
| Vérification | Résultat attendu et contrôle des données ou du service |
| Échec | Logs et événements à relever ; action de correction |
| Retour arrière | Configuration précédente ou restauration vers une cible distincte |
| Preuve | Date, commit, résultats, durée et limites ; aucun secret |

Puis faire suivre le README et le runbook à une autre personne. Noter chaque
intervention orale nécessaire : une procédure n'est pas encore autonome si une
étape indispensable doit être expliquée hors du document. Mesurer séparément
l'installation, la publication, le rollback et la restauration.

La méthode est validée pour le périmètre testé lorsque les critères sont atteints
et qu'une autre personne peut reproduire les opérations. Cela ne valide pas les
performances, la haute disponibilité ou la reprise de l'infrastructure de production.

## Références techniques pour l'adaptation

Le PDF fourni reste la référence de périmètre ; son contenu interne et ses
adresses d'exploitation ne sont pas recopiés dans les manifests du lab.

- [Installation Kubernetes de Traefik](https://doc.traefik.io/traefik/setup/kubernetes/)
- [Autorité de certification cert-manager](https://cert-manager.io/docs/configuration/ca/)
- [Sauvegarde de fichiers Velero 1.18 et limites](https://velero.io/docs/v1.18/file-system-backup/)
- [Prérequis Rook/Ceph](https://www.rook.io/docs/rook/latest/Getting-Started/Prerequisites/prerequisites/)
- [Trivy Operator](https://aquasecurity.github.io/trivy-operator/latest/)
- [Environnements d'apprentissage Falco](https://falco.org/docs/getting-started/learning-environments/)

Les versions compatibles seront choisies et fixées lors de l'implémentation,
après inventaire réel du cluster. Aucune installation nouvelle n'a été effectuée
dans le cadre de cette comparaison.
