# Public HTTPS access requires no repository Secret or GitHub deploy key.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Lab-Repository.ps1')
$repository = Get-LabRepository -ProjectRoot $projectRoot

# Verify anonymous access rather than relying on cached GitHub credentials.
# This script does not change cluster resources or existing SSH keys.
$previousPrompt = $env:GIT_TERMINAL_PROMPT
$previousAskPass = $env:GIT_ASKPASS
try {
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GIT_ASKPASS = ''
    $refs = @(& git -c credential.helper= -c core.askPass= -c credential.interactive=never ls-remote --exit-code $repository.HttpsUrl refs/heads/main)
    if ($LASTEXITCODE -ne 0 -or $refs.Count -ne 1 -or $refs[0] -notmatch '^[0-9a-f]{40}\s+refs/heads/main$') {
        throw 'Anonymous HTTPS access to main failed. Ensure the repository is public and check the network connection.'
    }
} finally {
    $env:GIT_TERMINAL_PROMPT = $previousPrompt
    $env:GIT_ASKPASS = $previousAskPass
}
Write-Host "Public repository available: $($repository.HttpsUrl)"
Write-Host 'ArgoCD Applications will use HTTPS. No SSH key or GitHub login is needed for reading.'
