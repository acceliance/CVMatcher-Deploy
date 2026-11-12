# Registre de traitement RGPD — notice

Ce dossier contient [`registre-traitement-rgpd.docx`](registre-traitement-rgpd.docx). C'est un modèle de **registre des
activités de traitement** (article 30 du RGPD) adapté à une instance CVMatcher.

## À quoi sert ce document

Toute société qui traite des données personnelles doit tenir ce registre et le présenter à la CNIL sur demande. Dans
CVMatcher, ces données sont celles des candidats et des utilisateurs.

Les rôles se répartissent ainsi :

| Rôle RGPD | Qui | Responsabilité |
|---|---|---|
| Responsable de traitement | La société de recrutement cliente | Tient le registre, choisit la base légale, répond aux candidats |
| Sous-traitant | Acceliance | Héberge et exploite l'instance dédiée |
| Sous-traitant ultérieur | Le fournisseur d'IA retenu, s'il y en a un | Analyse les CV, envoyés sans identité |

Le registre est donc **le vôtre**. Le modèle vous évite de partir de zéro et garantit que ce qui y est écrit correspond à ce
que l'application fait réellement.

Ce document n'est pas un gabarit de rendu. CVMatcher ne l'utilise pas et il ne se dépose pas dans
Administration ▸ Modèles.

## Comment le compléter

1. Copiez le fichier dans vos documents de conformité. Ne le modifiez pas dans ce dépôt.
2. Remplacez toutes les valeurs **entre crochets** `[...]` (voir le tableau ci-dessous).
3. Relisez les valeurs pré-remplies. Elles décrivent le comportement **par défaut** de l'application. Si vous avez changé un
   paramètre de l'instance, corrigez la ligne correspondante.
4. Renseignez la date de mise à jour et le numéro de version en tête du document.
5. Faites valider le document par votre délégué à la protection des données (DPO), si vous en avez un.

### Champs à compléter

| Rubrique | Ce qu'il faut indiquer | Où trouver l'information |
|---|---|---|
| Responsable de traitement | Raison sociale, adresse, représentant légal | Votre société |
| Délégué à la protection des données | Nom et contact du DPO, ou « non désigné » | Votre société |
| Sous-traitant | FQDN de l'instance et hébergeur (OVHcloud, Scaleway, VM du client…) | Fiche d'instance, contrat |
| Base légale | Intérêt légitime, ou mesures précontractuelles à la demande du candidat | Paramètre `rgpd.baseLegale` de l'instance |
| Sous-traitants ultérieurs (IA) | Fournisseur retenu : Anthropic, OpenAI, Mistral ou modèle local | Configuration IA de l'instance |
| Transferts hors UE | Pays de traitement du fournisseur d'IA ; « aucun » si `AI_EGRESS_ALLOWED=false` ou modèle local | `.env` de l'instance, contrat du fournisseur |

### Valeurs pré-remplies à vérifier

| Rubrique | Valeur par défaut | À revoir si… |
|---|---|---|
| Finalités | Candidatures et vivier, rapprochement CV / fiches de poste, production de CV et de rapports | Vous utilisez l'application à d'autres fins |
| Personnes concernées | Candidats ; utilisateurs (recruteurs, managers) | — |
| Catégories de données | Identité, coordonnées, parcours, formations, compétences, langues ; pas de donnée sensible attendue | Vous ajoutez des champs ou des documents |
| Destinataires | Utilisateurs habilités selon leur rôle ; clients destinataires des CV anonymisés | Vous transmettez des CV non anonymisés |
| Durée de conservation | 24 mois après le dernier contact, alerte 30 jours avant, puis effacement automatique | Vous changez `retention.candidatMois` |
| Droits des personnes | Export ZIP (accès, portabilité), effacement en cascade, rectification dans la revue du CV | — |
| Mesures de sécurité | TLS, clés IA chiffrées, accès par rôle, audit sans nom après effacement, sauvegardes chiffrées hors site, instance dédiée | Vous désactivez les sauvegardes ou changez d'hébergement |

## Quand le mettre à jour

Mettez à jour le registre et incrémentez sa version à chacun de ces changements :

- changement de fournisseur d'IA ou de sa région de traitement ;
- modification de la durée de conservation ou de la base légale ;
- changement d'hébergeur ou migration de l'instance ;
- nouvel usage de l'application, ou nouvelle catégorie de destinataires.

## Pour aller plus loin

Sur <https://www.cnil.fr>, consultez :
- la fiche « Le registre des activités de traitement », qui propose un modèle et un guide ;
- le référentiel « Recrutement », qui donne les durées de conservation recommandées.

Les fonctions RGPD de l'application sont présentées dans la section « Sécurité, RGPD et AI Act » du
[README du kit](../README.md).
