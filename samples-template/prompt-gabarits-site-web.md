# Prompt : produire les gabarits Word depuis le site web de la société

Ce prompt fait produire par un assistant IA les trois gabarits Word de CVMatcher (CV, rapport de scoring « charte »,
rapport de scoring « analyse ») aux couleurs d'une ESN ou d'un cabinet de recrutement, à partir de son site public.

L'assistant lit les codes couleur, les polices et le logo du site, écrit une charte `charte.json`, puis exécute le
script [`generer_gabarits.py`](generer_gabarits.py), qui injecte ces couleurs dans les fichiers Word :

- dans les **styles nommés** (titres, corps, styles `CV …`, tableaux), modifiables ensuite dans Word ;
- dans la **palette** du document, c'est-à-dire les propriétés personnalisées `cvm.*` qui pilotent ce que CVMatcher
  dessine lui-même (en-têtes de tableaux, appréciations, note globale, radar, jauge).

Le mode d'emploi pas à pas se trouve dans la [notice](NOTICE-identite-graphique.md).

---

## Ce qu'il faut à l'assistant

| Élément | Obligatoire | Rôle |
|---|---|---|
| Lecture de pages web | oui | Lire le HTML et les feuilles de style du site |
| Exécution de code Python et création de fichiers | conseillé | Exécuter le script et rendre les `.docx`. Sans cela, l'assistant ne rend que `charte.json` et vous lancez le script vous-même |
| Fichier joint `generer_gabarits.py` | oui | Le script qui fabrique les gabarits |
| Fichier joint `nexora-conseil/charte.json` | oui | Exemple du format de charte attendu |
| Votre modèle de CV Word actuel | non | S'il est joint, il est habillé (option `--cv-base`) au lieu d'un CV créé de zéro |
| Votre logo en PNG haute définition | non | Prioritaire sur le logo trouvé sur le site |

---

## Prompt

Remplacez les valeurs entre `<< >>` avant d'envoyer. Supprimez la ligne « Interlocuteur » si vous ne voulez pas de bloc
contact sur la première page du CV.

