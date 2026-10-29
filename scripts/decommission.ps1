#Requires -Version 5.1
<#
.SYNOPSIS
    Décommissionnement (spec §4.4) : sauvegarde finale (export remis au client), arrêt de la stack, effacement
    des volumes, puis rappel des révocations (robot Harbor, certificat) et mention de clôture dans notes.md.
#>
param([Parameter(Mandatory)] [string]$Fqdn)
. "$PSScriptRoot/lib/guards.ps1"
$hostCfg = Read-EnvFile (Join-Path (Get-InstanceDir $Fqdn) "config.env")
Confirm-Explicit "DÉCOMMISSIONNER $Fqdn : les données de l'instance seront effacées après la sauvegarde finale ?"
Invoke-Remote $hostCfg "sudo /usr/local/sbin/cvmatcher-backup"
Invoke-Remote $hostCfg "cd /opt/cvmatcher && sudo docker compose down --volumes --remove-orphans"
Invoke-Remote $hostCfg "sudo certbot delete --non-interactive --cert-name $Fqdn || true"
Add-NoteLine $Fqdn "Décommissionnement : stack arrêtée, volumes effacés ; robot Harbor à révoquer, sauvegardes locales à purger après remise de l'export"
Write-Host "À faire : révoquer le robot Harbor deploy-pull de l'instance, retirer l'instance de instances/inventory.yaml"
