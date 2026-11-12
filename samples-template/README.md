# Gabarits Word d'exemple

| Fichier | Contenu |
|---|---|
| [`NOTICE-identite-graphique.md`](NOTICE-identite-graphique.md) | **Notice** : obtenir des CV et des rapports aux couleurs de votre entreprise, puis les mettre en service |
| [`prompt-gabarits-site-web.md`](prompt-gabarits-site-web.md) | Prompt pour faire produire vos gabarits par un assistant IA à partir de votre site web |
| [`generer_gabarits.py`](generer_gabarits.py) | Générateur : charte JSON → trois gabarits Word (styles et palette `cvm.*` aux couleurs de la charte) |
| [`nexora-conseil/`](nexora-conseil/) | Exemple **fictif** d'ESN : charte, logos, gabarit de CV et deux gabarits de rapport |
| [`boreal-recrutement/`](boreal-recrutement/) | Exemple **fictif** de cabinet de recrutement : charte, logos, gabarit de CV et deux gabarits de rapport |
| [`apercus/`](apercus/) | Rendu des six gabarits d'exemple, générés par CVMatcher avec des données de démonstration |
| `cv-template.example.docx` | Modèle de CV nu, sans charte graphique |

Nexora Conseil et Boréal Recrutement n'existent pas : noms, adresses, interlocuteurs, logos et domaines
(`.example`) sont inventés. Les numéros de téléphone appartiennent aux plages réservées par l'Arcep à la fiction.

Pour régénérer un exemple :

```bash
python generer_gabarits.py nexora-conseil/charte.json
```
