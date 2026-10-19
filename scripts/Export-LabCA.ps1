# Export only the public root certificate. Trust is an explicit user option.
[CmdletBinding()]
param([switch]$Trust)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$encoded = & kubectl --context kind-devops-lab -n cert-manager get secret devops-lab-root-ca -o 'jsonpath={.data.tls\.crt}'
if ($LASTEXITCODE -ne 0 -or -not $encoded) { throw 'The public root certificate is unavailable. Run Deploy-Access.ps1 first.' }
$bytes = [Convert]::FromBase64String($encoded)
$text = [Text.Encoding]::UTF8.GetString($bytes)
if ($text -notmatch '^-----BEGIN CERTIFICATE-----') { throw 'The root Secret does not contain a PEM certificate.' }
$directory = Join-Path $projectRoot 'work/tls'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$path = Join-Path $directory 'devops-lab-root-ca.crt'
[IO.File]::WriteAllBytes($path, $bytes)
if ($Trust) {
    if (-not (Get-Command Import-Certificate -ErrorAction SilentlyContinue)) { throw 'Windows Import-Certificate is unavailable. The public certificate was exported, but no trust was changed.' }
    $certificate = Import-Certificate -FilePath $path -CertStoreLocation Cert:\CurrentUser\Root
    if (-not $certificate -or -not (Test-Path "Cert:\CurrentUser\Root\$($certificate.Thumbprint)")) {
        throw 'The local CA was not trusted. Accept the Windows security confirmation, then retry.'
    }
    Write-Host "Local CA trusted for the current Windows user. Thumbprint: $($certificate.Thumbprint)"
}
Write-Host "Public CA certificate: $path"
Write-Output $path
