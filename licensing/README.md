# Licence de l'instance

La licence est un fichier `instance.lic` remis par Acceliance avec votre paquet de livraison. Il est signé par Acceliance
et lié au nom de domaine de votre instance (`PUBLIC_URL`).

Pour obtenir une licence, ou la faire réémettre (changement de domaine, ajout de comptes), écrivez à
[contact@acceliance.fr](mailto:contact@acceliance.fr) en indiquant le nom de domaine de l'instance. La licence est totalement gratuite.

## Déposer la licence

1. Connectez-vous à l'instance avec un compte `administrator`.
2. Ouvrez **Administration ▸ Licence**, choisissez le fichier `instance.lic`, puis **Déposer la licence**.
3. L'effet est immédiat ; l'écran affiche le client, le domaine et les comptes autorisés par rôle.

La licence est perpétuelle : elle n'a pas de date d'expiration.

| Situation | Effet |
|---|---|
| Aucune licence déposée | Instance utilisable, limitée à 50 CV en base ; fonctions agents (MCP, A2A) fermées |
| Licence valide | Toutes les fonctions prévues par la licence |
| Licence invalide ou d'un autre domaine | Instance verrouillée, administration seule ; écrivez à contact@acceliance.fr |
| Quota de comptes d'un rôle atteint | Création de compte refusée pour ce rôle (`LICENCE_QUOTA`) |
| Quota mensuel de CV atteint | Import refusé jusqu'au mois suivant |

Le fichier `.lic` ne contient aucun secret, mais toute modification invalide sa signature. Ne le versionnez pas : ce dépôt
l'ignore (`*.lic`).

`scripts/deploy.ps1 <fqdn> -Licence <chemin>/instance.lic` vérifie avant le déploiement que le domaine de la licence est
celui de l'instance.
