<#
.SYNOPSIS
    Garde-fous communs des scripts de déploiement (spec de déploiement §5). Aucun secret n'est affiché.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:InternalVars = @("JSON_VIEW_ENABLED")
$script:SecretPattern = '(?i)(PASSWORD|SECRET|KEY|TOKEN)$'

function Fail([string]$Message) { throw "REFUS : $Message" }
function Warn([string]$Message) { Write-Warning $Message }

function Get-InstanceDir([string]$Fqdn) {
    if ($Fqdn -notmatch '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$') { Fail "FQDN invalide : $Fqdn" }
    $dir = Join-Path $script:RepoRoot "instances/$Fqdn"
    if (-not (Test-Path $dir)) { Fail "instance inconnue : $dir (scripts/new-instance.ps1)" }
    return $dir
}

function Read-EnvFile([string]$Path) {
    if (-not (Test-Path $Path)) { Fail "fichier absent : $Path" }
    $raw = [IO.File]::ReadAllText($Path)
    if ($raw.Contains("`r")) { Fail "$Path est en fins de ligne CRLF" }
    $vars = [ordered]@{}
    foreach ($line in $raw -split "`n") {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $k, $v = $line -split '=', 2
        $vars[$k.Trim()] = $v.Trim()
    }
    return $vars
}

function Assert-LfOnly([string]$Dir) {
    Get-ChildItem -Path $Dir -Recurse -File -Include *.sh, *.env, *.yaml, *.yml, *.json |
        Where-Object { [IO.File]::ReadAllText($_.FullName).Contains("`r") } |
        ForEach-Object { Fail "fins de ligne CRLF : $($_.FullName)" }
}

function Assert-Instance([string]$Fqdn, $HostCfg, $AppCfg, [switch]$Production) {
    if ($HostCfg.DOMAIN -ne $Fqdn) { Fail "DOMAIN de config.env ($($HostCfg.DOMAIN)) différent du dossier ($Fqdn)" }
    if ($AppCfg.INSTANCE_FQDN -ne $Fqdn) { Fail "INSTANCE_FQDN différent du dossier" }
    if ($AppCfg.PUBLIC_URL -ne "https://$Fqdn") { Fail "PUBLIC_URL doit valoir https://$Fqdn (domaine de la licence)" }
    if ($Production -and ($AppCfg.TAG -eq "latest" -or -not $AppCfg.TAG)) { Fail "tag « latest » ou vide refusé en production" }
    foreach ($k in "NEO4J_PASSWORD", "SESSION_SECRET", "DATA_ENCRYPTION_KEY") {
        if (-not $AppCfg[$k] -or $AppCfg[$k] -like "__*") { Fail "$k manquant" }
    }
    $profiles = @(("$($AppCfg.COMPOSE_PROFILES)") -split ',' | Where-Object { $_ })

    # OIDC
    if ($AppCfg.AUTH_MODE -in "office365", "google") {
        foreach ($k in "OAUTH2_CLIENT_ID", "OAUTH2_CLIENT_SECRET", "OAUTH2_COOKIE_SECRET", "OAUTH2_ALLOWED_DOMAINS") {
            if (-not $AppCfg[$k]) { Fail "$k requis en $($AppCfg.AUTH_MODE)" }
        }
        if ($AppCfg.AUTH_MODE -eq "office365" -and -not $AppCfg.OAUTH2_OIDC_ISSUER_URL) { Fail "OAUTH2_OIDC_ISSUER_URL requis en office365" }
        if ($AppCfg.OAUTH2_REDIRECT_URL -ne "https://$Fqdn/oauth2/callback") { Fail "OAUTH2_REDIRECT_URL doit valoir https://$Fqdn/oauth2/callback" }
        if ($AppCfg.OAUTH2_ALLOWED_DOMAINS -eq "*") { Fail "OAUTH2_ALLOWED_DOMAINS=* refusé" }
        if ("federated" -notin $profiles) { Fail "le profil federated est requis en $($AppCfg.AUTH_MODE)" }
    }
    # stockage S3 et SeaweedFS
    if ($AppCfg.FILE_STORE -eq "s3" -and -not $AppCfg.S3_ENDPOINT) { Fail "FILE_STORE=s3 sans S3_ENDPOINT" }
    if ("files-seaweedfs" -in $profiles) {
        $secret = Join-Path (Get-InstanceDir $Fqdn) "seaweedfs-s3.json"
        if (-not (Test-Path $secret)) { Fail "profil files-seaweedfs sans secret seaweedfs-s3.json" }
        if (-not $HostCfg.BACKUP_REMOTE) { Warn "files-seaweedfs sans copie externe des sauvegardes : aucune durabilité ajoutée" }
    }
    if ($AppCfg.VECTOR_BACKEND -eq "qdrant" -and (-not $AppCfg.QDRANT_API_KEY -or "vectors-qdrant" -notin $profiles)) {
        Fail "VECTOR_BACKEND=qdrant exige le profil vectors-qdrant et QDRANT_API_KEY"
    }
    # agents
    if ($AppCfg.MCP_ENABLED -eq "true" -and $AppCfg.MCP_ALLOWED_HOSTS -notmatch [regex]::Escape($Fqdn)) {
        Fail "MCP_ENABLED=true sans le FQDN dans MCP_ALLOWED_HOSTS (tout client recevrait 421)"
    }
    if ($AppCfg.AI_EGRESS_ALLOWED -eq "false" -and ($AppCfg.MCP_ENABLED -eq "true" -or $AppCfg.A2A_ENABLED -eq "true")) {
        Confirm-Explicit "AI_EGRESS_ALLOWED=false avec des agents actifs : des données peuvent sortir par les agents (EF-173)"
    }
    # thème
    foreach ($h in (("$($AppCfg.THEME_ASSET_HOSTS)") -split '[,\s]+' | Where-Object { $_ })) {
        if ($h -eq "*") {
            if ($Production) { Confirm-Explicit "THEME_ASSET_HOSTS=* : le thème peut faire charger des ressources depuis n'importe quel hôte" }
        } elseif ($h -notmatch '^(\*\.)?[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:[0-9]{1,5})?$') {
            Fail "entrée THEME_ASSET_HOSTS invalide : $h"
        }
    }
    # sauvegardes
    if ($Production -and -not $HostCfg.BACKUP_REMOTE) { Warn "aucune copie externe des sauvegardes (BACKUP_REMOTE) : exigée en production (K-12)" }
}

