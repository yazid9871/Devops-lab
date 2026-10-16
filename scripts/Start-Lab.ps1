# Recreate the implemented part of the lab, or restart it without deleting data.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
function Invoke-Checked {
    param([string]$Tool, [string[]]$Arguments)
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed: $Tool $($Arguments -join ' ')" }
}
foreach ($tool in @('docker', 'kind', 'kubectl')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is missing from PATH. Install it and open a new PowerShell."
    }
}
$previousDockerContext = $env:DOCKER_CONTEXT
$env:DOCKER_CONTEXT = 'desktop-linux'
try {
    $osType = & docker info --format '{{.OSType}}'
    if ($LASTEXITCODE -ne 0 -or $osType -ne 'linux') {
        throw 'Start Docker Desktop with the Linux engine before running this script.'
    }
    Write-Host '[1/5] Kubernetes'
    $clusters = @(& kind get clusters)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to list kind clusters.' }
    if ($clusters -notcontains 'devops-lab') {
        Invoke-Checked kind @('create', 'cluster', '--name', 'devops-lab', '--image', 'kindest/node:v1.37.0', '--wait', '120s')
    }
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', 'wait', '--for=condition=Ready', 'node', '--all', '--timeout=120s')

    Write-Host '[2/5] Local registry'
    & (Join-Path $PSScriptRoot 'Setup-Registry.ps1')

    Write-Host '[3/5] ArgoCD'
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', 'apply', '-f', (Join-Path $projectRoot 'infra/argocd/namespace.yaml'))
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', 'apply', '--server-side', '-n', 'argocd', '-f', (Join-Path $projectRoot 'infra/argocd/install.yaml'))
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', '-n', 'argocd', 'wait', '--for=condition=Available', 'deployment', '--all', '--timeout=300s')
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', '-n', 'argocd', 'rollout', 'status', 'statefulset/argocd-application-controller', '--timeout=300s')

    Write-Host '[4/5] Demo image'
    Invoke-Checked docker @('build', '--tag', 'devops-demo:v1', (Join-Path $projectRoot 'app'))
    Invoke-Checked docker @('tag', 'devops-demo:v1', 'localhost:5001/devops-demo:v1')
    Invoke-Checked docker @('push', 'localhost:5001/devops-demo:v1')
    $nodes = @(& kind get nodes --name devops-lab)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to list cluster nodes.' }
    foreach ($nodeName in $nodes) {
        Invoke-Checked docker @('exec', $nodeName, 'crictl', 'pull', 'localhost:5001/devops-demo:v1')
    }
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', 'apply', '--dry-run=client', '-k', (Join-Path $projectRoot 'k8s/demo'))

    Write-Host '[5/5] Local preview'
    $names = @(& docker ps -a --filter 'name=^/devops-demo-preview$' --format '{{.Names}}')
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect preview container.' }
    if ($names -contains 'devops-demo-preview') {
        $container = (& docker inspect devops-demo-preview | ConvertFrom-Json)[0]
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect preview container.' }
        $expectedImage = (& docker image inspect devops-demo:v1 | ConvertFrom-Json)[0]
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect demo image.' }
        $currentImage = (& docker image inspect $container.Image | ConvertFrom-Json)[0]
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect running demo image.' }
        # Build attestations can change the image ID even when its files are identical.
        $sameLayers = ($currentImage.RootFS.Layers -join ',') -eq ($expectedImage.RootFS.Layers -join ',')
        $sameConfig = ($currentImage.Config | ConvertTo-Json -Depth 10 -Compress) -eq ($expectedImage.Config | ConvertTo-Json -Depth 10 -Compress)
        $portBindings = @($container.HostConfig.PortBindings.'8080/tcp')
        if (-not $sameLayers -or -not $sameConfig -or $portBindings.Count -ne 1 -or $portBindings[0].HostIp -ne '127.0.0.1' -or $portBindings[0].HostPort -ne '18080') {
            throw 'An incompatible preview container already exists. Inspect it before replacing it.'
        }
        if (-not $container.State.Running) { Invoke-Checked docker @('start', 'devops-demo-preview') }
    } else {
        Invoke-Checked docker @('run', '--detach', '--name', 'devops-demo-preview', '--label', 'devops.lab=preview', '--read-only', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--publish', '127.0.0.1:18080:8080', 'devops-demo:v1')
    }
    $healthy = $false
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:18080/healthz' -TimeoutSec 3
            if ($health.status -eq 'ok') { $healthy = $true; break }
        } catch { Start-Sleep -Seconds 1 }
    }
    if (-not $healthy) { throw 'Demo health check failed.' }
    Write-Host 'Ready: http://localhost:18080'
    Write-Host 'The demo runs in Docker. ArgoCD Git access and app sync are the next step.'
} finally {
    $env:DOCKER_CONTEXT = $previousDockerContext
}
