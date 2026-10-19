# HTTPS local avec Traefik et cert-manager

## État de cette évolution

Les fichiers ont été préparés le 19 octobre 2026. Aucun déploiement, aucun rendu
Helm et aucun test fonctionnel de cette évolution n'ont été exécutés. Les
commandes ci-dessous sont destinées à la phase d'installation et de tests de
l'utilisateur. Ne pas présenter le renouvellement ou le HTTPS comme validés.

## Architecture

```text
Navigateur : https://localhost:8443
  -> tunnel Windows limité à 127.0.0.1:8443
  -> Service traefik:443 (namespace traefik)
  -> Traefik termine TLS et suit l'Ingress
  -> Service devops-demo:80 -> application:8080 (namespace demo)

cert-manager -> autorité locale -> certificat localhost -> Secret devops-demo-tls
```

Le nom `localhost` évite de modifier le fichier `hosts` ou d'utiliser un DNS
externe. Le certificat est émis pour ce nom. Le tunnel fait passer la requête
uniquement par Traefik ; aucun tunnel direct vers le Service applicatif n'est
utilisé. Le navigateur doit être ouvert sur le PC qui exécute le tunnel.

TLS se termine dans Traefik. La liaison de Traefik vers l'application reste en
HTTP dans le cluster. Grafana et ArgoCD gardent leurs accès documentés séparément.

## Installation et responsabilités

`Install-Lab.ps1` appelle `Deploy-Access.ps1` après le démarrage du cluster et
avant le déploiement de l'application. Cette étape télécharge les charts officiels
et leurs images ; l'accès à Internet est nécessaire.

| Élément | Gestion | Source |
| --- | --- | --- |
| Traefik | Release Helm `traefik`, namespace `traefik` | Chart officiel `41.6.1` et `infra/access/traefik-values.yaml` |
| cert-manager | Release Helm `cert-manager`, namespace `cert-manager` | Chart officiel `v1.21.2` et `infra/access/cert-manager-values.yaml` |
| Autorité locale | Bootstrap par `Deploy-Access.ps1` | Manifests `infra/access/pki/` |
| Application, Ingress et Certificate | ArgoCD rend le chart Helm applicatif | `charts/devops-demo/` |
| Certificats et clés générés | cert-manager | Secrets locaux au cluster, hors Git |

Les versions des charts des contrôleurs sont fixées dans `infra/access/versions.psd1`.
Les images de ces contrôleurs utilisent les versions prévues par leurs charts,
sans fixation supplémentaire par digest dans notre configuration. Les contrôleurs
ne sont pas encore des Applications ArgoCD : une modification de leurs valeurs
Git sera appliquée par une relance explicite de `Deploy-Access.ps1`.

Sur le lab existant, après publication des fichiers sur GitHub et mise à jour du
checkout, la transition se prépare ainsi, lorsque l'utilisateur sera prêt :

```powershell
.\scripts\Deploy-Access.ps1
.\scripts\Deploy-Demo.ps1
```

`Deploy-Access.ps1` réutilise les releases Helm et l'autorité existante. Il ne
recrée pas le cluster et n'efface aucun volume. Si un Certificate racine existe
mais que son Secret a disparu, il refuse de continuer : récupérer l'autorité
d'origine avant de décider d'en créer une autre. Une erreur d'installation laisse
les ressources déjà créées en place ; examiner la sortie avant de relancer.

## Ouvrir l'application

Depuis le projet, dans un terminal à garder ouvert :

```powershell
.\scripts\Open-Demo.ps1
```

