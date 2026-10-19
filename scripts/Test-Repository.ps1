# Offline portability checks: no GitHub account or cluster is changed.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Lab-Repository.ps1')
$fixture = Join-Path $projectRoot ('work/repository-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $fixture | Out-Null
& git init -q -b main $fixture
if ($LASTEXITCODE -ne 0) { throw 'Cannot create the isolated Git fixture.' }
& git -C $fixture remote add origin https://github.com/colleague/custom-lab.git
if ($LASTEXITCODE -ne 0) { throw 'Cannot create the fixture origin.' }
foreach ($url in @('https://github.com/colleague/custom-lab.git','https://github.com/colleague/custom-lab','git@github.com:colleague/custom-lab.git','ssh://git@github.com/colleague/custom-lab.git','ssh://git@ssh.github.com:443/colleague/custom-lab.git')) {
    & git -C $fixture remote set-url origin $url
    if ($LASTEXITCODE -ne 0) { throw 'Cannot configure the fixture URL.' }
    $repository = Get-LabRepository -ProjectRoot $fixture
    if ($repository.HttpsUrl -ne 'https://github.com/colleague/custom-lab.git' -or $repository.WebUrl -ne 'https://github.com/colleague/custom-lab') { throw 'GitHub origin normalization failed.' }
    foreach ($file in Get-ChildItem (Join-Path $projectRoot 'infra/argocd') -Filter '*application.yaml') {
        $text = Get-LabApplicationText -ManifestPath $file.FullName -RepositoryUrl $repository.HttpsUrl
        if (-not $text.Contains('repoURL: ' + $repository.HttpsUrl) -or $text.Contains('/OWNER/') -or $text.Contains('repoURL: ssh://')) { throw 'Application HTTPS portability failed.' }
    }
}
foreach ($url in @('https://example.org/colleague/custom-lab.git','https://github.com/TON-COMPTE/Devops-lab.git')) {
    & git -C $fixture remote set-url origin $url
    $rejected = $false
    try { $null = Get-LabRepository -ProjectRoot $fixture } catch { $rejected = $true }
    if (-not $rejected) { throw 'An unsupported origin was accepted.' }
}
Write-Host 'PASS: 5 GitHub URL formats, 4 Applications per format and 2 invalid origins checked offline.'
