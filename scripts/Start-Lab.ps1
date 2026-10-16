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
    Write-Host '[1/4] Kubernetes'
    $clusters = @(& kind get clusters)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to list kind clusters.' }
    if ($clusters -notcontains 'devops-lab') {
        Invoke-Checked kind @('create', 'cluster', '--name', 'devops-lab', '--image', 'kindest/node:v1.37.0', '--wait', '120s')
    }
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', 'wait', '--for=condition=Ready', 'node', '--all', '--timeout=120s')

    Write-Host '[2/4] Local registry'
    & (Join-Path $PSScriptRoot 'Setup-Registry.ps1')

    Write-Host '[3/4] ArgoCD'
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', 'apply', '-f', (Join-Path $projectRoot 'infra/argocd/namespace.yaml'))
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', 'apply', '--server-side', '-n', 'argocd', '-f', (Join-Path $projectRoot 'infra/argocd/install.yaml'))
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', '-n', 'argocd', 'wait', '--for=condition=Available', 'deployment', '--all', '--timeout=300s')
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', '-n', 'argocd', 'rollout', 'status', 'statefulset/argocd-application-controller', '--timeout=300s')

    Write-Host '[4/4] Demo image'
    $version = [IO.File]::ReadAllText((Join-Path $projectRoot 'app/VERSION')).Trim()
    if ($version -notmatch '^\d+$') { throw 'Expected a numeric app/VERSION.' }
    $manifest = [IO.File]::ReadAllText((Join-Path $projectRoot 'k8s/demo/kustomization.yaml'))
    if ($manifest -notmatch "(?m)^    newTag: v$version\r?`$") { throw 'App version and desired image tag must match.' }
    $image = "localhost:5001/devops-demo:v$version"
    $tags = @()
    try { $tags = (Invoke-RestMethod -Uri 'http://127.0.0.1:5001/v2/devops-demo/tags/list' -TimeoutSec 10).tags }
    catch { if ([int]$_.Exception.Response.StatusCode -ne 404) { throw } }
    if ($tags -notcontains "v$version") {
        Invoke-Checked docker @('build', '--provenance=false', '--tag', $image, (Join-Path $projectRoot 'app'))
        Invoke-Checked docker @('push', $image)
    } else {
        Invoke-Checked docker @('pull', $image)
    }
    $testFile = Join-Path $PSScriptRoot 'smoke_test.py'
    Invoke-Checked docker @('run', '--rm', '--read-only', '--network', 'none', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--mount', "type=bind,source=$testFile,target=/tmp/smoke_test.py,readonly", $image, 'python', '/tmp/smoke_test.py', $version)
    $nodes = @(& kind get nodes --name devops-lab)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to list cluster nodes.' }
    foreach ($nodeName in $nodes) {
        Invoke-Checked docker @('exec', $nodeName, 'crictl', 'pull', $image)
    }
    Invoke-Checked kubectl @('--context', 'kind-devops-lab', 'apply', '--dry-run=client', '-k', (Join-Path $projectRoot 'k8s/demo'))
    Write-Host 'Infrastructure ready. Follow the README to connect GitHub and deploy the services.'
} finally {
    $env:DOCKER_CONTEXT = $previousDockerContext
}
