# One entry point for a new Windows PC with Docker/Git/kind/kubectl/OpenSSH ready.
[CmdletBinding()]
param([switch]$RepoKeyAlreadyAdded)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Lab-Repository.ps1')
$timer = [Diagnostics.Stopwatch]::StartNew()
$steps = New-Object System.Collections.Generic.List[object]
function Invoke-InstallStep {
    param([string]$Name, [string]$Script)
    Write-Host "`n--- $Name ---"
    $stepTimer = [Diagnostics.Stopwatch]::StartNew()
    & (Join-Path $PSScriptRoot $Script) | Out-Host
    $steps.Add([pscustomobject]@{Name=$Name;Seconds=[math]::Round($stepTimer.Elapsed.TotalSeconds,1)})
}
Push-Location $projectRoot
try {
    foreach ($tool in @('git','docker','kind','kubectl','ssh-keygen')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is missing. Install the prerequisites in the README, then reopen PowerShell." }
    }
    $repository = Get-LabRepository -ProjectRoot $projectRoot
    $clusters = @(& kind get clusters)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect kind clusters.' }
    $clusterAlreadyExisted = $clusters -contains 'devops-lab'
    $branch = & git branch --show-current
    if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') { throw 'Use the main branch of your copy of the repository.' }
    $pending = & git status --porcelain
    if ($LASTEXITCODE -ne 0 -or $pending) { throw 'Commit and push your changes before installing.' }
    & git fetch origin main
    if ($LASTEXITCODE -ne 0) { throw 'GitHub access failed. Sign in with an account allowed to read your repository.' }
    $head = & git rev-parse HEAD
    $remote = & git rev-parse origin/main
    if ($LASTEXITCODE -ne 0 -or $head -ne $remote) { throw 'Local main must match origin/main. Synchronize the repository before installing.' }
    Write-Host "Repository: $($repository.WebUrl)"
    Invoke-InstallStep 'Cluster, registry and ArgoCD' 'Start-Lab.ps1'
    Invoke-InstallStep 'GitHub deploy key' 'Connect-ArgoRepo.ps1'
    if (-not $RepoKeyAlreadyAdded) {
        Write-Host "`nAdd the displayed PUBLIC key here: $($repository.KeysUrl)"
        Write-Host 'Leave Allow write access unchecked. Keep the private key in secrets/.'
        $answer = Read-Host 'Type OK after clicking Add key on GitHub'
        if ($answer -ne 'OK') { throw 'Installation stopped before deployment. Rerun once the public key is added.' }
    }
    Invoke-InstallStep 'Web application' 'Deploy-Demo.ps1'
    Invoke-InstallStep 'HTTP check' 'Test-Deployment.ps1'
    Invoke-InstallStep 'PostgreSQL and scheduled backup' 'Deploy-Postgres.ps1'
    Invoke-InstallStep 'Redis' 'Deploy-Redis.ps1'
    Invoke-InstallStep 'Full database restore into a new instance' 'Test-Restore.ps1'
    Invoke-InstallStep 'Prometheus, Grafana and alerts' 'Deploy-Monitoring.ps1'
    $timer.Stop()
    $report = [ordered]@{
        CompletedAtUtc=(Get-Date).ToUniversalTime().ToString('o')
        Repository=$repository.WebUrl
        TotalMinutes=[math]::Round($timer.Elapsed.TotalMinutes,2)
        IncludesPrerequisiteInstallation=$false
        IncludesKeyAuthorizationWait=$true
        ClusterAlreadyExisted=$clusterAlreadyExisted
        ExcludesRepositoryCopyAndClone=$true
        Steps=@($steps.ToArray())
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'work') | Out-Null
    [IO.File]::WriteAllText((Join-Path $projectRoot 'work/install-report.json'),($report | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    Write-Host "`nPASS: application, PostgreSQL, Redis, restore and monitoring checked in $($report.TotalMinutes) minutes."
    Write-Host 'Report: work/install-report.json. Follow README to open the interfaces.'
    if ($report.TotalMinutes -gt 30) { Write-Host 'The 30-minute target was exceeded. Inspect the per-step timings in the report.' }
} finally { Pop-Location }
