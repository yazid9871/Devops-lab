[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Name, [int]$TimeoutSeconds = 240)
$ErrorActionPreference = 'Stop'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    $raw = & kubectl --context kind-devops-lab -n data get job $Name -o json
    if ($LASTEXITCODE -ne 0) { throw "Unable to read job $Name" }
    $job = $raw | ConvertFrom-Json
    if ($job.status.succeeded -ge 1) { return }
    if (@($job.status.conditions | Where-Object { $_.type -eq 'Failed' -and $_.status -eq 'True' }).Count -gt 0) {
        & kubectl --context kind-devops-lab -n data logs "job/$Name" | Out-Host
        throw "Job $Name failed."
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
& kubectl --context kind-devops-lab -n data get pods -l "job-name=$Name" | Out-Host
throw "Timed out waiting for job $Name"
