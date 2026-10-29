#Requires -Version 5.1
<#
.SYNOPSIS
    Mise à jour de la flotte par anneaux (instances/inventory.yaml) : anneau 0 (recette) d'abord, puis 1, puis 2.
    Un échec arrête la vague. Chaque instance passe par upgrade.ps1 (sauvegarde, santé, notes.md).
.EXAMPLE
    ./scripts/upgrade-fleet.ps1 -Tag v412-1a2b3c4 -MaxRing 1
#>
param(
    [Parameter(Mandatory)] [string]$Tag,
    [int]$MaxRing = 2
)
. "$PSScriptRoot/lib/guards.ps1"
if (-not (Get-Module -ListAvailable powershell-yaml)) { Fail "module powershell-yaml requis (Install-Module powershell-yaml)" }
Import-Module powershell-yaml
$inventoryPath = Join-Path $script:RepoRoot "instances/inventory.yaml"
$inventory = Get-Content $inventoryPath -Raw | ConvertFrom-Yaml
foreach ($ring in 0..$MaxRing) {
    $wave = @($inventory.instances | Where-Object { $_.anneau -eq $ring })
    if (-not $wave) { continue }
    Write-Host "anneau $ring : $($wave.fqdn -join ', ')"
    foreach ($inst in $wave) {
        & "$PSScriptRoot/upgrade.ps1" $inst.fqdn -Tag $Tag
        $inst.tag = $Tag
    }
    [IO.File]::WriteAllText($inventoryPath, ($inventory | ConvertTo-Yaml))
    if ($ring -lt $MaxRing) { Confirm-Explicit "Anneau $ring à jour. Passer à l'anneau $($ring + 1) ?" }
}