function Assert-LicenceDomain([string]$Fqdn, [string]$LicencePath) {
    if (-not $LicencePath -or -not (Test-Path $LicencePath)) { Warn "licence non fournie : domaine non vérifié"; return }
    $lic = Get-Content $LicencePath -Raw | ConvertFrom-Json
    if ($lic.licence.domain -ne $Fqdn) { Fail "licence émise pour $($lic.licence.domain), instance $Fqdn" }
}

function Assert-NoInternalVars([string[]]$Paths) {
    foreach ($p in $Paths) {
        if (-not (Test-Path $p)) { continue }
        Get-ChildItem -Path $p -Recurse -File | ForEach-Object {
            $text = [IO.File]::ReadAllText($_.FullName)
            foreach ($v in $script:InternalVars) {
                if ($text -match "(?m)^\s*$v\s*=") { Fail "variable interne $v dans $($_.FullName) (§3.1.1)" }
            }
        }
    }
}

function Confirm-Explicit([string]$Message) {
    Write-Warning $Message
    if ($env:CVM_ASSUME_YES -eq "1") { return }
    $answer = Read-Host "Saisir OUI pour confirmer"
    if ($answer -ne "OUI") { Fail "annulé" }
}

function Show-Summary([string]$Fqdn, $HostCfg, $AppCfg, [string[]]$Stages) {
    $internal = @($script:InternalVars | Where-Object { $AppCfg[$_] -eq "true" })
    Write-Host ""
    Write-Host "Instance        : $Fqdn"
    Write-Host "Hôte SSH        : $($HostCfg.SSH_USER)@$($HostCfg.SSH_HOST)"
    Write-Host "Tag             : $($AppCfg.TAG)"
    Write-Host "Authentification: $($AppCfg.AUTH_MODE)"
    Write-Host "Profils         : $($AppCfg.COMPOSE_PROFILES)"
    Write-Host "Étapes          : $($Stages -join ', ')"
    Write-Host ("Fonctions internes actives : " + ($(if ($internal) { $internal -join ', ' } else { 'aucune' })))
    Write-Host ""
}

function New-Secret([int]$Bytes = 32, [switch]$UrlSafe) {
    $buf = New-Object byte[] $Bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($buf)
    $rng.Dispose()
    $b64 = [Convert]::ToBase64String($buf)
    if ($UrlSafe) { return $b64.Replace('+', '-').Replace('/', '_') }
    return $b64.TrimEnd('=').Replace('+', 'A').Replace('/', 'B')
}

function Add-NoteLine([string]$Fqdn, [string]$Event) {
    $notes = Join-Path (Get-InstanceDir $Fqdn) "notes.md"
    $line = "| $(Get-Date -Format 'yyyy-MM-dd') | $env:USERNAME | $Event |"
    $text = [IO.File]::ReadAllText($notes).TrimEnd("`n")
    $marker = "## Procès-verbal de recette"
    if ($text.Contains($marker)) {
        $idx = $text.IndexOf($marker)
        $text = $text.Substring(0, $idx).TrimEnd("`n") + "`n$line`n`n" + $text.Substring($idx)
    } else { $text += "`n$line" }
    [IO.File]::WriteAllText($notes, $text + "`n")
}

function Invoke-Remote($HostCfg, [string]$Command, [string]$StdIn) {
    $target = "$($HostCfg.SSH_USER)@$($HostCfg.SSH_HOST)"
    if ($StdIn) { $StdIn | ssh -o BatchMode=yes $target $Command } else { ssh -o BatchMode=yes $target $Command }
    if ($LASTEXITCODE -ne 0) { Fail "commande distante en échec ($LASTEXITCODE) : $Command" }
}
