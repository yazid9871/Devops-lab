# Generate a dedicated deploy key and register its private part in local ArgoCD.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$keyDir = Join-Path $projectRoot 'secrets'
$keyPath = Join-Path $keyDir 'argocd-github'
$publicPath = $keyPath + '.pub'
$repoUrl = 'ssh://git@ssh.github.com:443/yazid9871/Devops-lab.git'
foreach ($tool in @('git', 'kubectl', 'ssh-keygen')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is missing from PATH." }
}
& kubectl --context kind-devops-lab -n argocd get deployment argocd-repo-server -o name
if ($LASTEXITCODE -ne 0) { throw 'Start the lab first.' }
& git -C $projectRoot check-ignore --quiet secrets/argocd-github
if ($LASTEXITCODE -ne 0) { throw 'The private key must be excluded from Git before continuing.' }
if ((Test-Path $keyPath) -ne (Test-Path $publicPath)) {
    throw 'Incomplete key pair. Inspect the secrets folder; no key has been overwritten.'
}
New-Item -ItemType Directory -Force -Path $keyDir | Out-Null
if (-not (Test-Path $keyPath)) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Command ssh-keygen).Source
    $info.Arguments = '-t ed25519 -C "argocd-devops-lab" -f "' + $keyPath + '" -N ""'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    $null = $process.StandardOutput.ReadToEnd()
    $failure = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Key generation failed: $failure" }
}
# Limit access to the private key to the current Windows user.
$account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls $keyPath /inheritance:r /grant:r "${account}:(F)" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to protect the private key file.' }
$knownHosts = & kubectl --context kind-devops-lab -n argocd get configmap argocd-ssh-known-hosts-cm -o 'jsonpath={.data.ssh_known_hosts}'
if ($LASTEXITCODE -ne 0 -or ($knownHosts -join "`n") -notmatch '\[ssh\.github\.com\]:443') {
    throw 'ArgoCD does not have a trusted host key for ssh.github.com:443.'
}
$repoSecret = @{
    apiVersion = 'v1'
    kind = 'Secret'
    metadata = @{
        name = 'devops-lab-github'
        namespace = 'argocd'
        labels = @{ 'argocd.argoproj.io/secret-type' = 'repository' }
    }
    type = 'Opaque'
    data = @{
        type = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('git'))
        url = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($repoUrl))
        sshPrivateKey = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keyPath))
    }
}
# Pipe the secret directly to Kubernetes. Do not write or print it.
$repoSecret | ConvertTo-Json -Depth 6 -Compress | & kubectl --context kind-devops-lab apply --server-side -f -
if ($LASTEXITCODE -ne 0) { throw 'Unable to register the repository credential in ArgoCD.' }
Write-Host 'Public key to add to GitHub (leave Allow write access unchecked):'
Get-Content -LiteralPath $publicPath
Write-Host 'GitHub repository > Settings > Deploy keys > Add deploy key'
Write-Host 'This prepares the credential; repository access is verified after adding the public key.'
