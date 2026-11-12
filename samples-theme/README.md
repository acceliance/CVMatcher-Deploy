# Exemples de thème

| Fichier | Contenu |
|---|---|
| `brand-theme.acceliance.json` | Thème visuel Acceliance (charte : bleu `#0097b6`, accents violet, vert, bleu, rouge ; Poppins et Lora). Les logos et les polices sont chargés directement depuis `www.acceliance.fr` et Google Fonts |
| [`brand/prompt-brand-theme.md`](brand/prompt-brand-theme.md) | Prompt d'exemple pour produire ce JSON à partir du site web du client, avec la valeur de `THEME_ASSET_HOSTS` |
| [`../schemas/brand-theme.schema.json`](../schemas/brand-theme.schema.json) | Schéma appliqué par l'application, référencé par `$schema` pour la validation dans l'éditeur |

## Déposer le thème Acceliance

1. Autoriser les hôtes des logos et des polices dans la configuration de l'instance, puis recréer les conteneurs
   (`deploy.ps1 <fqdn> -Stage config,app`) :

   ```
   THEME_ASSET_HOSTS=www.acceliance.fr,fonts.googleapis.com,fonts.gstatic.com
   ```

   Sans cette ligne, le dépôt est refusé sur `brand.logo.*`, `typography.heading.url` et `typography.body.url`. L'edge
   construit la politique de sécurité de contenu (CSP) du navigateur à partir de la même variable.

2. Dans l'application : **Administration ▸ Thème**, téléverser `brand-theme.acceliance.json`, vérifier le contrôle de
   contraste, puis publier.

Les logos étant chargés depuis le site, un changement de logo sur `www.acceliance.fr` est repris sans republier le
thème. Le worker ne télécharge rien de l'extérieur : le logo des documents Word (`brand.logo.document`) n'est imprimé
que s'il est téléversé dans l'instance (`/files/brand/…`) ou donné en `data:`.

## Choix de couleurs

Le bleu de charte `#0097b6` sous un texte blanc n'atteint que 3,4:1, sous le seuil WCAG AA de 4,5:1 exigé à la
publication. Les boutons et les en-têtes de tableaux des documents Word utilisent donc `#00809b` (4,6:1). Le bleu de
charte reste sur les dégradés, le focus et la première série des graphiques. Les niveaux d'appréciation reprennent les
accents de la charte dans l'ordre attendu par l'application : violet (expertise confirmée), vert (très bon niveau),
bleu (intermédiaire), rouge (compétence non démontrée).
