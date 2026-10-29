#Requires -Version 5.1
<#
.SYNOPSIS
    Contrôles du dépôt (hook pre-commit et CI, spec §5 et §7) : aucune variable interne dans les gabarits livrés,
    fins de ligne LF dans le kit, aucun fichier sensible suivi par git.
#>
. "$PSScriptRoot/lib/guards.ps1"
Assert-NoInternalVars @(
    (Join-Path $script:RepoRoot "kit/compose/.env.example"),
    (Join-Path $script:RepoRoot "instances/_template/config.app.env.example"),
    (Join-Path $script:RepoRoot "licensing/deliveries")
)
Assert-LfOnly (Join-Path $script:RepoRoot "kit")
$tracked = git -C $script:RepoRoot ls-files
$forbidden = $tracked | Where-Object { $_ -match '(\.env$|\.lic$|\.pem$|\.key$|secret|/deliveries/|/backups/|seaweedfs-s3\.json$)' -and $_ -notmatch '\.example$' }
if ($forbidden) { Fail "fichiers sensibles suivis par git : $($forbidden -join ', ')" }
Write-Host "dépôt conforme"
