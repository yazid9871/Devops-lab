# Resolve the colleague's GitHub repository from origin; never rewrite tracked files.
function Get-LabRepository {
    param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
    $origin = & git -C $ProjectRoot remote get-url origin
    if ($LASTEXITCODE -ne 0) { throw 'Clone your GitHub repository first (origin is required).' }
    $pattern = '^(?:https://github\.com/|git@github\.com:|ssh://git@(?:github\.com|ssh\.github\.com)(?::443)?/)(?<owner>[A-Za-z0-9-]+)/(?<repo>[A-Za-z0-9_.-]+)/?$'
    if ($origin -notmatch $pattern) { throw 'origin must be a GitHub HTTPS or SSH URL, without an embedded token.' }
    $owner = $Matches.owner
    $repository = $Matches.repo -replace '\.git$', ''
    if ($owner -in @('OWNER','TON-COMPTE') -or -not $repository) { throw 'Replace the example URL with your own GitHub repository.' }
    [pscustomobject]@{
        SshUrl = "ssh://git@ssh.github.com:443/$owner/$repository.git"
        WebUrl = "https://github.com/$owner/$repository"
        KeysUrl = "https://github.com/$owner/$repository/settings/keys"
    }
}

function Get-LabApplicationText {
    param([string]$ManifestPath, [string]$RepositoryUrl)
    $text = [IO.File]::ReadAllText($ManifestPath)
    if ([regex]::Matches($text, '(?m)^    repoURL: .+\r?$').Count -ne 1) { throw 'Expected one Application repository URL.' }
    [regex]::Replace($text, '(?m)^    repoURL: .+\r?$', ('    repoURL: ' + $RepositoryUrl))
}

function Set-LabApplication {
    param([Parameter(Mandatory=$true)][string]$ManifestPath)
    $repository = Get-LabRepository
    $text = Get-LabApplicationText -ManifestPath $ManifestPath -RepositoryUrl $repository.SshUrl
    $nameMatch = [regex]::Match($text, '(?m)^  name: ([a-z0-9-]+)\r?$')
    if (-not $nameMatch.Success) { throw 'Application manifest name is missing.' }
    $name = $nameMatch.Groups[1].Value
    $existing = & kubectl --context kind-devops-lab -n argocd get application $name --ignore-not-found -o json
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the existing ArgoCD Application.' }
    if ($existing) {
        $app = $existing | ConvertFrom-Json
        if ($app.spec.source.repoURL -ne $repository.SshUrl) {
            throw "Application $name belongs to another repository. Use its original checkout; no source has been changed."
        }
    }
    $text | & kubectl --context kind-devops-lab apply -f -
    if ($LASTEXITCODE -ne 0) { throw "Unable to deploy Application $name." }
    & kubectl --context kind-devops-lab -n argocd annotate application $name argocd.argoproj.io/refresh=hard --overwrite
    if ($LASTEXITCODE -ne 0) { throw 'Unable to refresh ArgoCD.' }
}
