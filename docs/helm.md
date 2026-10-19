# Application geree avec Helm et ArgoCD

## Etat de cette evolution

Le chart est deploye via ArgoCD. La version 0.3.0 ajoute la connexion PostgreSQL
et une readiness qui verifie la base. Les validations du 16 octobre concernent
l'ancienne configuration Kustomize. Voir application-postgresql.md.

## Role de chaque fichier

| Fichier | Role |
| --- | --- |
| `charts/devops-demo/Chart.yaml` | Identite du chart et version de ses templates |
| `charts/devops-demo/values.yaml` | Image, nombre de replicas, port et ressources |
| `charts/devops-demo/values.schema.json` | Contraintes de configuration utilisees par Helm |
| `charts/devops-demo/templates/` | Namespace, Deployment, Service, Ingress et Certificate a generer |
| `infra/argocd/demo-application.yaml` | Source Git, chemin du chart, release `devops-demo`, destination `demo` |
| `app/VERSION` | Version retournee par l'application dans l'image construite |

La version du chart (`0.3.0`) decrit ses templates. Le tag d'image (`v1`, `v2`...)
decrit une publication de l'application. Le script de publication modifie le tag
dans `values.yaml` et la version dans `app/VERSION` ensemble.

ArgoCD execute le rendu Helm puis applique les objets Kubernetes. Il gere leur
cycle de vie ; il n'installe pas une release geree par la CLI Helm. Ne pas utiliser
`helm install`, `helm upgrade`, `helm rollback` ou `helm uninstall` sur cette application.
L'absence de release dans `helm list` ne signifie donc pas qu'ArgoCD a echoue.

## Installation

Helm est ajoute aux prerequis du [README](../README.md) :

```powershell
winget install --exact --id Helm.Helm --source winget
```

Fermer et rouvrir PowerShell apres installation. `Install-Lab.ps1` exige Helm,
puis `Start-Lab.ps1` controle le chart avant de preparer le cluster et l'image.
PostgreSQL, Redis et la supervision conservent leurs manifests Kustomize.
Le [guide HTTPS](https-local.md) explique les deux releases Helm des controleurs
Traefik et cert-manager, qui sont distinctes de l'application geree par ArgoCD.

## Transition du lab existant (a executer plus tard)

Publier d'abord ces fichiers sur `main`, puis mettre a jour le checkout local.
Ne pas lancer le deploiement avant publication : ArgoCD lit GitHub, pas les fichiers
non committes du PC. Quand l'utilisateur sera pret a deployer :

```powershell
.\scripts\Deploy-Access.ps1
.\scripts\Deploy-Demo.ps1
.\scripts\Test-Deployment.ps1
```

Le Deployment et le Service restent nommes `devops-demo`, avec le selecteur
`app: devops-demo`, dans le namespace `demo`. Les anciens fichiers `k8s/demo/`
sont remplaces dans le depot par le chart. Aucun changement n'a ete applique au
cluster lors de la preparation des fichiers. Aucune base ni aucun volume n'est
gere par ce chart. ArgoCD conserve sa politique `prune: false`.

## Publication et retour arriere (a executer plus tard)

Le [runbook](runbook.md) reste le point d'entree. `Publish-Demo.ps1` prepare les
deux numeros de version, controle le chart, construit et teste l'image, puis
publie l'image et pousse le commit. S'il echoue avant le commit, les fichiers
peuvent rester modifies : lire l'erreur et examiner `git diff` avant de relancer.
Ne pas annuler des modifications locales sans les avoir examinees.

Un `git revert` du commit **de publication applicative** restaure l'ancien tag et
`app/VERSION`. Il ne faut pas selectionner le commit de migration Helm a sa place.
L'ancienne image doit encore exister dans le registry local.

## Commandes de controle pour la phase de tests ulterieure

Ces commandes sont fournies pour l'utilisateur ; elles n'ont pas ete lancees
dans le cadre de la preparation de cette evolution.

```powershell
helm lint .\charts\devops-demo --strict
helm template devops-demo .\charts\devops-demo --namespace demo
.\scripts\Test-Deployment.ps1
```

Les deux premieres commandes controlent les fichiers sans appliquer le chart.
La derniere verifie ArgoCD, le chemin du chart, l'image deployee et la reponse HTTP.
Le test de publication/rollback et la reception sur un autre PC restent a faire.
Le controle HTTPS de bout en bout est fourni dans `Test-Https.ps1` et necessite
le tunnel `Open-Demo.ps1`. Ces nouveaux scripts n'ont pas ete executes.

Reference : [Helm avec ArgoCD](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/).
