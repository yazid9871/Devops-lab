# Local CI: build -> test -> push image -> commit desired version -> push Git.
[CmdletBinding()]
param([ValidateRange(0, 999999)][int]$Version = 0)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
function Invoke-CiCommand {
    param([string]$Tool, [string[]]$Arguments)
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed: $Tool $($Arguments -join ' ')" }
}
Push-Location $projectRoot
$previousContext = $env:DOCKER_CONTEXT
$env:DOCKER_CONTEXT = 'desktop-linux'
try {
    $branch = & git branch --show-current
    if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Run the pipeline from branch main.' }
    $pending = & git status --porcelain
    if ($LASTEXITCODE -ne 0 -or $pending) { throw 'Commit your changes before running the pipeline.' }
    $null = & git var GIT_AUTHOR_IDENT
    if ($LASTEXITCODE -ne 0) { throw 'Configure git user.name and user.email for this repository first.' }
    Invoke-CiCommand git @('fetch', 'origin', 'main')
    $head = & git rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read HEAD.' }
    $remote = & git rev-parse origin/main
    if ($LASTEXITCODE -ne 0 -or $head -ne $remote) { throw 'Local main must match origin/main before publishing.' }
    $tags = (Invoke-RestMethod -Uri 'http://127.0.0.1:5001/v2/devops-demo/tags/list' -TimeoutSec 10).tags
    $current = [int]([IO.File]::ReadAllText((Join-Path $projectRoot 'app/VERSION')).Trim())
    if ($Version -eq 0) {
        $numbers = @($current)
        foreach ($tag in $tags) { if ($tag -match '^v(\d+)$') { $numbers += [int]$Matches[1] } }
        $Version = [int](($numbers | Measure-Object -Maximum).Maximum) + 1
    }
    if ($tags -contains "v$Version") { throw "Image v$Version already exists. Choose a new version; existing tags are preserved." }
    $image = "localhost:5001/devops-demo:v$Version"
    Write-Host "[1/4] Build $image"
    [IO.File]::WriteAllText((Join-Path $projectRoot 'app/VERSION'), "$Version`n", [Text.UTF8Encoding]::new($false))
    Invoke-CiCommand docker @('build', '--provenance=false', '--tag', $image, (Join-Path $projectRoot 'app'))

    Write-Host '[2/4] Test image (HTTP, health, version, 404)'
    $testFile = Join-Path $PSScriptRoot 'smoke_test.py'
    Invoke-CiCommand docker @('run', '--rm', '--read-only', '--network', 'none', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--mount', "type=bind,source=$testFile,target=/tmp/smoke_test.py,readonly", $image, 'python', '/tmp/smoke_test.py', "$Version")

    Write-Host '[3/4] Publish image'
    Invoke-CiCommand docker @('push', $image)

    Write-Host '[4/4] Update Git'
    $manifestPath = Join-Path $projectRoot 'k8s/demo/kustomization.yaml'
    $manifest = [IO.File]::ReadAllText($manifestPath)
    if ([regex]::Matches($manifest, '(?m)^    newTag: v\d+\r?$').Count -ne 1) { throw 'Expected one numeric image tag in kustomization.yaml.' }
    $manifest = [regex]::Replace($manifest, '(?m)^    newTag: v\d+\r?$', "    newTag: v$Version")
    [IO.File]::WriteAllText($manifestPath, $manifest, [Text.UTF8Encoding]::new($false))
    Invoke-CiCommand kubectl @('kustomize', (Join-Path $projectRoot 'k8s/demo'))
    Invoke-CiCommand git @('add', '--', 'app/VERSION', 'k8s/demo/kustomization.yaml')
    Invoke-CiCommand git @('diff', '--cached', '--check')
    Invoke-CiCommand git @('commit', '-m', "Deploy demo v$Version")
    $commit = & git rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read deployment commit.' }
    Invoke-CiCommand git @('push', 'origin', 'main')
    Write-Host "Published version: $Version"
    Write-Host "Deployment commit: $commit"
    Write-Host "Rollback: git revert $commit"
    Write-Host 'Then: git push origin main'
    Write-Host 'ArgoCD will deploy automatically. The pipeline does not apply Kubernetes manifests.'
} finally {
    $env:DOCKER_CONTEXT = $previousContext
    Pop-Location
}
