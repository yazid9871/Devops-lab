# Comment le registry est relié à kind

Windows publie les images sur `localhost:5001`.
Dans le réseau Docker de kind, le même registry s'appelle `devops-lab-registry:5000`.
La configuration `infra/registry/hosts.toml` fait le lien entre les deux.

Le script `scripts/Setup-Registry.ps1` :

1. Vérifie que le cluster existe.
2. Crée ou réutilise le conteneur du registry et son volume `devops-lab-registry-data`.
3. Relie le registry au réseau Docker `kind`.
4. Active le dossier de configuration des registries dans containerd si nécessaire.
5. Copie `hosts.toml` dans chaque nœud.
6. Publie un ConfigMap qui indique l'adresse du registry aux outils.

Avant de modifier containerd, le script conserve le fichier original dans
`/etc/containerd/config.toml.devops-lab.bak`. Il peut redémarrer ce service.
Il s'arrête devant une configuration qu'il ne sait pas modifier.
Le cluster existant n'est pas recréé.

Le volume des images est distinct des conteneurs. Il reste sur le même PC :
ce stockage n'est pas une sauvegarde externe.
Le registry utilise HTTP sans authentification et écoute seulement sur
`127.0.0.1:5001` côté Windows. Cette configuration est réservée au lab.

## Commandes de contrôle

```powershell
docker --context desktop-linux ps --filter name=devops-lab-registry
Invoke-RestMethod http://127.0.0.1:5001/v2/devops-demo/tags/list
docker --context desktop-linux exec devops-lab-control-plane crictl pull localhost:5001/devops-demo:v1
```

Le dernier contrôle utilise le moteur de téléchargement de Kubernetes.
Un simple push depuis Windows ne suffirait pas à prouver cet accès.

Références : [kind](https://kind.sigs.k8s.io/docs/user/local-registry/) et
[containerd](https://github.com/containerd/containerd/blob/main/docs/hosts.md).