Ouvrir [https://localhost:8443](https://localhost:8443).
`Ctrl+C` arrête uniquement le tunnel. Si 8443 est occupé, utiliser par exemple
`Open-Demo.ps1 -Port 8444`, puis ouvrir `https://localhost:8444`.
Le Service Traefik reste un `ClusterIP` ; aucun LoadBalancer OVH, NodePort ou
port public Windows n'est créé. L'adresse Ingress `127.0.0.1` est une indication
de statut locale pour ArgoCD, pas un accès qui remplace le tunnel.

## Faire confiance au certificat dans le navigateur

L'autorité du lab n'est pas une autorité publique. L'installation et
`Open-Demo.ps1` exportent uniquement son certificat **public** dans
`work/tls/devops-lab-root-ca.crt` et ne modifient pas la confiance Windows.

Pour approuver explicitement cette autorité pour l'utilisateur Windows courant :

```powershell
.\scripts\Export-LabCA.ps1 -Trust
```

Fermer puis rouvrir le navigateur. Cette commande importe le certificat public
dans `Cert:\CurrentUser\Root`, sans exporter la clé privée. Elle ne nécessite
pas d'installation dans le magasin système. Noter l'empreinte affichée.
Un navigateur avec son propre magasin de certificats peut nécessiter l'import
du même fichier public dans ses paramètres.

Pour retirer plus tard cette confiance, ouvrir `certmgr.msc`, retrouver le
certificat **Devops Lab Local Root CA** dans les autorités racines de confiance,
vérifier son empreinte et supprimer uniquement cette entrée. Cela ne supprime
aucun certificat ou Secret du cluster.

## Certificats et renouvellement

La racine est conservée dans `cert-manager/devops-lab-root-ca`. Le ClusterIssuer
`devops-lab-ca` l'utilise pour émettre le certificat de l'application. Ce dernier
est décrit par `demo/devops-demo-tls` ; sa clé privée et son certificat sont dans
le Secret du même nom, lu par Traefik.

Le certificat applicatif est demandé pour 90 jours, avec renouvellement 15 jours
avant expiration et rotation de clé à chaque émission. Traefik suit les mises à
jour du Secret. Ce comportement est configuré, mais n'a pas encore été observé.
L'autorité racine est demandée pour dix ans, avec conservation de sa clé aux
renouvellements ; la distribution de sa nouvelle version dans les postes reste
manuelle. Ce lab n'implémente pas de service de révocation ni de PKI de production.

Pour lire les dates et le statut sans afficher les clés privées :

```powershell
kubectl --context kind-devops-lab -n demo get certificate devops-demo-tls -o wide
kubectl --context kind-devops-lab -n demo describe certificate devops-demo-tls
```

**Attendu lors de la validation future :** condition `Ready=True`, dates de
validité et date de renouvellement présentes. Le remplacement de l'autorité ou
la perte du PC ne sont pas couverts par une simple réémission du certificat serveur.

## Validation HTTPS à exécuter plus tard

Laisser `Open-Demo.ps1` ouvert, puis dans un second terminal :

```powershell
.\scripts\Test-Https.ps1
```

Le script utilise `curl.exe` et le certificat racine exporté pour vérifier le
nom `localhost`, la chaîne de confiance, le routage Ingress, la version et la santé
HTTP. Il n'utilise pas `--insecure` et ne modifie pas le magasin de confiance.
Si le tunnel utilise un autre port, transmettre le même avec `-Port`.

Le rapport d'installation distingue **certificat prêt** et **requête HTTPS
réussie**. Il indique `HttpsEndpointTested=false` : l'ouverture du tunnel et ce
test doivent encore être effectués. Conserver le résultat réel avant de conclure.

## Diagnostic

| Symptôme | Vérifications |
| --- | --- |
| Connexion refusée sur 8443 | Terminal `Open-Demo.ps1`, disponibilité du port, Deployment et Service Traefik |
| Avertissement de confiance | Certificat public du PC concerné, empreinte, import explicite pour le bon utilisateur |
| Certificat Traefik par défaut | Secret `devops-demo-tls`, condition Ready du Certificate, nom `localhost`, classe Ingress |
| Réponse 404 | Host `localhost`, Ingress `devops-demo`, classe `traefik-lab`, point d'entrée `websecure` |
| Réponse 503 | Pods applicatifs prêts, sélecteur et endpoints du Service |
| Certificate non prêt | ClusterIssuer, événements Certificate et logs cert-manager |

```powershell
kubectl --context kind-devops-lab -n traefik get pods,svc
kubectl --context kind-devops-lab -n traefik logs deployment/traefik --tail=50
kubectl --context kind-devops-lab -n demo describe ingress devops-demo
kubectl --context kind-devops-lab -n demo describe certificate devops-demo-tls
kubectl --context kind-devops-lab get clusterissuer devops-lab-ca
kubectl --context kind-devops-lab -n cert-manager logs deployment/cert-manager --tail=50
kubectl --context kind-devops-lab -n demo get endpointslices -l kubernetes.io/service-name=devops-demo
```

Ne pas supprimer de Secret TLS, d'autorité, de CRD ou de release pour contourner
une erreur. Revenir à une configuration Git précédente après examen du commit
et de ses effets. Pour diagnostiquer, utiliser les logs, les événements et les
EndpointSlices ; conserver le chemin HTTPS via Traefik pour les requêtes web.

Sources : [chart Traefik](https://github.com/traefik/traefik-helm-chart/tree/v41.6.1/traefik),
[installation Helm cert-manager](https://cert-manager.io/docs/installation/helm/),
[bootstrap SelfSigned](https://cert-manager.io/docs/configuration/selfsigned/),
[autorité CA](https://cert-manager.io/docs/configuration/ca/).

Le contrôle `Test-Deployment.ps1` vérifie HTTPS via Traefik. Il ouvre un tunnel
temporaire si nécessaire et ferme seulement celui qu’il a créé. Sous Windows,
curl/Schannel utilise `--ssl-revoke-best-effort` pour cette autorité locale sans
point de distribution CRL ; la chaîne et le nom localhost restent vérifiés.
Aucun `--insecure` ni changement du magasin Windows n’est effectué.
