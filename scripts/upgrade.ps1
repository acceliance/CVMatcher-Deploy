#Requires -Version 5.1
<#
.SYNOPSIS
    Mise à jour d'une instance (spec §4.2) : sauvegarde préalable, nouveau tag, pull, up -d (les migrations
    Cypher sont jouées par l'API au démarrage, sous verrou), santé, ligne dans notes.md.
    -RotateDataKey : rotation de DATA_ENCRYPTION_KEY puis tâche secrets.reencrypt (§4.6).
    -VectorBackend qdrant|neo4j : bascule de l'index vectoriel (§4.5).
.EXAMPLE
    ./scripts/upgrade.ps1 cvmatcher-client.acceliance.fr -Tag v412-1a2b3c4
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$Fqdn,
    [string]$Tag = "",
    [switch]$RotateDataKey,
    [ValidateSet("", "neo4j", "qdrant")] [string]$VectorBackend = "",
    [switch]$SkipBackup
)
. "$PSScriptRoot/lib/guards.ps1"

$dir = Get-InstanceDir $Fqdn
$appCfgPath = Join-Path $dir "config.app.env"
$hostCfg = Read-EnvFile (Join-Path $dir "config.env")
$text = [IO.File]::ReadAllText($appCfgPath)
$events = @()
if ($Tag) {
    if ($Tag -eq "latest") { Fail "tag « latest » refusé" }
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
Assert-Instance $Fqdn $hostCfg $appCfg -Production:($appCfg.ENVIRONMENT -ne "recette")
if (-not $events) { Fail "rien à faire (-Tag, -RotateDataKey ou -VectorBackend)" }
Confirm-Explicit "Mettre à jour $Fqdn : $($events -join ', ') ?"
if ($PSCmdlet.ShouldProcess($Fqdn, $events -join ', ')) {
    if (-not $SkipBackup) { Invoke-Remote $hostCfg "sudo /usr/local/sbin/cvmatcher-backup" }
    [IO.File]::WriteAllText($appCfgPath, $text)
    & "$PSScriptRoot/deploy.ps1" $Fqdn -Stage config, app -Recette:($appCfg.ENVIRONMENT -eq "recette")
    if ($RotateDataKey) { Write-Host "lancer Administration ▸ Maintenance ▸ Rechiffrement des secrets, puis retirer DATA_ENCRYPTION_KEY_PREVIOUS" }
    if ($VectorBackend -eq "qdrant") { Write-Host "lancer la reconstruction de l'index (vector.rebuild) et vérifier les comptages (§4.5)" }
    Add-NoteLine $Fqdn ("Mise à jour : " + ($events -join ', '))
}
