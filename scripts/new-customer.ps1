#Requires -Version 5.1
<#
.SYNOPSIS
    Émet la licence d'un client et prépare son paquet de livraison dans licensing/deliveries/<client>/ (hors git).
    La clé privée est lue dans le coffre (chemin hors dépôt, $env:CVM_LICENCE_KEY) ; elle n'est jamais copiée.
.EXAMPLE
    $env:CVM_LICENCE_KEY = "X:\coffre\cvmatcher-licence-signing.pem"
    ./scripts/new-customer.ps1 client -Customer "Client SA" -Domain cvmatcher-client.acceliance.fr -Expires 2027-12-31 `
        -Seats administrator=2,steward=1,recruiter=10,business_manager=5,visitor=-1 -Features mcp,a2a
#>
param(
    [Parameter(Mandatory)] [string]$Slug,
    [Parameter(Mandatory)] [string]$Customer,
    [Parameter(Mandatory)] [string]$Domain,
    [Parameter(Mandatory)] [string]$Expires,
    [Parameter(Mandatory)] [string]$Seats,
    [int]$CvQuota = -1,
    [string]$Features = ""
)
. "$PSScriptRoot/lib/guards.ps1"
if ($Slug -notmatch '^[a-z0-9-]+$') { Fail "slug invalide" }
if (-not $env:CVM_LICENCE_KEY) { Fail "CVM_LICENCE_KEY absent : chemin de la clé privée dans le coffre" }
$out = Join-Path $script:RepoRoot "licensing/deliveries/$Slug"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$tool = Join-Path $script:RepoRoot "licensing/cvmatcher-licence.py"
$pyArgs = @($tool, "sign", "--key", $env:CVM_LICENCE_KEY, "--customer", $Customer, "--domain", $Domain, "--expires", $Expires, "--seats", $Seats, "--out", (Join-Path $out "instance.lic"))
if ($CvQuota -ge 0) { $pyArgs += @("--cv-quota", "$CvQuota") }
if ($Features) { $pyArgs += @("--features", $Features) }
python @pyArgs
if ($LASTEXITCODE -ne 0) { Fail "émission de la licence" }
Copy-Item (Join-Path $script:RepoRoot "kit/compose/docker-compose.yaml") $out
Copy-Item (Join-Path $script:RepoRoot "kit/compose/.env.example") $out
Assert-NoInternalVars @($out)
Write-Host "paquet de livraison : $out (hors git)"
