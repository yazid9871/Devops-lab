# Source and adaptations

Adapted from [WesleyCharlesBlake/k3d-argocd-template](https://github.com/WesleyCharlesBlake/k3d-argocd-template),
commit `cf17e98676edbd0aeedd1c0bfb38e34cbb191a02`, under the MIT license.
The original copyright and license are retained in [LICENSE](LICENSE).

The Go application, migrations and application Helm chart originate from that
template. The GitOps layout and README structure follow its approach.

Adaptations:

- One server, two agents, loopback ports and local registry on 5050.
- Explicit Helm-managed Traefik instead of K3s bundled Traefik.
- Portable Python commands; Make optional, no PowerShell dependency.
- Updated pinned charts and compatible Go builder.
- Alloy replaces end-of-life Promtail. No standalone Tempo or Mimir.
- Random persistent Grafana credentials, no admin/admin default.
- Traefik Middleware, metrics dashboard, JSON access logs and separate test clients.
- Child Application health checks for dependency ordering.
- Binary-safe logical backup and restore into a separate CNPG cluster.
- Original Kind lab and database retained; no automatic data migration.

Multiple Docker nodes on one PC do not provide host-level high availability.
