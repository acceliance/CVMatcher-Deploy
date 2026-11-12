#Requires -Version 5.1
<#
.SYNOPSIS
    Met à jour une instance CVMatcher déjà déployée à partir des images publiques Docker Hub
    (acceliance/cvmatcher-{app,web,docproc}), sans fiche d'instance locale : seul l'accès SSH est requis.

.DESCRIPTION
    1. Lit l'état de la VM (tag courant, conteneurs) et affiche un résumé.
    2. Demande OUI (CVM_ASSUME_YES=1 pour l'automatisation ; -WhatIf s'arrête après le résumé).
    3. Sauvegarde préalable (/usr/local/sbin/cvmatcher-backup), sauf -SkipBackup.
    4. Change le TAG dans /opt/cvmatcher/.env si -Tag est fourni ; sinon conserve le tag courant
       (avec « latest », retélécharge simplement les dernières images).
    5. Lance /opt/cvmatcher-kit/ubuntu/deploy-app.sh : pull, up -d, attente de santé. Les migrations Cypher
       sont jouées par l'API au démarrage.
    6. -Prune : supprime ensuite les images Docker devenues orphelines.

    Prérequis : instance installée par scripts/deploy.ps1 (dossiers /opt/cvmatcher et /opt/cvmatcher-kit),
    accès SSH par clé, utilisateur sudo sans mot de passe.

    Si la fiche d'instance existe sur ce poste, préférez scripts/upgrade.ps1 : il garde config.app.env et
    notes.md à jour. Avec -Tag, ce script ne modifie que la VM : reportez le tag dans config.app.env, sinon
    un prochain deploy.ps1 -Stage config le remettra à l'ancienne valeur.

.PARAMETER Ssh
    Cible SSH : utilisateur@hôte, ou alias défini dans ~/.ssh/config.

.PARAMETER Tag
    Version des images à déployer (ex. v37-86577d8 ou latest). Vide = tag courant de l'instance.

.PARAMETER Port
    Port SSH (22 par défaut, ou celui de ~/.ssh/config).

.PARAMETER IdentityFile
    Clé privée SSH à utiliser.

.EXAMPLE
    ./kit/update.ps1 ubuntu@cv.client.fr
    Retélécharge les images du tag courant (typiquement latest) et redémarre la stack.

.EXAMPLE
    ./kit/update.ps1 ubuntu@cv.client.fr -Tag v37-86577d8 -Prune
    Passe à la version v37-86577d8, puis nettoie les anciennes images.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, Position = 0)] [string]$Ssh,
    [string]$Tag = "",
    [int]$Port = 0,
    [string]$IdentityFile = "",
    [switch]$SkipBackup,
    [switch]$Prune
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$Message) { throw "REFUS : $Message" }

# --- contrôles des paramètres (aucune option ssh injectable par la cible ou le tag) ---
if ($Ssh -notmatch '^[A-Za-z0-9_][A-Za-z0-9._-]*(@[A-Za-z0-9_\[][A-Za-z0-9._:\[\]-]*)?$') { Fail "cible SSH invalide : $Ssh (attendu utilisateur@hôte ou alias)" }
if ($Tag -and $Tag -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$') { Fail "tag Docker invalide : $Tag" }
if ($IdentityFile -and -not (Test-Path $IdentityFile)) { Fail "clé introuvable : $IdentityFile" }
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Fail "client ssh introuvable sur ce poste" }

$sshArgs = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15")
if ($Port -gt 0) { $sshArgs += @("-p", "$Port") }
if ($IdentityFile) { $sshArgs += @("-i", $IdentityFile) }

