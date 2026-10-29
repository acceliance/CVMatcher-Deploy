#Requires -Version 5.1
<#
.SYNOPSIS
    Crée la fiche d'une instance (spec §4.1 étape 2) : instances/<fqdn>/ depuis _template, secrets aléatoires,
    variables OIDC et agents dérivées du FQDN. Les config*.env ne sont jamais versionnés.
.EXAMPLE
    ./scripts/new-instance.ps1 cvmatcher-client.acceliance.fr -Customer "Client SA" -AdminIp 203.0.113.10 -AuthMode office365 -OidcTenant <id> -AllowedDomains client.fr
#>
param(
    [Parameter(Mandatory)] [string]$Fqdn,
    [Parameter(Mandatory)] [string]$Customer,
    [Parameter(Mandatory)] [string]$AdminIp,
    [string]$CustomerIps = "",
    [ValidateSet("standalone", "office365", "google")] [string]$AuthMode = "standalone",
    [string]$OidcTenant = "",
    [string]$AllowedDomains = "",
    [string]$Tag = "",
    [ValidateSet("local", "s3")] [string]$FileStore = "local",
    [ValidateSet("hosting", "seaweedfs")] [string]$S3Target = "hosting"
)
. "$PSScriptRoot/lib/guards.ps1"

$dir = Join-Path $script:RepoRoot "instances/$Fqdn"
if (Test-Path $dir) { Fail "l'instance existe déjà : $dir" }
if ($AuthMode -eq "office365" -and -not $OidcTenant) { Fail "-OidcTenant requis en office365" }
if ($AuthMode -ne "standalone" -and -not $AllowedDomains) { Fail "-AllowedDomains requis en OIDC" }
New-Item -ItemType Directory -Path $dir | Out-Null
$tpl = Join-Path $script:RepoRoot "instances/_template"
$slug = ($Fqdn -split '\.')[0]
$profiles = @()
if ($AuthMode -ne "standalone") { $profiles += "federated" }
$s3 = @{ endpoint = ""; bucket = ""; access = ""; secret = "" }
if ($FileStore -eq "s3") {
    if ($S3Target -eq "seaweedfs") {
        $profiles += "files-seaweedfs"
        $s3 = @{ endpoint = "http://seaweedfs:8333"; bucket = "cvmatcher"; access = "cvmatcher"; secret = (New-Secret 24) }
        $seaweed = @{ identities = @(@{ name = "cvmatcher"; credentials = @(@{ accessKey = $s3.access; secretKey = $s3.secret }); actions = @("Admin", "Read", "Write", "List", "Tagging") }) }
        [IO.File]::WriteAllText((Join-Path $dir "seaweedfs-s3.json"), ($seaweed | ConvertTo-Json -Depth 6) + "`n")
    } else {
        $s3.bucket = "cvmatcher-$slug"
        Warn "FILE_STORE=s3 (hébergeur) : renseigner S3_ENDPOINT, S3_ACCESS_KEY, S3_SECRET_KEY dans config.app.env"
    }
}
$values = @{
    "__FQDN__" = $Fqdn; "__ADMIN_IP__" = $AdminIp; "__CUSTOMER_IPS__" = $CustomerIps; "__TAG__" = $Tag; "__SLUG__" = $slug
    "__PROFILES__" = ($profiles -join ","); "__AUTH_MODE__" = $AuthMode
    "__OAUTH2_PROVIDER__" = $(if ($AuthMode -eq "google") { "google" } else { "oidc" })
    "__OAUTH2_ISSUER__" = $(if ($AuthMode -eq "office365") { "https://login.microsoftonline.com/$OidcTenant/v2.0" } else { "" })
    "__ALLOWED_DOMAINS__" = $AllowedDomains
    "__SECRET_NEO4J__" = (New-Secret 24); "__SECRET_SESSION__" = (New-Secret 48)
    "__SECRET_FERNET__" = (New-Secret 32 -UrlSafe); "__SECRET_OAUTH2_COOKIE__" = (New-Secret 32 -UrlSafe)
    "__FILE_STORE__" = $FileStore; "__S3_ENDPOINT__" = $s3.endpoint; "__S3_BUCKET__" = $s3.bucket
    "__S3_ACCESS_KEY__" = $s3.access; "__S3_SECRET_KEY__" = $s3.secret
    "__CUSTOMER__" = $Customer; "__DATE__" = (Get-Date -Format "yyyy-MM-dd"); "__AUTHOR__" = $env:USERNAME
}
foreach ($pair in @(@("config.env.example", "config.env"), @("config.app.env.example", "config.app.env"), @("notes.md", "notes.md"))) {
    $text = [IO.File]::ReadAllText((Join-Path $tpl $pair[0])).Replace("`r", "")
    foreach ($k in $values.Keys) { $text = $text.Replace($k, [string]$values[$k]) }
    [IO.File]::WriteAllText((Join-Path $dir $pair[1]), $text)
}
New-Item -ItemType Directory -Path (Join-Path $dir "branding") | Out-Null
Write-Host "instance créée : $dir"
Write-Host "secrets générés dans config.app.env (non versionné) : à verser au coffre de l'instance"
if ($AuthMode -ne "standalone") { Write-Host "OIDC : déclarer https://$Fqdn/oauth2/callback dans l'IdP, puis renseigner OAUTH2_CLIENT_ID et OAUTH2_CLIENT_SECRET" }
