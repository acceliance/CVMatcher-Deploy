#Requires -Version 5.1
<#
.SYNOPSIS
    Contrôles du dépôt (hook pre-commit et CI, spec §5 et §7) : fins de ligne LF dans le kit, aucun outillage interne
    Acceliance, aucune surcharge compose d'instance ni aucun fichier sensible suivi par git.
#>
. "$PSScriptRoot/lib/guards.ps1"
Assert-LfOnly (Join-Path $script:RepoRoot "kit")
# dépôt destiné aux clients : aucun outillage interne Acceliance (émission de licences, flotte)
$internal = @("licensing/cvmatcher-licence.py", "scripts/new-customer.ps1", "scripts/upgrade-fleet.ps1", "instances/inventory.yaml")
foreach ($f in $internal) { if (Test-Path (Join-Path $script:RepoRoot $f)) { Fail "outillage interne dans le kit client : $f" } }
$tracked = git -C $script:RepoRoot ls-files
$forbidden = $tracked | Where-Object { $_ -match '(\.env$|\.lic$|\.pem$|\.key$|secret|/deliveries/|/backups/|seaweedfs-s3\.json$|docker-compose\.override\.yaml$)' -and $_ -notmatch '\.example$' }
if ($forbidden) { Fail "fichiers sensibles suivis par git : $($forbidden -join ', ')" }
Write-Host "dépôt conforme"
