# Émission des licences CVMatcher

Les licences sont des enveloppes JSON signées en Ed25519 (`cvmatcher-licence`, SFG §11.3). L'application ne
connaît que les **clés publiques** de confiance, compilées dans l'image (`TRUSTED_PUBLIC_KEYS` de
`cvmatcher/server/cvmatcher/admin/licence.py`). La **clé privée ne se trouve jamais dans un dépôt** : elle vit dans
le coffre d'Acceliance (spec de déploiement §7). L'outil refuse d'écrire ou de lire une clé située dans ce dépôt.

## Première mise en place (une fois)

```bash
pip install cryptography
python licensing/cvmatcher-licence.py keygen --out-dir <dossier hors dépôt>
```

1. Verser `cvmatcher-licence-signing.pem` au coffre, puis l'effacer du poste.
2. Ajouter le contenu de `cvmatcher-licence-public.pem` à `TRUSTED_PUBLIC_KEYS` dans le dépôt `cvmatcher`, puis
   reconstruire les images release (`build-for-harbor.ps1`). Une image sans clé publique refuse toute licence.

## Émettre une licence (par client)

```powershell
$env:CVM_LICENCE_KEY = "<chemin de la clé privée, monté depuis le coffre>"
./scripts/new-customer.ps1 client -Customer "Client SA" -Domain cvmatcher-client.acceliance.fr -Expires 2027-12-31 `
    -Seats administrator=2,steward=1,recruiter=10,business_manager=5,visitor=-1 -CvQuota 2000 -Features mcp,a2a
```

| Champ | Effet dans l'application |
|---|---|
| `domain` | Doit correspondre au FQDN de `PUBLIC_URL` ; sinon l'instance est verrouillée |
| `expires` | Après la date : lecture seule 30 jours, puis verrouillage (seule l'administration reste ouverte) |
| `seats` | Comptes actifs par rôle ; `-1` = illimité, rôle absent = aucun compte |
| `cvMonthlyQuota` | CV importés par mois (facultatif) |
| `features` | `mcp`, `mcp.write`, `a2a` : fonctions agents ouvertes (facultatif) |

Le paquet `licensing/deliveries/<client>/` (hors git) contient `instance.lic`, le compose et `.env.example`. Le
fichier `.lic` est déposé par l'administrateur du client dans Administration ▸ Licence.

## Vérifier une licence

```bash
python licensing/cvmatcher-licence.py verify --pub <clé publique.pem> licensing/deliveries/client/instance.lic
```

## Rotation de la clé de signature

Nouvelle paire dans le coffre, ajout de la nouvelle clé publique **à côté** de l'ancienne dans `TRUSTED_PUBLIC_KEYS`,
nouvelle image, réémission des licences des instances, puis retrait de l'ancienne clé publique à la version suivante.
