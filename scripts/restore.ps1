#Requires -Version 5.1
<#
.SYNOPSIS
    Restauration (runbook §4.7, étape 4) depuis un dossier de sauvegarde présent sur la VM
    (/var/backups/cvmatcher/<horodatage>, ou archive récupérée de la copie externe et déchiffrée).
    Une sauvegarde de l'état courant est faite avant. Ensuite : Administration ▸ Maintenance ▸ Vérification
    après restauration (tâche restore.verify), puis recette de l'étape 6.
#>
param(
    [Parameter(Mandatory)] [string]$Fqdn,
    [Parameter(Mandatory)] [string]$Backup
)
. "$PSScriptRoot/lib/guards.ps1"
if ($Backup -notmatch '^/var/backups/cvmatcher/[0-9]{8}T[0-9]{6}Z$') { Fail "chemin de sauvegarde attendu : /var/backups/cvmatcher/<AAAAMMJJTHHMMSSZ>" }
$hostCfg = Read-EnvFile (Join-Path (Get-InstanceDir $Fqdn) "config.env")
Confirm-Explicit "Restaurer $Fqdn depuis $Backup (l'état courant sera sauvegardé puis remplacé) ?"
$start = Get-Date
Invoke-Remote $hostCfg "sudo /usr/local/sbin/cvmatcher-restore $Backup"
$minutes = [int]((Get-Date) - $start).TotalMinutes
Add-NoteLine $Fqdn "Restauration depuis $Backup ($minutes min) ; vérification restore.verify à lancer"
