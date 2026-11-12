# Prompt : produire le thème JSON depuis le site web du client

Exemple de prompt pour faire écrire par un assistant IA capable de lire des pages web (Claude, par exemple) le fichier
`brand-theme.json` d'une instance CVMatcher à partir du site public du client. Il est rempli ici pour
[www.acceliance.fr](https://www.acceliance.fr). Pour un autre client, remplacez l'URL et le nom.

Le prompt demande aussi la valeur de la variable Docker `THEME_ASSET_HOSTS`. Elle doit lister chaque hôte d'où le thème
charge un logo ou une police, sinon l'application refuse le thème au dépôt.

Joignez à la conversation le schéma [`../../schemas/brand-theme.schema.json`](../../schemas/brand-theme.schema.json).
L'assistant s'y conforme, et l'application valide le thème contre ce même schéma.

---

## Prompt

```text
Tu produis le thème visuel d'une instance CVMatcher pour la société Acceliance, à partir de son site public
https://www.acceliance.fr/. Le résultat est un fichier JSON conforme au schéma brand-theme.schema.json joint
(JSON Schema 2020-12, additionalProperties: false partout : n'ajoute aucune clé absente du schéma).

1. Lecture du site
   - Lis le HTML de la page d'accueil et les feuilles de style qu'elle charge (link rel="stylesheet").
   - Couleurs : variables CSS de :root en priorité, puis meta[name=theme-color], puis couleurs dominantes des
     boutons, liens, en-tête et corps de page.
   - Polices : familles des titres et du texte. Si le site les charge depuis Google Fonts, reprends l'URL de la
     feuille https://fonts.googleapis.com/css2?... dans typography.heading.url et typography.body.url.
   - Logos : logo de l'en-tête, og:image, link[rel~=icon], apple-touch-icon. Supprime les paramètres de
     redimensionnement (?width=…&height=…) pour garder le fichier d'origine.

2. Logos chargés directement depuis le site
   - brand.logo.* contient les URL https absolues des fichiers du site. Ne télécharge rien et n'encode rien en
     data: : le navigateur de chaque utilisateur charge les images depuis le site.
   - mark : icône carrée ou monogramme (affiché dans l'en-tête de l'application) ; favicon : icône du site ;
     primary : logo horizontal complet s'il existe en fichier image (pas un SVG inline) ; document : le plus grand
     PNG ou JPEG disponible (600 px de large conseillés pour Word ; signale-le s'il est plus petit).
   - Vérifie que chaque URL répond 200 avec un Content-Type image/*. Sinon, n'utilise pas cette URL et signale-le.

3. Accessibilité (contrôlée à la publication, bloquante)
   - Contraste WCAG 2.1 AA 4,5:1 pour : colors.text sur colors.background et colors.surface, colors.onPrimary sur
     colors.primary, le texte de chaque niveau appreciation.* et impact.* sur son fond, documents.tableHeaderText
     sur documents.tableHeaderBackground.
   - Si une couleur de la charte n'atteint pas 4,5:1, garde-la pour les éléments décoratifs (secondary, focus,
     charts) et utilise une teinte assombrie pour les couples texte/fond. Donne chaque ratio calculé.
   - appreciation : EXPERTISE_CONFIRMEE, TRES_BON_NIVEAU, INTERMEDIAIRE, COMPETENCE_NON_DEMONTREE, du plus fort au
     plus faible, avec les accents de la charte.

4. Traçabilité
   - meta.client = "Acceliance" ; meta.source.method = "WEBSITE_EXTRACTION" ; meta.source.url = l'URL lue ;
     meta.source.extractedAt = date et heure ISO 8601 ; meta.source.confidence = un score de 0 à 1 pour colors,
     typography, logo, colorsDark (en dessous de 0,6, l'écran d'administration signale la valeur à vérifier).
   - meta.source.notes : d'où vient chaque couleur (nom de la variable CSS), les teintes corrigées pour le
     contraste, et la valeur de THEME_ASSET_HOSTS.
   - colorsDark : seulement si le site a une règle @media (prefers-color-scheme: dark) ; sinon omets la section.

5. Variable THEME_ASSET_HOSTS
   - Relève l'hôte de chaque URL https du thème : brand.logo.*, typography.*.url, et les url() de cssVariables.
     Ne compte pas brand.website ni meta.source.url, qui ne sont jamais chargés.
   - Pour une feuille Google Fonts, ajoute fonts.gstatic.com : la feuille de fonts.googleapis.com charge les
     fichiers de police depuis cet hôte.
   - Format : hôtes séparés par des virgules, sans schéma, sans chemin ni espace (exemple :
     www.client.fr,fonts.googleapis.com,fonts.gstatic.com). N'utilise jamais * : cette valeur autorise tout hôte.

Réponds avec, dans cet ordre :
  a) le fichier brand-theme.json complet, dans un seul bloc ```json ;
  b) la ligne THEME_ASSET_HOSTS=… à placer dans la configuration Docker ;
  c) un tableau des couples de contraste (couple, texte, fond, ratio) ;
  d) les points à faire vérifier par l'administrateur (confiance < 0,6, logo document trop petit, URL écartées).
```

---

## Résultat attendu pour www.acceliance.fr

Le thème [`../brand-theme.acceliance.json`](../brand-theme.acceliance.json) montre le résultat attendu. Ses logos
viennent du site :

| Clé | URL |
|---|---|
| `brand.logo.mark` | `https://www.acceliance.fr/media/wdxp1zys/logo-acc-seul-400.png` |
| `brand.logo.favicon` | `https://www.acceliance.fr/media/rdchpdwu/logo-acc-seul-64.png` |
| `brand.logo.document` | `https://www.acceliance.fr/media/wdxp1zys/logo-acc-seul-400.png` (400 px, sous les 600 px conseillés) |
| `typography.*.url` | `https://fonts.googleapis.com/css2?family=…` |

Valeur à positionner :

```text
THEME_ASSET_HOSTS=www.acceliance.fr,fonts.googleapis.com,fonts.gstatic.com
```

| Hôte | Raison |
|---|---|
| `www.acceliance.fr` | Logos (`brand.logo.*`) |
| `fonts.googleapis.com` | Feuilles de polices (`typography.heading.url`, `typography.body.url`) |
| `fonts.gstatic.com` | Fichiers de polices chargés par ces feuilles |

## Appliquer la variable

1. Ajoutez la ligne dans la configuration de l'instance, `instances/<fqdn>/config.app.env` (ou `kit/compose/.env`
   pour un déploiement compose seul).
2. Recréez les conteneurs. L'edge construit sa politique de sécurité de contenu (CSP) au démarrage à partir de cette
   variable, donc un simple redémarrage de l'API ne suffit pas :

   ```powershell
   ./scripts/deploy.ps1 <fqdn> -Stage config,app
   ```

3. Dans **Administration ▸ Thème**, téléversez le JSON, relisez le contrôle de contraste et les valeurs à vérifier,
   puis publiez.

Si un hôte manque dans la variable, le dépôt est refusé (422) et le message donne le chemin JSON et l'URL en cause. Si
un hôte est retiré après la publication, l'application sert le thème sans ces références et l'événement
`theme.asset_blocked` est journalisé.

Le worker ne télécharge aucune ressource externe. Un `brand.logo.document` en URL https n'apparaît donc pas dans les
documents Word. Pour l'y imprimer, téléversez le fichier dans l'instance avec l'API `POST /api/files/brand` (champ
`file`, rôle administrateur) et référencez le chemin `/files/brand/…` qu'elle renvoie.
