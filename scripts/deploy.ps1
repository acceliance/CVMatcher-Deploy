#Requires -Version 5.1
<#
.SYNOPSIS
    Déploie une instance (spec §4.1 étape 4) : -Stage kit,config,provision,app (une ou plusieurs étapes).
    -EnableJsonView / -DisableJsonView : variable interne Acceliance (§3.1.1), tracée dans notes.md.
    Le mot de passe du robot Harbor deploy-pull est lu dans $env:HARBOR_PULL_SECRET (coffre), jamais affiché.
.EXAMPLE
    ./scripts/deploy.ps1 cvmatcher-client.acceliance.fr -Stage kit,config,provision,app -Licence licensing/deliveries/client/instance.lic
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$Fqdn,
    [ValidateSet("kit", "config", "provision", "app")] [string[]]$Stage = @("kit", "config", "provision", "app"),
    [string]$Licence = "",
    [switch]$EnableJsonView,
    [switch]$DisableJsonView,
    [switch]$Recette
)
. "$PSScriptRoot/lib/guards.ps1"

$dir = Get-InstanceDir $Fqdn
$hostCfgPath = Join-Path $dir "config.env"
$appCfgPath = Join-Path $dir "config.app.env"
if ($EnableJsonView -or $DisableJsonView) {
    $text = [IO.File]::ReadAllText($appCfgPath) -replace "(?m)^JSON_VIEW_ENABLED=.*\n?", ""
    if ($EnableJsonView) { $text = $text.TrimEnd("`n") + "`nJSON_VIEW_ENABLED=true`n" }
    [IO.File]::WriteAllText($appCfgPath, $text)
    Add-NoteLine $Fqdn ("Vue JSON " + $(if ($EnableJsonView) { "activée" } else { "désactivée" }) + " (variable interne §3.1.1)")
}
$hostCfg = Read-EnvFile $hostCfgPath
$appCfg = Read-EnvFile $appCfgPath
$production = -not $Recette -and $appCfg.ENVIRONMENT -ne "recette"
Assert-LfOnly (Join-Path $script:RepoRoot "kit")
Assert-Instance $Fqdn $hostCfg $appCfg -Production:$production
Assert-LicenceDomain $Fqdn $Licence
Show-Summary $Fqdn $hostCfg $appCfg $Stage
if (-not $WhatIfPreference) { Confirm-Explicit "Déployer $Fqdn ?" }
$target = "$($hostCfg.SSH_USER)@$($hostCfg.SSH_HOST)"

if ("kit" -in $Stage -and $PSCmdlet.ShouldProcess($Fqdn, "copie du kit")) {
    Invoke-Remote $hostCfg "sudo install -d -m 0750 -o `$USER /opt/cvmatcher-kit"
    scp -q -r (Join-Path $script:RepoRoot "kit/compose") (Join-Path $script:RepoRoot "kit/ubuntu") "${target}:/opt/cvmatcher-kit/"
    if ($LASTEXITCODE -ne 0) { Fail "scp du kit" }
}
if ("config" -in $Stage -and $PSCmdlet.ShouldProcess($Fqdn, "copie de la configuration")) {
    scp -q $hostCfgPath "${target}:/opt/cvmatcher-kit/config.env"
    scp -q $appCfgPath "${target}:/opt/cvmatcher-kit/app.env"
    $seaweed = Join-Path $dir "seaweedfs-s3.json"
    if (Test-Path $seaweed) { scp -q $seaweed "${target}:/opt/cvmatcher-kit/seaweedfs-s3.json" }
    Invoke-Remote $hostCfg "chmod 0600 /opt/cvmatcher-kit/config.env /opt/cvmatcher-kit/app.env"
}
if ("provision" -in $Stage -and $PSCmdlet.ShouldProcess($Fqdn, "provisioning")) {
    Invoke-Remote $hostCfg "sudo bash /opt/cvmatcher-kit/ubuntu/provision.sh"
} elseif ("config" -in $Stage -and $PSCmdlet.ShouldProcess($Fqdn, "installation de la configuration")) {
    Invoke-Remote $hostCfg "sudo bash /opt/cvmatcher-kit/ubuntu/08-stage-app.sh"
}
if ("app" -in $Stage -and $PSCmdlet.ShouldProcess($Fqdn, "démarrage de l'application")) {
    if (-not $env:HARBOR_PULL_SECRET) { Fail "HARBOR_PULL_SECRET absent de l'environnement (robot deploy-pull, coffre)" }
    Invoke-Remote $hostCfg "sudo bash /opt/cvmatcher-kit/ubuntu/deploy-app.sh" $env:HARBOR_PULL_SECRET
    Add-NoteLine $Fqdn "Déploiement $($appCfg.TAG) (étapes : $($Stage -join ', '))"
}
Write-Host "terminé : https://$Fqdn"
