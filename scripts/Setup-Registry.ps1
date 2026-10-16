# Configure the existing kind cluster; never recreate it.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$registryName = 'devops-lab-registry'
$registryImage = 'registry:3@sha256:ddf754342cfc8acc51a56d5d0ab6af06826461864460636d8bd5c546dab2a7b8'
$contextName = 'kind-devops-lab'
function Invoke-LabDocker {
    & docker --context desktop-linux @args
    if ($LASTEXITCODE -ne 0) { throw "Docker failed: $($args -join ' ')" }
}
function Invoke-LabKubectl {
    & kubectl --context $contextName @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $($args -join ' ')" }
}

# Check prerequisites and cluster before making changes.
Invoke-LabDocker info --format '{{.OSType}}'
$nodes = @(& kind get nodes --name devops-lab)
if ($LASTEXITCODE -ne 0 -or $nodes.Count -eq 0) { throw 'Cluster devops-lab absent.' }
Invoke-LabKubectl get nodes

$existing = @(Invoke-LabDocker ps -a --filter "name=^/${registryName}$" --format '{{.Names}}')
if ($existing -contains $registryName) {
    $registry = (Invoke-LabDocker inspect $registryName | ConvertFrom-Json)[0]
    $binding = @($registry.HostConfig.PortBindings.'5000/tcp')
    if ($binding.Count -ne 1 -or $binding[0].HostIp -ne '127.0.0.1' -or $binding[0].HostPort -ne '5001') {
        throw 'Existing registry has unexpected port bindings; inspect it manually.'
    }
    $dataMount = @($registry.Mounts | Where-Object { $_.Destination -eq '/var/lib/registry' })
    if ($dataMount.Count -ne 1 -or $dataMount[0].Name -ne 'devops-lab-registry-data') {
        throw 'Existing registry has an unexpected storage mount; inspect it manually.'
    }
    if (-not $registry.State.Running) { Invoke-LabDocker start $registryName }
} else {
    Invoke-LabDocker volume create --label devops.lab=registry devops-lab-registry-data
    Invoke-LabDocker run --detach --restart unless-stopped --name $registryName --label devops.lab=registry --publish 127.0.0.1:5001:5000 --mount 'type=volume,source=devops-lab-registry-data,target=/var/lib/registry' $registryImage
}
$registry = (Invoke-LabDocker inspect $registryName | ConvertFrom-Json)[0]
if (-not $registry.NetworkSettings.Networks.PSObject.Properties['kind']) {
    Invoke-LabDocker network connect kind $registryName
}

foreach ($nodeName in $nodes) {
    $effective = (Invoke-LabDocker exec $nodeName containerd config dump) -join "`n"
    if ($effective -notmatch 'config_path\s*=\s*["'']/etc/containerd/certs.d["'']') {
        $original = (Invoke-LabDocker exec $nodeName cat /etc/containerd/config.toml) -join "`n"
        if ($original -notmatch '(?m)^version\s*=\s*2\s*$' -or $original -match '(?m)^\[plugins\."io.containerd.grpc.v1.cri"\.registry\]') {
            throw "Unsupported containerd config on $nodeName; no overwrite attempted."
        }
        $patched = $original + "`n`n" + @'
[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = "/etc/containerd/certs.d"
'@
        $scratchDir = Join-Path $projectRoot 'work/registry'
        New-Item -ItemType Directory -Force -Path $scratchDir | Out-Null
        $scratchFile = Join-Path $scratchDir "$nodeName-config.toml"
        [IO.File]::WriteAllText($scratchFile, $patched + "`n", [Text.UTF8Encoding]::new($false))
        Invoke-LabDocker exec $nodeName cp -n /etc/containerd/config.toml /etc/containerd/config.toml.devops-lab.bak
        Invoke-LabDocker cp $scratchFile "${nodeName}:/etc/containerd/config.toml"
        $effective = (Invoke-LabDocker exec $nodeName containerd config dump) -join "`n"
        if ($effective -notmatch 'config_path\s*=\s*["'']/etc/containerd/certs.d["'']') {
            throw 'Registry config_path was not activated; original config remains in .devops-lab.bak.'
        }
        Invoke-LabDocker exec $nodeName systemctl restart containerd
        Invoke-LabDocker exec $nodeName systemctl is-active containerd
    }
    Invoke-LabDocker exec $nodeName mkdir -p /etc/containerd/certs.d/localhost:5001
    Invoke-LabDocker cp (Join-Path $projectRoot 'infra/registry/hosts.toml') "${nodeName}:/etc/containerd/certs.d/localhost:5001/hosts.toml"
}
Invoke-LabKubectl apply -f (Join-Path $projectRoot 'infra/registry/local-registry-hosting.yaml')
Invoke-LabKubectl wait --for=condition=Ready node --all --timeout=120s
$available = $false
for ($attempt = 0; $attempt -lt 15; $attempt++) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:5001/v2/' -TimeoutSec 3
        if ($response.StatusCode -eq 200) { $available = $true; break }
    } catch { Start-Sleep -Seconds 1 }
}
if (-not $available) { throw 'Registry HTTP endpoint is not ready.' }
Write-Output 'Registry ready: localhost:5001 -> devops-lab-registry:5000'
