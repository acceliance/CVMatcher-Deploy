#Requires -Version 5.1
<#
.SYNOPSIS
    Décommissionnement (spec §4.4) : sauvegarde finale (export remis au client), arrêt de la stack, effacement
    des volumes, puis rappel des révocations (certificat) et mention de clôture dans notes.md.
#>
param([Parameter(Mandatory)] [string]$Fqdn)
. "$PSScriptRoot/lib/guards.ps1"
$hostCfg = Read-EnvFile (Join-Path (Get-InstanceDir $Fqdn) "config.env")
Confirm-Explicit "DÉCOMMISSIONNER $Fqdn : les données de l'instance seront effacées après la sauvegarde finale ?"
Invoke-Remote $hostCfg "sudo /usr/local/sbin/cvmatcher-backup"
Invoke-Remote $hostCfg "cd /opt/cvmatcher && sudo docker compose down --volumes --remove-orphans"
Invoke-Remote $hostCfg "sudo certbot delete --non-interactive --cert-name $Fqdn || true"
Add-NoteLine $Fqdn "Décommissionnement : stack arrêtée, volumes effacés ; sauvegardes locales à purger après remise de l'export"
Write-Host "À faire : retirer l'instance de instances/inventory.yaml"
