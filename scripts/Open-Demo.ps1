# Foreground tunnel through Traefik. Ctrl+C closes it.
[CmdletBinding()]
param([ValidateRange(1,65535)][int]$Port = 8443)
$ErrorActionPreference = 'Stop'
$null = & (Join-Path $PSScriptRoot 'Export-LabCA.ps1')
Write-Host "Open https://localhost:$Port"
Write-Host 'For browser trust, run scripts/Export-LabCA.ps1 -Trust separately, then reopen the browser.'
Write-Host 'Keep this terminal open. Ctrl+C stops only this tunnel.'
& kubectl --context kind-devops-lab -n traefik port-forward svc/traefik "${Port}:443" --address=127.0.0.1
if ($LASTEXITCODE -ne 0) { throw 'The HTTPS tunnel stopped with an error. Check Traefik readiness and whether the local port is in use.' }
