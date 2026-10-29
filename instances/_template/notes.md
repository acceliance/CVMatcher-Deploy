# Instance __FQDN__

Fiche d'instance (seul fichier versionné du dossier). **Aucun secret ici** : ni clé, ni mot de passe, ni jeton.

| Élément | Valeur |
|---|---|
| Client | __CUSTOMER__ |
| FQDN | __FQDN__ |
| Hébergement | (VM Acceliance OVH / Scaleway, ou VM du client) |
| Profil de dimensionnement | (petit cabinet / ESN moyenne / grand compte, spec §8) |
| Mode d'authentification | __AUTH_MODE__ |
| Tenant IdP, contact, date d'enregistrement | |
| Mode des clés IA | (client ou managé) ; workspace Anthropic / projet OpenAI dédié : identifiants seulement |
| Stockage des fichiers | __FILE_STORE__ |
| Index vectoriel | neo4j |
| Copie externe des sauvegardes | (cible, sans identifiant) |
| Fonctions internes actives (§3.1.1) | aucune |
| Clés d'agents MCP / A2A | (noms et hôtes, jamais les clés) |

## Journal

| Date | Auteur | Événement |
|---|---|---|
| __DATE__ | __AUTHOR__ | Fiche créée par new-instance.ps1 |

## Procès-verbal de recette (spec §4.1, étape 11)

- [ ] 3 CV (dont 1 PDF scanné et 1 PDF mixte) importés, validés, évalués
- [ ] 1 fiche de poste scannée extraite et activée
- [ ] 1 scoring avec décision humaine, rapport Word généré
- [ ] 1 CV Word généré
- [ ] Chaque appel IA visible au journal des coûts ; budget mensuel saisi
- [ ] OIDC : compte autorisé accepté, compte hors domaine refusé
- [ ] Sauvegarde nocturne exécutée, copie externe présente
- [ ] Restauration testée sur la recette (durée mesurée, RTO 4 h)
