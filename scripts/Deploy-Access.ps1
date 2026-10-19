# Install local ingress/TLS controllers. This script must be run by the user.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$accessRoot = Join-Path $projectRoot 'infra/access'
$versions = Import-PowerShellDataFile (Join-Path $accessRoot 'versions.psd1')
function Invoke-AccessKubectl {
    & kubectl --context kind-devops-lab @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $($args -join ' ')" }
}
function Invoke-AccessHelm {
    & helm --kube-context kind-devops-lab @args
    if ($LASTEXITCODE -ne 0) { throw 'Helm failed. Inspect its output; no automatic uninstall or cluster reset was requested.' }
}
foreach ($tool in @('helm','kubectl')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is missing. Follow README prerequisites." }
}
Invoke-AccessKubectl get nodes

# Do not recreate a CA whose private key has been lost: recover the old Secret.
$rootCertificate = $null
$certificateApi = Invoke-AccessKubectl get crd certificates.cert-manager.io --ignore-not-found -o name
$certificateNamespace = Invoke-AccessKubectl get namespace cert-manager --ignore-not-found -o name
if ($certificateApi -and $certificateNamespace) {
    $rootCertificate = Invoke-AccessKubectl -n cert-manager get certificates.cert-manager.io devops-lab-root-ca --ignore-not-found -o name
}
if ($rootCertificate) {
    $rootSecret = Invoke-AccessKubectl -n cert-manager get secret devops-lab-root-ca --ignore-not-found -o name
    if (-not $rootSecret) { throw 'The existing root Certificate has lost its Secret. Recover the original CA; it has not been regenerated.' }
}

Write-Host '[1/4] cert-manager (pinned Helm chart)'
Invoke-AccessHelm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --version $versions.CertManagerChartVersion --namespace cert-manager --create-namespace --values (Join-Path $accessRoot 'cert-manager-values.yaml') --wait --wait-for-jobs --timeout 300s
foreach ($crd in @('certificates.cert-manager.io','clusterissuers.cert-manager.io')) {
    Invoke-AccessKubectl wait --for=condition=Established "crd/$crd" --timeout=120s
}

Write-Host '[2/4] Local certificate authority (private keys stay in Kubernetes Secrets)'
Invoke-AccessKubectl apply -f (Join-Path $accessRoot 'pki/bootstrap-issuer.yaml')
Invoke-AccessKubectl wait --for=condition=Ready clusterissuer/devops-lab-selfsigned --timeout=120s
Invoke-AccessKubectl apply -f (Join-Path $accessRoot 'pki/root-ca.yaml')
Invoke-AccessKubectl -n cert-manager wait --for=condition=Ready certificate/devops-lab-root-ca --timeout=180s
Invoke-AccessKubectl apply -f (Join-Path $accessRoot 'pki/ca-issuer.yaml')
Invoke-AccessKubectl wait --for=condition=Ready clusterissuer/devops-lab-ca --timeout=120s

Write-Host '[3/4] Traefik (pinned Helm chart, ClusterIP Service)'
Invoke-AccessHelm upgrade --install traefik traefik --repo https://traefik.github.io/charts --version $versions.TraefikChartVersion --namespace traefik --create-namespace --values (Join-Path $accessRoot 'traefik-values.yaml') --wait --timeout 300s

Write-Host '[4/4] Export public CA certificate (no change to Windows trust store)'
& (Join-Path $PSScriptRoot 'Export-LabCA.ps1') | Out-Host
Write-Host 'Ingress and CA prepared. Deploy-Demo.ps1 creates the application Certificate and Ingress through ArgoCD.'
