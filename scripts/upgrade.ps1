#Requires -Version 5.1
<#
.SYNOPSIS
    Mise à jour d'une instance (spec §4.2) : sauvegarde préalable, nouveau tag, pull, up -d (les migrations
    Cypher sont jouées par l'API au démarrage, sous verrou), santé, ligne dans notes.md.
    -RotateDataKey : rotation de DATA_ENCRYPTION_KEY puis tâche secrets.reencrypt (§4.6).
    -VectorBackend qdrant|neo4j : bascule de l'index vectoriel (§4.5).
    Lancé sans aucun paramètre, le script affiche l'aide et la liste des instances connues.
.PARAMETER Fqdn
    Nom de domaine de l'instance (dossier instances/<fqdn>). Obligatoire dès qu'une action est demandée.
.PARAMETER Tag
    Nouveau tag des images (ex. latest, 1.4.2) écrit dans TAG= de config.app.env.
.PARAMETER RotateDataKey
    Génère une nouvelle DATA_ENCRYPTION_KEY et conserve l'ancienne dans DATA_ENCRYPTION_KEY_PREVIOUS.
.PARAMETER VectorBackend
    Bascule l'index vectoriel : neo4j ou qdrant.
.PARAMETER SkipBackup
    N'exécute pas la sauvegarde préalable (cvmatcher-backup) sur l'hôte.
.PARAMETER Recette
    Instance de recette : assouplit les garde-fous de production.
.EXAMPLE
    ./scripts/upgrade.ps1 cvmatcher-client.acceliance.fr -Tag latest   # retélécharge les dernières images
.EXAMPLE
    ./scripts/upgrade.ps1 cvmatcher-client.acceliance.fr -RotateDataKey
.EXAMPLE
    ./scripts/upgrade.ps1 cvmatcher-client.acceliance.fr -VectorBackend qdrant -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)] [string]$Fqdn,
    [string]$Tag = "",
    [switch]$RotateDataKey,
    [ValidateSet("", "neo4j", "qdrant")] [string]$VectorBackend = "",
    [switch]$SkipBackup,
    [switch]$Recette
)
. "$PSScriptRoot/lib/guards.ps1"

# Aucun paramètre : affichage de l'aide (options, exemples, instances disponibles) puis sortie sans action.
if ($PSBoundParameters.Count -eq 0) {
    Write-Host @"
Usage : ./scripts/upgrade.ps1 <fqdn> [options]

Mise à jour d'une instance CVMatcher : sauvegarde préalable, application des changements dans
config.app.env, redéploiement (config + app), contrôle de santé et trace dans notes.md.

Paramètres :
  <fqdn>                       Nom de domaine de l'instance (obligatoire)

Actions (au moins une) :
  -Tag <tag>                   Nouveau tag des images (ex. latest, 1.4.2)
  -RotateDataKey               Rotation de DATA_ENCRYPTION_KEY, puis rechiffrement des secrets (§4.6)
  -VectorBackend neo4j|qdrant  Bascule de l'index vectoriel (§4.5)

Options :
  -SkipBackup                  Ne pas lancer la sauvegarde préalable sur l'hôte
  -Recette                     Instance de recette (garde-fous de production assouplis)
  -WhatIf                      Simulation : n'écrit rien et ne déploie rien
  -Confirm                     Demande de confirmation PowerShell supplémentaire
  -Verbose                     Sortie détaillée

Exemples :
  ./scripts/upgrade.ps1 cvmatcher-client.acceliance.fr -Tag latest
  ./scripts/upgrade.ps1 cvmatcher-client.acceliance.fr -RotateDataKey
  ./scripts/upgrade.ps1 cvmatcher-client.acceliance.fr -VectorBackend qdrant -WhatIf
  ./scripts/upgrade.ps1 recette.acceliance.fr -Tag 1.4.2 -Recette -SkipBackup

Aide détaillée : Get-Help ./scripts/upgrade.ps1 -Full
"@
    $instances = @(Get-ChildItem -Path $script:InstancesRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "_*" } | Select-Object -ExpandProperty Name)
    if ($instances) {
        Write-Host "Instances connues ($script:InstancesRoot) :"
        $instances | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "Aucune instance trouvée dans $script:InstancesRoot (scripts/new-instance.ps1)."
    }
    return
}
if (-not $Fqdn) { Fail "FQDN de l'instance manquant (lancer le script sans paramètre pour l'aide)" }

$dir = Get-InstanceDir $Fqdn
$appCfgPath = Join-Path $dir "config.app.env"
$hostCfg = Read-EnvFile (Join-Path $dir "config.env")
$text = [IO.File]::ReadAllText($appCfgPath)
$events = @()
if ($Tag) {
    $text = $text -replace "(?m)^TAG=.*$", "TAG=$Tag"
    $events += "tag $Tag"
}
if ($RotateDataKey) {
    $old = ([regex]::Match($text, "(?m)^DATA_ENCRYPTION_KEY=(.*)$")).Groups[1].Value
    $text = $text -replace "(?m)^DATA_ENCRYPTION_KEY_PREVIOUS=.*\n?", ""
    $text = $text -replace "(?m)^DATA_ENCRYPTION_KEY=.*$", "DATA_ENCRYPTION_KEY=$(New-Secret 32 -UrlSafe)`nDATA_ENCRYPTION_KEY_PREVIOUS=$old"
    $events += "rotation de DATA_ENCRYPTION_KEY"
}
if ($VectorBackend) {
    $text = $text -replace "(?m)^VECTOR_BACKEND=.*$", "VECTOR_BACKEND=$VectorBackend"
    if ($VectorBackend -eq "qdrant") {
        if ($text -match "(?m)^QDRANT_API_KEY=\s*$") { $text = $text -replace "(?m)^QDRANT_API_KEY=.*$", "QDRANT_API_KEY=$(New-Secret 32)" }
        if ($text -notmatch "(?m)^COMPOSE_PROFILES=.*vectors-qdrant") { $text = $text -replace "(?m)^COMPOSE_PROFILES=(.*)$", 'COMPOSE_PROFILES=$1,vectors-qdrant' -replace "COMPOSE_PROFILES=,", "COMPOSE_PROFILES=" }
    }
    $events += "index vectoriel $VectorBackend"
}
$appCfg = Read-EnvFile $appCfgPath
Assert-Instance $Fqdn $hostCfg $appCfg -Production:(-not $Recette)
if (-not $events) { Fail "rien à faire (-Tag, -RotateDataKey ou -VectorBackend ; lancer sans paramètre pour l'aide)" }
Confirm-Explicit "Mettre à jour $Fqdn : $($events -join ', ') ?"
if ($PSCmdlet.ShouldProcess($Fqdn, $events -join ', ')) {
    if (-not $SkipBackup) { Invoke-Remote $hostCfg "sudo /usr/local/sbin/cvmatcher-backup" }
    [IO.File]::WriteAllText($appCfgPath, $text)
    & "$PSScriptRoot/deploy.ps1" $Fqdn -Stage config, app -Recette:$Recette
    if ($RotateDataKey) { Write-Host "lancer Administration ▸ Maintenance ▸ Rechiffrement des secrets, puis retirer DATA_ENCRYPTION_KEY_PREVIOUS" }
    if ($VectorBackend -eq "qdrant") { Write-Host "lancer la reconstruction de l'index (vector.rebuild) et vérifier les comptages (§4.5)" }
    Add-NoteLine $Fqdn ("Mise à jour : " + ($events -join ', '))
}
