#Requires -Version 5.1
<#
.SYNOPSIS
    Sauvegarde immédiate d'une instance (même procédure que le timer nocturne, spec §4.3).
#>
param([Parameter(Mandatory)] [string]$Fqdn)
. "$PSScriptRoot/lib/guards.ps1"
$hostCfg = Read-EnvFile (Join-Path (Get-InstanceDir $Fqdn) "config.env")
Confirm-Explicit "Sauvegarder $Fqdn maintenant (interruption de quelques minutes) ?"
Invoke-Remote $hostCfg "sudo /usr/local/sbin/cvmatcher-backup"
Add-NoteLine $Fqdn "Sauvegarde manuelle"
