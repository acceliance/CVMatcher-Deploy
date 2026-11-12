#Requires -Version 5.1
<#
.SYNOPSIS
    Déploie une instance (spec §4.1 étape 4) : -Stage kit,config,provision,app (une ou plusieurs étapes).
    Les images sont publiques sur Docker Hub : aucun identifiant de registre n'est nécessaire.
.EXAMPLE
    ./scripts/deploy.ps1 cvmatcher-client.acceliance.fr -Stage kit,config,provision,app -Licence licensing/deliveries/client/instance.lic
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$Fqdn,
    [ValidateSet("kit", "config", "provision", "app")] [string[]]$Stage = @("kit", "config", "provision", "app"),
    [string]$Licence = "",
    [switch]$Recette
)
. "$PSScriptRoot/lib/guards.ps1"

$dir = Get-InstanceDir $Fqdn
$hostCfgPath = Join-Path $dir "config.env"
$appCfgPath = Join-Path $dir "config.app.env"
$hostCfg = Read-EnvFile $hostCfgPath
$appCfg = Read-EnvFile $appCfgPath
$production = -not $Recette
Assert-LfOnly (Join-Path $script:RepoRoot "kit")
Assert-Instance $Fqdn $hostCfg $appCfg -Production:$production
Assert-LicenceDomain $Fqdn $Licence
Show-Summary $Fqdn $hostCfg $appCfg $Stage
if (-not $WhatIfPreference) { Confirm-Explicit "Déployer $Fqdn ?" }
$target = "$($hostCfg.SSH_USER)@$($hostCfg.SSH_HOST)"

# Connexions SSH regroupées (au plus 4 pour un déploiement complet) : un hôte dont ufw limite le port 22
# (« ufw limit » : 6 connexions en 30 s) bloquerait sinon le déploiement avant que 02-firewall.sh remplace la règle.
$copyKit = "kit" -in $Stage
$copyConfig = "config" -in $Stage
$copied = @(@{ kit = $copyKit; configuration = $copyConfig }.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key } | Sort-Object -Descending)
if ($copied -and $PSCmdlet.ShouldProcess($Fqdn, "copie : $($copied -join ', ')")) {
    # dossier de préparation local, à la disposition de /opt/cvmatcher-kit, copié en un seul scp puis effacé (secrets)
    $staging = Join-Path ([IO.Path]::GetTempPath()) ("cvm-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $staging | Out-Null
    try {
        if ($copyKit) {
            Copy-Item -Recurse (Join-Path $script:RepoRoot "kit/compose"), (Join-Path $script:RepoRoot "kit/ubuntu") $staging
        }
        if ($copyConfig) {
            Copy-Item $hostCfgPath (Join-Path $staging "config.env")
            Copy-Item $appCfgPath (Join-Path $staging "app.env")
            $seaweed = Join-Path $dir "seaweedfs-s3.json"
            if (Test-Path $seaweed) { Copy-Item $seaweed (Join-Path $staging "seaweedfs-s3.json") }
            # surcharge compose propre à l'instance (facultative) ; absente, 08-stage-app.sh retire celle de la VM
            $override = Join-Path $dir "docker-compose.override.yaml"
            if (Test-Path $override) { Copy-Item $override (Join-Path $staging "docker-compose.override.yaml") }
        }
        Invoke-Remote $hostCfg "sudo install -d -m 0750 -o `$USER /opt/cvmatcher-kit"
        $items = @(Get-ChildItem $staging | ForEach-Object { $_.FullName })
        $code = Invoke-Native { scp -q -r @items "${target}:/opt/cvmatcher-kit/" }
        if ($code -ne 0) { Fail "scp vers /opt/cvmatcher-kit ($code)" }
    } finally {
        Remove-Item -Recurse -Force $staging
    }
}
# commandes d'installation enchaînées dans une seule session SSH
$remote = @()
if ($copyConfig -and -not $WhatIfPreference) { $remote += "chmod 0600 /opt/cvmatcher-kit/config.env /opt/cvmatcher-kit/app.env" }
if ("provision" -in $Stage) {
    if ($PSCmdlet.ShouldProcess($Fqdn, "provisioning")) { $remote += "sudo bash /opt/cvmatcher-kit/ubuntu/provision.sh" }
} elseif ($copyConfig) {
    if ($PSCmdlet.ShouldProcess($Fqdn, "installation de la configuration")) { $remote += "sudo bash /opt/cvmatcher-kit/ubuntu/08-stage-app.sh" }
}
if ($remote) { Invoke-Remote $hostCfg ($remote -join " && ") }
if ("app" -in $Stage -and $PSCmdlet.ShouldProcess($Fqdn, "démarrage de l'application")) {
    Invoke-Remote $hostCfg "sudo bash /opt/cvmatcher-kit/ubuntu/deploy-app.sh"
    Add-NoteLine $Fqdn "Déploiement $($appCfg.TAG) (étapes : $($Stage -join ', '))"
}
if ($WhatIfPreference) { Write-Host "simulation terminée : rien n'a été modifié" } else { Write-Host "terminé : https://$Fqdn" }
