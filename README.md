# CVMatcher-Deploy

Kits, scripts et fiches d'instance pour déployer CVMatcher, une instance par société de recrutement. Aucun code
applicatif ici : les images viennent de Harbor (`harbor.acceliance.fr/cvmatcher/{app,web,docproc}`), construites
par `build-for-harbor.ps1` dans le dépôt `cvmatcher`. Spécification : `Specifications/deployment-specification-cvmatcher.md`.

| Dossier | Contenu |
|---|---|
| `kit/compose/` | Compose de production (pull uniquement) et `.env.example` ; profils `federated`, `vectors-qdrant`, `files-seaweedfs`, `local-llm` |
| `kit/ubuntu/` | Provisioning de la VM (`provision.sh` enchaîne 00 à 09), démarrage (`deploy-app.sh`), sauvegarde et restauration |
| `instances/` | `_template/`, une fiche par instance (`notes.md` seul versionné), `inventory.yaml` de la flotte |
| `licensing/` | Outil d'émission des licences Ed25519 ; la clé privée reste dans le coffre |
| `scripts/` | `new-customer`, `new-instance`, `deploy`, `upgrade`, `upgrade-fleet`, `backup-now`, `restore`, `decommission`, `check-repo` |
| `templates/` | Thème d'exemple, modèle Word nu, registre de traitement RGPD |

## Créer une instance

```powershell
./scripts/new-customer.ps1 client -Customer "Client SA" -Domain cvmatcher-client.acceliance.fr -Expires 2027-12-31 -Seats administrator=2,recruiter=10,visitor=-1
./scripts/new-instance.ps1 cvmatcher-client.acceliance.fr -Customer "Client SA" -AdminIp 203.0.113.10 -AuthMode standalone -Tag v412-1a2b3c4
# DNS du FQDN vers la VM, puis :
$env:HARBOR_PULL_SECRET = "<robot deploy-pull, depuis le coffre>"
./scripts/deploy.ps1 cvmatcher-client.acceliance.fr -Stage kit,config,provision,app -Licence licensing/deliveries/client/instance.lic
```

Puis, dans l'application : premier administrateur, licence, IA (connexions, slots, budget), thème et modèles Word,
référentiel, utilisateurs, recette (spec §4.1).

## Règles

- Scripts PowerShell 5.1 ou 7 ; ils affichent un résumé et demandent `OUI` avant toute action (`-WhatIf` accepté).
  `CVM_ASSUME_YES=1` pour l'automatisation.
- Fichiers du kit en LF ; un fichier CRLF est refusé au déploiement.
- Aucun secret dans git : `pre-commit install` active gitleaks et `scripts/check-repo.ps1`.
- `JSON_VIEW_ENABLED` est une variable interne (spec §3.1.1) : jamais dans les gabarits livrés, seulement par
  `deploy.ps1 <fqdn> -EnableJsonView`.
