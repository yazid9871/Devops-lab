# Ouvrir les interfaces du lab

Chaque commande ci-dessous garde son terminal occupé : **utiliser un terminal
séparé par interface** et le laisser ouvert. `Ctrl+C` ferme le tunnel.

**Application :**

```powershell
kubectl --context kind-devops-lab -n demo port-forward svc/devops-demo 8081:80
```

Ouvrir [localhost:8081](http://localhost:8081).

**Grafana :**

```powershell
kubectl --context kind-devops-lab -n monitoring port-forward svc/grafana 3000:3000
```

Ouvrir [le dashboard DevOps Lab](http://localhost:3000/d/devops-lab), compte `admin`.
Pour afficher son mot de passe, dans un autre PowerShell :

```powershell
$encoded = kubectl --context kind-devops-lab -n monitoring get secret lab-grafana-admin -o jsonpath='{.data.admin-password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Le tableau montre tous les pods, tous états confondus, avec `demo` en premier.
Les alertes couvrent les pods en erreur, PostgreSQL, les sauvegardes et Redis
s'il est installé. Elles sont locales, sans envoi d'email.

**ArgoCD :**

```powershell
kubectl --context kind-devops-lab -n argocd port-forward svc/argocd-server 8080:443
```

Ouvrir [localhost:8080](https://localhost:8080), accepter le certificat local,
puis se connecter avec `admin`. Pour obtenir le mot de passe initial :

```powershell
$encoded = kubectl --context kind-devops-lab -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

Le changer dans **User Info → Update Password**. S'il a déjà été changé, utiliser
le mot de passe choisi.
