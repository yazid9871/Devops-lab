# Read the version contract used by startup, publication and deployment checks.
function Get-LabDemoChart {
    param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
    $chartPath = Join-Path $ProjectRoot 'charts/devops-demo'
    $valuesPath = Join-Path $chartPath 'values.yaml'
    $values = [IO.File]::ReadAllText($valuesPath)
    $tagPattern = '(?m)^  tag: "v(?<version>\d+)"\r?$'
    $tags = [regex]::Matches($values, $tagPattern)
    if ($tags.Count -ne 1) { throw 'Expected one numeric image.tag in charts/devops-demo/values.yaml (example: tag: "v1").' }
    if ([regex]::Matches($values, '(?m)^  repository: localhost:5001/devops-demo\r?$').Count -ne 1) {
        throw 'The lab chart must use the local registry localhost:5001/devops-demo.'
    }
    $version = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'app/VERSION')).Trim()
    if ($version -notmatch '^\d+$' -or $tags[0].Groups['version'].Value -ne $version) {
        throw 'app/VERSION and the Helm image.tag must match.'
    }
    $ingress = [regex]::Match($values, '(?m)^ingress:\r?\n  enabled: (?<enabled>true|false)\r?$')
    if (-not $ingress.Success) { throw 'Expected ingress.enabled: true or false in the Helm values.' }
    [pscustomobject]@{
        ChartPath = $chartPath
        ValuesPath = $valuesPath
        Values = $values
        TagPattern = $tagPattern
        Version = $version
        Image = "localhost:5001/devops-demo:v$version"
        IngressEnabled = $ingress.Groups['enabled'].Value -eq 'true'
    }
}