```text
Tu prépares les gabarits Word de l'application CVMatcher pour la société suivante :

  Société        : <<Nom de la société>>
  Type           : <<ESN | cabinet de recrutement | société de portage | autre>>
  Site web       : <<https://www.exemple.fr/>>
  Interlocuteur  : <<Prénom Nom>>, <<fonction>>, <<email professionnel>>, <<téléphone>>

Fichiers joints : generer_gabarits.py (le générateur), charte.json (exemple de format, société fictive),
et le cas échéant notre modèle de CV Word actuel et notre logo.

Objectif : des documents Word (CV et rapports de scoring) qui reprennent fidèlement l'identité graphique du site :
couleurs, polices, logo.

ÉTAPE 1 — Lecture du site
  - Lis la page d'accueil, puis au plus trois pages utiles (contact, carrières ou recrutement, à propos).
  - Récupère les feuilles de style chargées (link rel="stylesheet") et les styles inline.
  - Couleurs, par ordre de priorité :
      1. variables CSS de :root (--primary, --brand, --color-*, --wp--preset--color--*, etc.) ;
      2. meta[name=theme-color] ;
      3. couleurs des boutons d'action, liens, titres h1-h3, en-tête et pied de page ;
      4. couleurs dominantes du logo.
    Ignore les couleurs des bibliothèques tierces (bannière cookies, widgets de chat, cartes, réseaux sociaux).
  - Polices : familles des titres et du texte (font-family, Google Fonts, Adobe Fonts, @font-face).
  - Logo : logo de l'en-tête (img, svg), og:image, link rel="icon" et apple-touch-icon. Retire les paramètres de
    redimensionnement (?width=…) pour obtenir le fichier d'origine. Si un logo est joint, utilise-le en priorité.
  - Adresse postale et slogan : repris du site s'ils y figurent (page contact, pied de page).
  - Ne collecte aucune donnée personnelle sur le site (noms, photos ou coordonnées de salariés) : l'interlocuteur est
    celui indiqué plus haut, et seulement lui.

ÉTAPE 2 — Attribution des rôles de couleur
  Range les couleurs relevées dans les rôles de la charte :
    primaire         couleur principale de la marque : titres, en-têtes de tableaux, nom du candidat
    secondaire       couleur d'accent : intitulé du poste, sous-titres, dates
    tertiaire        couleur décorative : filets, soulignements, 3e série des graphiques
    texte            texte courant (presque noir, teinté de la marque si le site le fait)
    texteSecondaire  texte gris des dates, secteurs, pieds de page
    fondClair        fond très clair teinté de la primaire (bloc contact, bandeau de la note)
    bordure          bordures de tableaux, grille du radar
    zebrure          une ligne sur deux des tableaux (plus clair que fondClair)
  Si le site n'a qu'une couleur de marque, dérive secondaire et tertiaire de façon harmonieuse (teinte voisine ou
  complémentaire) et dis-le.
  Niveaux d'appréciation (section "niveaux", facultative) : du plus fort au plus faible, EXPERTISE_CONFIRMEE,
  TRES_BON_NIVEAU, INTERMEDIAIRE, COMPETENCE_NON_DEMONTREE ; ils doivent rester distincts entre eux, et le dernier
  doit évoquer une alerte (rouge ou équivalent). Sans cette section, le générateur prend primaire, vert, secondaire
  et rouge.

ÉTAPE 3 — Lisibilité (obligatoire)
  - Contraste WCAG 2.1 d'au moins 4,5:1 sur fond blanc pour primaire, secondaire, texte et texteSecondaire, qui
    servent à écrire du texte. Le générateur choisit seul le blanc ou le texte sombre sur les fonds colorés.
  - Si une couleur de la marque n'atteint pas 4,5:1 (jaune, orange clair, vert pomme, turquoise…), garde-la en
    tertiaire (usage décoratif) et utilise pour le texte une version assombrie de la même teinte, la plus proche
    possible de l'originale qui atteint 4,5:1. Donne la couleur d'origine, la couleur retenue et les deux ratios.

ÉTAPE 4 — Polices
  Word n'affiche correctement que des polices installées sur le poste. Si la police du site n'est pas une police
  livrée avec Microsoft Office, choisis la police Office la plus proche et note l'équivalence. Repères :
    Montserrat, Poppins, Raleway, Nunito, Quicksand → Century Gothic
    Open Sans, Inter, Roboto, Source Sans, Noto Sans → Segoe UI
    Lato, Work Sans, Mulish, Helvetica, Arial         → Calibri ou Arial
    Playfair Display, Lora, Merriweather, Libre Baskerville → Georgia
    Cormorant, EB Garamond, Crimson                   → Garamond
  Conserve l'aspect général : un site aux titres sans empattement garde des titres sans empattement.

ÉTAPE 5 — Logo
  - Formats acceptés par Word : PNG ou JPEG. Préfère un PNG à fond transparent de 600 px de large au moins.
  - Si le logo n'existe qu'en SVG, convertis-le en PNG de 1200 px de large. Si tu ne peux pas, signale-le.
  - Deux fichiers : "logo.png" (logo complet, horizontal de préférence) et, s'il existe, "logo-seul.png"
    (symbole carré sans texte, utilisé en page de garde du rapport « analyse »).
  - Si aucun logo n'est récupérable, omets la section "logo" : le générateur écrit alors le nom de la société en
    couleur primaire.

ÉTAPE 6 — Charte
  Écris charte.json en suivant exactement le format de l'exemple joint : slug (minuscules et tirets), societe
  (nom, type, slogan, site, adresse en lignes, contact), logo (fichier, marque), polices (titres, texte), couleurs
  (#RRGGBB), niveaux (facultatif), palette (objet vide, sauf demande particulière), source. Dans source :
    methode = "WEBSITE_EXTRACTION", url = le site lu, extraitLe = date ISO 8601,
    notes = d'où vient chaque couleur (variable CSS, sélecteur ou logo), les teintes assombries, les polices
    remplacées, et un indice de confiance de 0 à 1 pour couleurs, polices et logo.
  Ne mets aucune clé supplémentaire hors de ces sections.

ÉTAPE 7 — Génération des gabarits
  Si tu peux exécuter du code :
    pip install python-docx
    python generer_gabarits.py charte.json
  (ajoute --cv-base <notre-modele.docx> si notre modèle de CV est joint).
  Le script produit cv.<slug>.docx, rapport-scoring.<slug>.docx et rapport-scoring-analyse.<slug>.docx, et affiche
  le contrôle des contrastes. Si une ligne est marquée BAS, corrige la charte et relance.
  Ne modifie pas le script : il produit les balises ({prenom}, {nom[0]}, {titre}, {poste}, {client}, {candidat},
  {date}, {version}, {corps}) et les propriétés cvm.* attendues par CVMatcher.
  Si tu ne peux pas exécuter de code, arrête-toi après l'étape 6 et indique la commande à lancer.

RÉPONSE ATTENDUE, dans cet ordre :
  a) un tableau des couleurs : rôle, couleur retenue, couleur d'origine du site, source, ratio de contraste sur blanc ;
  b) les polices du site et les polices Office retenues ;
  c) le contenu complet de charte.json dans un bloc ```json ;
  d) les fichiers à télécharger : charte.json, logo.png (et logo-seul.png), les trois .docx ;
  e) la sortie du contrôle des contrastes du script ;
  f) les points à faire vérifier : confiance inférieure à 0,6, logo de moins de 600 px ou converti depuis un SVG,
     couleurs dérivées faute de couleur secondaire sur le site, polices remplacées, informations non trouvées.
```

---

## Itérer avec l'assistant

Dans la même conversation, des demandes courtes suffisent. L'assistant modifie `charte.json` et relance le script.

| Besoin | Demande |
|---|---|
| Couleur trop vive ou trop terne | « Utilise #0A5A8C au lieu de la primaire actuelle et régénère. » |
| Inverser deux couleurs | « Mets l'orange en primaire et le bleu en secondaire. » |
| Niveaux d'appréciation | « Utilise le vert de la marque pour Très bon niveau. » |
| Couleur d'un seul élément | « Mets l'en-tête du tableau des forces en #1E7F4F. » (section `palette`, clé `documents.tables.forces.headerBackground`) |
| Rapport sans zébrure | « Pas de zébrure dans les tableaux. » (clé `documents.tableStripe` = `aucune`) |
| Autre police | « Titres en Segoe UI Semibold. » |

La section `palette` de la charte accepte toutes les clés `cvm.*` de CVMatcher (sans le préfixe). La liste est
donnée dans la [notice](NOTICE-identite-graphique.md#8-référence).