# --- script exécuté sur la VM (transmis en base64 : pas de souci de guillemets ni de fins de ligne CRLF) ---
$remoteScript = @'
set -euo pipefail
APP_DIR=/opt/cvmatcher
KIT_DIR=/opt/cvmatcher-kit
MODE="$1"; NEW_TAG="${2:-}"; SKIP_BACKUP="${3:-0}"; PRUNE="${4:-0}"
[ -f "$APP_DIR/.env" ] || { echo "instance absente : $APP_DIR/.env (déployer d'abord avec scripts/deploy.ps1)" >&2; exit 2; }
[ -f "$KIT_DIR/ubuntu/deploy-app.sh" ] || { echo "kit absent : $KIT_DIR/ubuntu/deploy-app.sh (deploy.ps1 -Stage kit)" >&2; exit 2; }
current=$(grep -E '^TAG=' "$APP_DIR/.env" | tail -n 1 | cut -d= -f2- || true)
if [ "$MODE" = "info" ]; then
  echo "TAG=${current:-latest}"
  cd "$APP_DIR" && docker compose ps --format '  {{.Service}}  {{.Image}}  {{.Status}}' 2>/dev/null || true
  exit 0
fi
if [ "$SKIP_BACKUP" != "1" ]; then
  echo "[cvmatcher] sauvegarde préalable"
  /usr/local/sbin/cvmatcher-backup
fi
if [ -n "$NEW_TAG" ] && [ "$NEW_TAG" != "$current" ]; then
  if grep -qE '^TAG=' "$APP_DIR/.env"; then sed -i -E "s/^TAG=.*/TAG=$NEW_TAG/" "$APP_DIR/.env"
  else printf 'TAG=%s\n' "$NEW_TAG" >> "$APP_DIR/.env"; fi
  echo "[cvmatcher] TAG ${current:-latest} -> $NEW_TAG (ancienne valeur pour un retour arrière : ${current:-latest})"
fi
bash "$KIT_DIR/ubuntu/deploy-app.sh"
if [ "$PRUNE" = "1" ]; then docker image prune -f; fi
'@
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript.Replace("`r", "")))

function Invoke-Update([string[]]$ScriptArgs) {
    $quoted = ($ScriptArgs | ForEach-Object { "'$_'" }) -join " "
    $command = "echo $encoded | base64 -d | sudo bash -s -- $quoted"
    # la VM écrit en UTF-8 : sans cela, la console Windows affiche « pr├®alable » au lieu de « préalable »
    $previousEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try {
        # Out-Host : la sortie distante s'affiche sans polluer la valeur de retour de la fonction
        ssh @sshArgs $Ssh $command | Out-Host
        return $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $previousEncoding
    }
}

# --- 1. état courant ---
Write-Host "Connexion à $Ssh ..."
$info = Invoke-Update @("info")
if ($info -ne 0) { Fail "lecture de l'instance impossible ($info) : vérifier l'accès SSH par clé et sudo sans mot de passe" }

# --- 2. résumé et confirmation ---
$targetTag = $(if ($Tag) { $Tag } else { "(inchangé)" })
Write-Host ""
Write-Host "Hôte SSH          : $Ssh"
Write-Host "Nouveau tag       : $targetTag"
Write-Host ("Sauvegarde        : " + $(if ($SkipBackup) { "NON (-SkipBackup)" } else { "oui, avant la mise à jour" }))
Write-Host ("Nettoyage images  : " + $(if ($Prune) { "oui" } else { "non" }))
Write-Host ""

if (-not $PSCmdlet.ShouldProcess($Ssh, "mise à jour depuis Docker Hub (tag $targetTag)")) { return }
Write-Warning "Mettre à jour l'instance $Ssh ? Le service est interrompu pendant le redémarrage."
if ($env:CVM_ASSUME_YES -ne "1") {
    if ((Read-Host "Saisir OUI pour confirmer") -ne "OUI") { Fail "annulé" }
}

# --- 3. mise à jour ---
$code = Invoke-Update @("update", $Tag, $(if ($SkipBackup) { "1" } else { "0" }), $(if ($Prune) { "1" } else { "0" }))
if ($code -ne 0) { Fail "mise à jour en échec ($code) : consulter les journaux (docker compose logs dans /opt/cvmatcher)" }

Write-Host ""
Write-Host "Mise à jour terminée sur $Ssh." -ForegroundColor Green
if ($Tag) { Write-Host "Pensez à reporter TAG=$Tag dans config.app.env de la fiche d'instance, si elle existe." }
