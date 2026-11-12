# Instance cv.exemple-rh.fr

> **Exemple fictif**, fourni pour illustrer le remplissage d'une fiche d'instance. La société, les noms, les dates et
> les identifiants ci-dessous sont inventés. Votre propre fiche est créée par `scripts/new-instance.ps1` dans
> `instances/<fqdn>/notes.md` ; elle reste sur votre poste et n'est pas versionnée.

Fiche d'instance (fichier local, non versionné). **Aucun secret ici** : ni clé, ni mot de passe, ni jeton.

| Élément | Valeur |
|---|---|
| Client | Exemple RH SAS |
| FQDN | cv.exemple-rh.fr |
| Hébergement | VM Scaleway PAR2, Ubuntu 24.04 LTS, 4 vCPU / 16 Go |
| Profil de dimensionnement | ESN moyenne (spec §8) |
| Mode d'authentification | office365 |
| Tenant IdP, contact, date d'enregistrement | Tenant `00000000-0000-0000-0000-000000000000`, Camille Martin (DSI), 2026-10-05 |
| Mode des clés IA | client ; workspace Anthropic `exemple-rh-cvmatcher` (identifiant seulement) |
| Stockage des fichiers | local |
| Index vectoriel | neo4j |
| Copie externe des sauvegardes | Bucket S3 `exemple-rh-backups`, région fr-par (sans identifiant) |
| Surcharge compose de l'instance (`docker-compose.override.yaml`) | aucune |
| Clés d'agents MCP / A2A | `claude-desktop-recrutement` (poste de l'équipe recrutement) ; pas d'A2A |

## Journal

| Date | Auteur | Événement |
|---|---|---|
| 2026-10-05 | cmartin | Fiche créée par new-instance.ps1 |
| 2026-10-06 | cmartin | Déploiement v37-86577d8 (étapes : kit, config, provision, app) |
| 2026-10-06 | cmartin | Licence déposée dans l'interface (domaine cv.exemple-rh.fr) |
| 2026-10-08 | cmartin | Recette validée (voir procès-verbal) |
| 2026-11-03 | cmartin | Mise à jour : tag v46-a3a7124 (sauvegarde 20261103T060000Z) |

## Procès-verbal de recette (spec §4.1, étape 11)

- [x] 3 CV (dont 1 PDF scanné et 1 PDF mixte) importés, validés, évalués
- [x] 1 fiche de poste scannée extraite et activée
- [x] 1 scoring avec décision humaine, rapport Word généré
- [x] 1 CV Word généré
- [x] Chaque appel IA visible au journal des coûts ; budget mensuel saisi
- [x] OIDC : compte autorisé accepté, compte hors domaine refusé
- [x] Sauvegarde nocturne exécutée, copie externe présente
- [ ] Restauration testée sur la recette (durée mesurée, RTO 4 h)
