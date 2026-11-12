"""Génère les gabarits Word de CVMatcher aux couleurs d'une société, à partir d'une charte JSON.

Trois gabarits sont produits dans le dossier de la charte (ou celui donné par --out) :

| Fichier                              | Famille   | Mise en page                                                    |
|--------------------------------------|-----------|-----------------------------------------------------------------|
| cv.<slug>.docx                       | cv        | Bloc d'identité en page 1, styles « CV … », en-tête et pied     |
| rapport-scoring.<slug>.docx          | rapport   | Variante « charte » : en-tête avec logo et filet de couleur     |
| rapport-scoring-analyse.<slug>.docx  | rapport   | Variante « analyse » : page de garde, titres en capitales       |

Les couleurs de la charte sont injectées à deux endroits :

1. dans les **styles nommés** du document (titres, corps, puces, styles « CV … », tableaux), qui restent modifiables
   dans Word ;
2. dans la **palette** du document : propriétés personnalisées `cvm.*` (Fichier ▸ Informations ▸ Propriétés ▸
   Propriétés avancées ▸ Personnalisation), qui pilotent ce que CVMatcher dessine lui-même (en-têtes et zébrure des
   tableaux, appréciations, impacts, note globale, radar, jauge).

Le script contrôle aussi les contrastes (WCAG 2.1) des couples texte/fond et les signale.

Prérequis : Python 3.10 ou plus, puis `pip install python-docx`.

Usage :
    python generer_gabarits.py <charte.json> [--out <dossier>] [--cv-base <mon-modele-cv.docx>]

`--cv-base` part d'un modèle de CV Word existant de la société au lieu d'en créer un : seuls les styles « CV … » et
la palette sont ajoutés ; en-tête, pied de page, page de garde et balises sont conservés.
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
import zipfile
from pathlib import Path
from typing import Any

try:
    from docx import Document
    from docx.enum.section import WD_SECTION_START
    from docx.enum.style import WD_STYLE_TYPE
    from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_TAB_ALIGNMENT
    from docx.oxml import OxmlElement
    from docx.oxml.ns import qn
    from docx.shared import Cm, Pt, RGBColor
    from lxml import etree
except ImportError:  # pragma: no cover - message d'installation
    sys.exit("Module manquant : installez-le avec  pip install python-docx")

# ====================================================================================== palette `cvm.*`
PREFIX = "cvm."
ROLES = (
    "section", "period", "exp_title", "details", "synthesis", "environment", "subheading", "body",
    "presentation", "bullet", "skills_heading", "skills", "formation", "langues", "caption",
)  # fmt: skip
TABLES = ("indicateurs", "radar", "forces", "faiblesses", "methode", "comparatif")
LEVELS = {
    "appreciation": ("EXPERTISE_CONFIRMEE", "TRES_BON_NIVEAU", "INTERMEDIAIRE", "COMPETENCE_NON_DEMONTREE"),
    "impact": ("FORT", "MOYEN", "FAIBLE"),
}


def _palette_keys() -> dict[str, str]:
    """Clés reconnues par CVMatcher → nature de la valeur (color, fill, colors, opacity, style)."""
    keys = {
        "colors.text": "color", "colors.textMuted": "color",
        "documents.headingColor": "color", "documents.accentColor": "color", "documents.keywordColor": "color",
        "documents.scoreText": "color", "documents.scoreBackground": "fill",
        "documents.tableHeaderBackground": "color", "documents.tableHeaderText": "color",
        "documents.tableBorder": "color", "documents.tableStripe": "fill",
        "documents.appreciationStyle": "style", "documents.impactStyle": "style",
        "charts.series": "colors", "charts.grid": "color", "charts.labels": "color", "charts.radarFill": "color",
        "charts.radarFillOpacity": "opacity", "charts.gaugeTrack": "color", "charts.gaugeFill": "color",
        "charts.gaugeText": "color",
    }  # fmt: skip
    keys.update({f"documents.roles.{r}.color": "color" for r in ROLES})
    for t in TABLES:
        keys.update({f"documents.tables.{t}.headerBackground": "color", f"documents.tables.{t}.headerText": "color"})
        keys[f"documents.tables.{t}.stripe"] = "fill"
    for family, levels in LEVELS.items():
        for lvl in levels:
            keys.update({f"{family}.{lvl}.background": "color", f"{family}.{lvl}.text": "color"})
    return keys


KEYS = _palette_keys()
_HEX = re.compile(r"^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")


def hexa(value: str, where: str = "") -> str:
    """Couleur normalisée `#RRGGBB` ; arrêt du script si la valeur est mal formée."""
    m = _HEX.match(str(value).strip())
    if not m:
        sys.exit(f"Couleur invalide {value!r} {where}".strip())
    h = m.group(1)
    return "#" + ("".join(c * 2 for c in h) if len(h) == 3 else h).upper()


def _serialize(value: Any) -> str:
    return ", ".join(value) if isinstance(value, list | tuple) else str(value)


def write_palette(data: bytes, palette: dict[str, Any]) -> bytes:
    """Écrit la palette en propriétés personnalisées `cvm.*` (docProps/custom.xml) ; le reste est recopié tel quel."""
    unknown = sorted(k for k in palette if k not in KEYS)
    if unknown:
        sys.exit(f"Clés de palette inconnues : {', '.join(unknown)}")
    ns_cp = "http://schemas.openxmlformats.org/officeDocument/2006/custom-properties"
    ns_vt = "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"
    ns_ct = "http://schemas.openxmlformats.org/package/2006/content-types"
    ns_rel = "http://schemas.openxmlformats.org/package/2006/relationships"
    rel_type = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties"
    part = "docProps/custom.xml"

    zin = zipfile.ZipFile(io.BytesIO(data))
    props: dict[str, str] = {}
    if part in zin.namelist():
        for prop in etree.fromstring(zin.read(part)).findall(f"{{{ns_cp}}}property"):
            child = next(iter(prop), None)
            name = prop.get("name") or ""
            if child is not None and child.text is not None and not name.lower().startswith(PREFIX):
                props[name] = child.text  # propriétés étrangères à CVMatcher conservées
    props.update({PREFIX + k: _serialize(v) for k, v in palette.items()})

    root = etree.Element(f"{{{ns_cp}}}Properties", nsmap={None: ns_cp, "vt": ns_vt})
    for pid, (name, value) in enumerate(sorted(props.items()), start=2):
        prop = etree.SubElement(
            root, f"{{{ns_cp}}}property", fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}", pid=str(pid), name=name
        )
        etree.SubElement(prop, f"{{{ns_vt}}}lpwstr").text = value
    custom = etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True)

    ct = etree.fromstring(zin.read("[Content_Types].xml"))
    if not any(o.get("PartName") == "/" + part for o in ct.findall(f"{{{ns_ct}}}Override")):
        etree.SubElement(
            ct, f"{{{ns_ct}}}Override", PartName="/" + part,
            ContentType="application/vnd.openxmlformats-officedocument.custom-properties+xml",
        )  # fmt: skip
    rels = etree.fromstring(zin.read("_rels/.rels"))
    if not any(r.get("Type") == rel_type for r in rels):
        ids = {r.get("Id") for r in rels}
        rid = next(f"rId{i}" for i in range(1, 1000) if f"rId{i}" not in ids)
        etree.SubElement(rels, f"{{{ns_rel}}}Relationship", Id=rid, Type=rel_type, Target=part)

    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename == part:
                continue
            payload = zin.read(item.filename)
            if item.filename == "[Content_Types].xml":
                payload = etree.tostring(ct, xml_declaration=True, encoding="UTF-8", standalone=True)
            elif item.filename == "_rels/.rels":
                payload = etree.tostring(rels, xml_declaration=True, encoding="UTF-8", standalone=True)
            zout.writestr(item, payload)
        zout.writestr(part, custom)
    return out.getvalue()


# ====================================================================================== contrastes WCAG 2.1
def _lum(color: str) -> float:
    def ch(c: int) -> float:
        s = c / 255
        return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4

    h = color.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a: str, b: str) -> float:
    la, lb = sorted((_lum(a), _lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def on(background: str, dark: str) -> str:
    """Texte lisible sur un fond : blanc ou la couleur de texte sombre, celle qui contraste le mieux."""
    return "#FFFFFF" if contrast(background, "#FFFFFF") >= contrast(background, dark) else dark


# ====================================================================================== charte
WHITE = "#FFFFFF"
DEFAULTS = {
    "texte": "#1F2A2E",
    "texteSecondaire": "#5F6B70",
    "fondClair": "#EEF3F6",
    "bordure": "#C9D2D8",
    "zebrure": "#F4F6F8",
    "succes": "#2E7D32",
    "alerte": "#E8A33D",
    "danger": "#B42318",
    "neutre": "#9AA3A8",
}


class Charte:
    """Charte lue dans le JSON, complétée par les valeurs par défaut."""

    def __init__(self, path: Path) -> None:
        raw = json.loads(path.read_text(encoding="utf-8"))
        self.dir = path.parent
        self.slug = raw.get("slug") or re.sub(r"[^a-z0-9]+", "-", raw["societe"]["nom"].lower()).strip("-")
        self.societe: dict[str, Any] = raw["societe"]
        self.nom: str = self.societe["nom"]
        c = {**DEFAULTS, **raw.get("couleurs", {})}
        for req in ("primaire", "secondaire"):
            if req not in c:
                sys.exit(f"La charte doit définir couleurs.{req}")
        c.setdefault("tertiaire", c["secondaire"])
        self.c = {k: hexa(v, f"(couleurs.{k})") for k, v in c.items()}
        fonts = raw.get("polices", {})
        self.titres: str = fonts.get("titres", "Arial")
        self.texte: str = fonts.get("texte", "Calibri")
        logo = raw.get("logo", {})
        self.logo = self._file(logo.get("fichier"))
        self.marque = self._file(logo.get("marque")) or self.logo
        self.niveaux: dict[str, str] = {k: hexa(v) for k, v in raw.get("niveaux", {}).items()}
        self.surcharges: dict[str, Any] = raw.get("palette", {})

    def _file(self, name: str | None) -> Path | None:
        if not name:
            return None
        p = (self.dir / name).resolve()
        if not p.is_file():
            print(f"avertissement : logo introuvable, ignoré : {p}", file=sys.stderr)
            return None
        return p

    # ------------------------------------------------------------------ palettes des trois gabarits
    def _levels(self) -> dict[str, str]:
        c, n = self.c, self.niveaux
        colors = {
            "appreciation.EXPERTISE_CONFIRMEE": n.get("EXPERTISE_CONFIRMEE", c["primaire"]),
            "appreciation.TRES_BON_NIVEAU": n.get("TRES_BON_NIVEAU", c["succes"]),
            "appreciation.INTERMEDIAIRE": n.get("INTERMEDIAIRE", c["secondaire"]),
            "appreciation.COMPETENCE_NON_DEMONTREE": n.get("COMPETENCE_NON_DEMONTREE", c["danger"]),
            "impact.FORT": n.get("FORT", c["danger"]),
            "impact.MOYEN": n.get("MOYEN", c["alerte"]),
            "impact.FAIBLE": n.get("FAIBLE", c["neutre"]),
        }
        out: dict[str, str] = {}
        for key, bg in colors.items():
            out[f"{key}.background"] = bg
            out[f"{key}.text"] = on(bg, c["texte"])
        return out

    def palette(self, variante: str) -> dict[str, Any]:
        c = self.c
        p, s, t = c["primaire"], c["secondaire"], c["tertiaire"]
        if variante == "cv":
            pal: dict[str, Any] = {
                "colors.text": c["texte"],
                "colors.textMuted": c["texteSecondaire"],
                "documents.headingColor": p,
                "documents.accentColor": s,
                "documents.roles.section.color": p,
                "documents.roles.period.color": s,
                "documents.roles.exp_title.color": s,
                "documents.roles.details.color": c["texteSecondaire"],
                "documents.roles.environment.color": c["texteSecondaire"],
                "documents.roles.subheading.color": s,
                "documents.roles.skills_heading.color": s,
            }
        else:
            pal = {
                "colors.text": c["texte"],
                "colors.textMuted": c["texteSecondaire"],
                "documents.headingColor": p,
                "documents.accentColor": s,
                "documents.tableHeaderBackground": p,
                "documents.tableHeaderText": on(p, c["texte"]),
                "documents.tableBorder": c["bordure"],
                "documents.tableStripe": c["zebrure"],
                **self._levels(),
                "charts.grid": c["bordure"],
                "charts.radarFillOpacity": 0.25,
                "charts.gaugeTrack": c["fondClair"],
            }
            if variante == "charte":
                pal.update({
                    "documents.scoreText": p,
                    "documents.appreciationStyle": "FOND",
                    "documents.impactStyle": "FOND",
                    "charts.series": [p, s, t],
                    "charts.labels": c["texte"],
                    "charts.radarFill": p,
                    "charts.gaugeFill": p,
                    "charts.gaugeText": c["texte"],
                })  # fmt: skip
            else:  # analyse : note en bandeau, forces et risques distingués, niveaux en texte coloré
                pal.update({
                    "documents.scoreText": s,
                    "documents.scoreBackground": c["fondClair"],
                    "documents.tables.forces.headerBackground": c["succes"],
                    "documents.tables.forces.headerText": on(c["succes"], c["texte"]),
                    "documents.tables.faiblesses.headerBackground": c["danger"],
                    "documents.tables.faiblesses.headerText": on(c["danger"], c["texte"]),
                    "documents.appreciationStyle": "TEXTE",
                    "documents.impactStyle": "FOND",
                    "charts.series": [s, p, t],
                    "charts.labels": p,
                    "charts.radarFill": s,
                    "charts.gaugeFill": s,
                    "charts.gaugeText": s,
                })  # fmt: skip
        for key, value in self.surcharges.items():  # surcharges explicites de la charte
            key = key.removeprefix(PREFIX)
            if KEYS.get(key) == "colors":
                items = value if isinstance(value, list) else [v for v in re.split(r"[,;\s]+", value) if v]
                value = [hexa(v, f"(palette.{key})") for v in items]
            elif KEYS.get(key) in ("color", "fill") and str(value).lower() not in ("aucune", "none"):
                value = hexa(value, f"(palette.{key})")
            pal[key] = value
        return pal

    # ------------------------------------------------------------------ contrôle des contrastes
    def contrastes(self) -> list[tuple[str, str, str, float, float]]:
        """(couple, texte, fond, ratio, seuil) des couples lus dans les documents."""
        c = self.c
        pairs = [
            ("Texte courant", c["texte"], WHITE, 4.5),
            ("Texte secondaire (dates, détails)", c["texteSecondaire"], WHITE, 4.5),
            ("Titres (primaire)", c["primaire"], WHITE, 4.5),
            ("Poste, sous-titres (secondaire)", c["secondaire"], WHITE, 4.5),
            ("En-tête de tableau", on(c["primaire"], c["texte"]), c["primaire"], 4.5),
            ("Note globale en bandeau", c["secondaire"], c["fondClair"], 4.5),
        ]
        for key, bg in self._levels().items():
            if key.endswith(".background"):
                lvl = key[: -len(".background")]
                pairs.append((f"Niveau {lvl}", on(bg, c["texte"]), bg, 4.5))
                if lvl.startswith("appreciation."):  # variante analyse : libellé coloré sur fond blanc
                    pairs.append((f"Niveau {lvl} en texte", bg, WHITE, 3.0))
        return [(name, fg, bg, contrast(fg, bg), seuil) for name, fg, bg, seuil in pairs]


# ====================================================================================== briques Word
def font(target: Any, name: str, size: float | None = None, color: str | None = None, bold: bool | None = None,
         italic: bool | None = None) -> None:  # fmt: skip
    """Police explicite (les polices de thème de Word sont retirées, sinon elles priment)."""
    f = target.font
    f.name = name
    rpr = (target.element if hasattr(target, "element") else target._r).get_or_add_rPr()
    fonts = rpr.get_or_add_rFonts()
    for attr in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
        fonts.set(qn(attr), name)
    for attr in ("w:asciiTheme", "w:hAnsiTheme", "w:cstheme", "w:eastAsiaTheme"):
        fonts.attrib.pop(qn(attr), None)
    if size is not None:
        f.size = Pt(size)
    if color is not None:
        f.color.rgb = RGBColor.from_string(color.lstrip("#"))
    if bold is not None:
        f.bold = bold
    if italic is not None:
        f.italic = italic


def border(target: Any, side: str, color: str, size: int = 8, space: int = 4) -> None:
    """Filet de paragraphe ou de style (`size` en huitièmes de point)."""
    ppr = target.element.get_or_add_pPr() if hasattr(target, "element") else target._p.get_or_add_pPr()
    bdr = ppr.find(qn("w:pBdr"))
    if bdr is None:
        bdr = OxmlElement("w:pBdr")
        ppr.append(bdr)
    edge = OxmlElement(f"w:{side}")
    for k, v in (("w:val", "single"), ("w:sz", str(size)), ("w:space", str(space)), ("w:color", color.lstrip("#"))):
        edge.set(qn(k), v)
    bdr.append(edge)


def shade(paragraph: Any, color: str) -> None:
    """Fond coloré d'un paragraphe (bandeau)."""
    ppr = paragraph._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    for k, v in (("w:val", "clear"), ("w:color", "auto"), ("w:fill", color.lstrip("#"))):
        shd.set(qn(k), v)
    ppr.append(shd)


def field(paragraph: Any, instr: str, fname: str, color: str) -> None:
    """Champ Word calculé à l'ouverture (PAGE, NUMPAGES)."""
    run = paragraph.add_run()
    font(run, fname, 8, color)
    for kind, text in (("begin", None), ("instr", instr), ("separate", None), ("text", "1"), ("end", None)):
        if kind == "instr":
            el = OxmlElement("w:instrText")
            el.set(qn("xml:space"), "preserve")
            el.text = f" {text} "
        elif kind == "text":
            el = OxmlElement("w:t")
            el.text = text
        else:
            el = OxmlElement("w:fldChar")
            el.set(qn("w:fldCharType"), kind)
        run._r.append(el)


def table_style(style: Any, border_color: str, stripe: str | None) -> None:
    """Bordures, marges de cellule et zébrure (`band1Horz`) du style de tableau."""
    tblpr = style.element.find(qn("w:tblPr"))
    if tblpr is None:
        tblpr = OxmlElement("w:tblPr")
        style.element.append(tblpr)
    for tag in ("w:tblBorders", "w:tblCellMar"):
        old = tblpr.find(qn(tag))
        if old is not None:
            tblpr.remove(old)
    borders = OxmlElement("w:tblBorders")
    for side in ("top", "left", "bottom", "right", "insideH", "insideV"):
        e = OxmlElement(f"w:{side}")
        for k, v in (("w:val", "single"), ("w:sz", "4"), ("w:space", "0"), ("w:color", border_color.lstrip("#"))):
            e.set(qn(k), v)
        borders.append(e)
    tblpr.append(borders)
    margins = OxmlElement("w:tblCellMar")
    for side, w in (("top", 40), ("left", 90), ("bottom", 40), ("right", 90)):
        e = OxmlElement(f"w:{side}")
        e.set(qn("w:w"), str(w))
        e.set(qn("w:type"), "dxa")
        margins.append(e)
    tblpr.append(margins)
    if stripe:
        band = OxmlElement("w:tblStyleRowBandSize")
        band.set(qn("w:val"), "1")
        tblpr.insert(0, band)
        pr = OxmlElement("w:tblStylePr")
        pr.set(qn("w:type"), "band1Horz")
        tcpr = OxmlElement("w:tcPr")
        shd = OxmlElement("w:shd")
        for k, v in (("w:val", "clear"), ("w:color", "auto"), ("w:fill", stripe.lstrip("#"))):
            shd.set(qn(k), v)
        tcpr.append(shd)
        pr.append(tcpr)
        style.element.append(pr)


def new_document(ch: Charte, title: str, body_font: str) -> Any:
    doc = Document()
    doc.core_properties.title = title
    doc.core_properties.author = ch.nom
    doc.core_properties.language = "fr-FR"
    normal = doc.styles["Normal"]
    font(normal, body_font, 10, ch.c["texte"])
    normal.paragraph_format.space_after = Pt(4)
    normal.paragraph_format.line_spacing = 1.15
    lang = OxmlElement("w:lang")
    lang.set(qn("w:val"), "fr-FR")
    normal.element.get_or_add_rPr().append(lang)
    for name in ("Header", "Footer"):  # taquets par défaut de Word retirés (alignement à droite du pied)
        doc.styles[name].paragraph_format.tab_stops.clear_all()
    section = doc.sections[0]
    section.start_type = WD_SECTION_START.NEW_PAGE
    section.page_width, section.page_height = Cm(21), Cm(29.7)
    section.left_margin = section.right_margin = Cm(2)
    section.header_distance, section.footer_distance = Cm(1), Cm(0.9)
    return doc


def first_paragraph(doc: Any) -> Any:
    """Premier paragraphe du corps (créé si le document vierge n'en a pas)."""
    return doc.paragraphs[0] if doc.paragraphs else doc.add_paragraph()


def logo_or_name(paragraph: Any, ch: Charte, logo: Path | None, height: float) -> None:
    """Logo de la société, ou son nom en couleur primaire si la charte n'a pas de logo."""
    if logo:
        paragraph.add_run().add_picture(str(logo), height=Cm(height))
    else:
        font(paragraph.add_run(ch.nom), ch.titres, height * 9, ch.c["primaire"], bold=True)


def save(doc: Any, out: Path, palette: dict[str, Any]) -> Path:
    buf = io.BytesIO()
    doc.save(buf)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(write_palette(buf.getvalue(), palette))
    return out


# ====================================================================================== gabarit de CV
#: nom → (police titres ?, taille, couleur, gras, italique, alignement, avant, après, retrait, alinéa)
CV_STYLES: dict[str, tuple] = {
    "CV Section": (True, 12, "primaire", True, False, "left", 12, 3, 0, 0),
    "CV Sous-titre": (False, 10.5, "secondaire", True, False, "left", 2, 0, 0, 0),
    "CV Corps": (False, 10, "texte", False, False, "justify", 0, 2, 0, 0),
    "CV Puce": (False, 10, "texte", False, False, "left", 0, 0, 0.9, -0.3),
    "CV Période": (False, 9, "secondaire", False, True, "left", 10, 0, 0, 0),
    "CV Poste": (True, 11, "secondaire", True, False, "left", 0, 0, 0, 0),
    "CV Détails": (False, 9, "texteSecondaire", False, True, "left", 0, 0, 0, 0),
    "CV Synthèse": (False, 10, "texte", False, True, "justify", 0, 0, 0, 0),
    "CV Environnement": (False, 9, "texteSecondaire", False, True, "left", 0, 0, 0, 0),
    "CV Compétences": (False, 10, "texte", False, False, "left", 0, 0, 0.6, 0),
}
KEEP_WITH_NEXT = {"CV Section", "CV Sous-titre", "CV Période", "CV Poste"}
ALIGN = {"left": WD_ALIGN_PARAGRAPH.LEFT, "justify": WD_ALIGN_PARAGRAPH.JUSTIFY}


def cv_styles(doc: Any, ch: Charte) -> None:
    """Ajoute ou met à jour les styles « CV … » reconnus par CVMatcher, aux couleurs et polices de la charte."""
    normal = doc.styles["Normal"]
    names = {s.name for s in doc.styles}
    for name, (heading, size, color, bold, italic, align, before, after, indent, first) in CV_STYLES.items():
        style = doc.styles[name] if name in names else doc.styles.add_style(name, WD_STYLE_TYPE.PARAGRAPH)
        style.base_style = normal
        style.quick_style = True  # visible dans la galerie des styles de Word
        font(style, ch.titres if heading else ch.texte, size, ch.c[color], bold=bold, italic=italic)
        pf = style.paragraph_format
        pf.alignment = ALIGN[align]
        pf.space_before, pf.space_after = Pt(before), Pt(after)
        pf.left_indent, pf.first_line_indent = Cm(indent), Cm(first)
        pf.line_spacing = 1.0
        pf.keep_with_next = name in KEEP_WITH_NEXT
    border(doc.styles["CV Section"], "bottom", ch.c["tertiaire"], size=6, space=1)


def build_cv(ch: Charte, out: Path, base: Path | None = None) -> Path:
    if base is not None:  # modèle existant de la société : styles et palette seulement
        doc = Document(str(base))
        cv_styles(doc, ch)
        return save(doc, out, ch.palette("cv"))

    c, so = ch.c, ch.societe
    doc = new_document(ch, f"CV — {ch.nom}", ch.texte)
    cv_styles(doc, ch)
    section = doc.sections[0]
    section.top_margin, section.bottom_margin = Cm(2.6), Cm(2)
    usable = section.page_width - section.left_margin - section.right_margin

    # pages suivantes : petit logo, rappel du candidat ; la page 1 porte son propre bloc d'identité
    section.different_first_page_header_footer = True
    head = section.header.paragraphs[0]
    head.paragraph_format.tab_stops.add_tab_stop(usable, WD_TAB_ALIGNMENT.RIGHT)
    logo_or_name(head, ch, ch.logo, 0.8)
    font(head.add_run("\t{prenom} {nom[0]}. — {titre}"), ch.titres, 8.5, c["primaire"], bold=True)
    border(head, "bottom", c["tertiaire"], size=8, space=4)

    def footer(paragraph: Any) -> None:
        paragraph.paragraph_format.tab_stops.add_tab_stop(usable, WD_TAB_ALIGNMENT.RIGHT)
        border(paragraph, "top", c["bordure"], size=4, space=6)
        site = so.get("site", "").removeprefix("https://").removeprefix("http://").rstrip("/")
        font(paragraph.add_run(f"{ch.nom}" + (f" · {site}" if site else "") + " · CV généré le {date} — version "
                               "{version}"), ch.texte, 7.5, c["texteSecondaire"])  # fmt: skip
        font(paragraph.add_run("\tPage "), ch.texte, 7.5, c["texteSecondaire"])
        field(paragraph, "PAGE", ch.texte, c["texteSecondaire"])

    footer(section.footer.paragraphs[0])
    footer(section.first_page_footer.paragraphs[0])

    # ---------------------------------------------------------------- page 1 : bandeau d'identité
    top = first_paragraph(doc)
    top.paragraph_format.tab_stops.add_tab_stop(usable, WD_TAB_ALIGNMENT.RIGHT)
    logo_or_name(top, ch, ch.logo, 1.3)
    if so.get("slogan"):
        font(top.add_run("\t" + so["slogan"]), ch.texte, 8.5, c["texteSecondaire"], italic=True)
    top.paragraph_format.space_after = Pt(18)

    name = doc.add_paragraph()
    name.paragraph_format.space_after = Pt(0)
    font(name.add_run("{prenom} {nom[0]}."), ch.titres, 24, c["primaire"], bold=True)
    title = doc.add_paragraph()
    title.paragraph_format.space_after = Pt(2)
    font(title.add_run("{titre}"), ch.titres, 13, c["secondaire"], bold=True)
    mission = doc.add_paragraph()
    mission.paragraph_format.space_after = Pt(10)
    font(mission.add_run("Proposé pour : {poste} · {client}"), ch.texte, 9, c["texteSecondaire"], italic=True)
    border(mission, "bottom", c["tertiaire"], size=18, space=6)

    # bloc contact de la société (interlocuteur commercial), sur fond clair
    contact = so.get("contact", {})
    lines = [
        (ch.nom, True),
        *[(line, False) for line in so.get("adresse", [])],
        *[(v, False) for v in (contact.get("nom"), contact.get("fonction")) if v],
        *[(v, False) for v in (contact.get("email"), contact.get("telephone") and f"Tél. : {contact['telephone']}")
          if v],
    ]  # fmt: skip
    for i, (text, strong) in enumerate(lines):
        p = doc.add_paragraph()
        pf = p.paragraph_format
        pf.space_before = Pt(6) if i == 0 else Pt(0)
        pf.space_after = Pt(6) if i == len(lines) - 1 else Pt(0)
        pf.left_indent = Cm(0.3)
        shade(p, c["fondClair"])
        font(p.add_run(text), ch.titres if strong else ch.texte, 9.5 if strong else 9,
             c["primaire"] if strong else c["texte"], bold=strong)  # fmt: skip

    # ---------------------------------------------------------------- corps : CVMatcher écrit tout le CV ici
    doc.add_paragraph().paragraph_format.space_after = Pt(6)
    doc.add_paragraph("{corps}")
    return save(doc, out, ch.palette("cv"))


# ====================================================================================== rapports de scoring
def report_styles(doc: Any, ch: Charte, *, analyse: bool) -> None:
    c, st = ch.c, doc.styles
    body = st["Body Text"]
    body.base_style = st["Normal"]
    font(body, ch.texte, 10, c["texte"])
    body.paragraph_format.space_after = Pt(6)
    if analyse:
        body.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY

    h1 = st["Heading 1"]
    font(h1, ch.titres, 16 if analyse else 14, c["primaire"], bold=True)
    h1.font.all_caps = analyse
    pf = h1.paragraph_format
    pf.space_before, pf.space_after, pf.keep_with_next = Pt(18 if analyse else 16), Pt(8 if analyse else 6), True
    if not analyse:
        border(h1, "bottom", c["tertiaire"], size=8, space=2)
    for name, size in (("Heading 2", 12 if analyse else 11), ("Heading 3", 10.5 if analyse else 10)):
        font(st[name], ch.titres, size, c["secondaire"] if analyse else c["primaire"], bold=True)

    bullet = st["List Bullet"]
    font(bullet, ch.texte, 10, c["texte"])
    bullet.paragraph_format.space_after = Pt(2)
    caption = st["Caption"]
    font(caption, ch.texte, 8.5, c["texteSecondaire"], bold=False, italic=True)
    grid = st["Table Grid"]
    font(grid, ch.texte, 8.5, c["texte"])  # tableaux denses (7 colonnes pour l'évaluation par indicateur)
    table_style(grid, c["bordure"], c["zebrure"] if analyse else None)


def build_report(ch: Charte, out: Path) -> Path:
    """Variante « charte » : logo et titre en en-tête, filet de couleur, pied confidentiel."""
    c = ch.c
    doc = new_document(ch, "Rapport de scoring", ch.texte)
    report_styles(doc, ch, analyse=False)
    section = doc.sections[0]
    section.top_margin, section.bottom_margin = Cm(3.2), Cm(2.2)
    usable = section.page_width - section.left_margin - section.right_margin

    top = section.header.paragraphs[0]
    top.paragraph_format.tab_stops.add_tab_stop(usable, WD_TAB_ALIGNMENT.RIGHT)
    logo_or_name(top, ch, ch.logo, 1.1)
    font(top.add_run("\tRAPPORT DE SCORING"), ch.titres, 11, c["primaire"], bold=True)
    sub = section.header.add_paragraph()
    sub.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    sub.paragraph_format.space_after = Pt(0)
    font(sub.add_run("{poste} · {client}"), ch.texte, 8.5, c["texteSecondaire"])
    border(sub, "bottom", c["primaire"], size=12, space=4)

    foot = section.footer.paragraphs[0]
    foot.paragraph_format.tab_stops.add_tab_stop(usable, WD_TAB_ALIGNMENT.RIGHT)
    border(foot, "top", c["bordure"], size=6, space=6)
    font(foot.add_run("Confidentiel · {candidat} · scoring du {date}"), ch.texte, 8, c["texteSecondaire"])
    font(foot.add_run("\tPage "), ch.texte, 8, c["texteSecondaire"])
    field(foot, "PAGE", ch.texte, c["texteSecondaire"])
    font(foot.add_run(" / "), ch.texte, 8, c["texteSecondaire"])
    field(foot, "NUMPAGES", ch.texte, c["texteSecondaire"])
    brand = section.footer.add_paragraph()
    font(brand.add_run(ch.nom), ch.titres, 7.5, c["primaire"], bold=True)

    first_paragraph(doc).text = "{corps}"
    return save(doc, out, ch.palette("charte"))


def build_report_analyse(ch: Charte, out: Path) -> Path:
    """Variante « analyse » : page de garde, puis rapport aux titres en capitales et tableaux zébrés."""
    c = ch.c
    doc = new_document(ch, "Analyse de profil — Scoring de compétences", ch.texte)
    report_styles(doc, ch, analyse=True)
    section = doc.sections[0]
    section.top_margin, section.bottom_margin = Cm(2.2), Cm(2)
    usable = section.page_width - section.left_margin - section.right_margin

    section.different_first_page_header_footer = True
    section.first_page_header.is_linked_to_previous = False
    cover_foot = section.first_page_footer.paragraphs[0]
    cover_foot.alignment = WD_ALIGN_PARAGRAPH.CENTER
    font(cover_foot.add_run(f"Document confidentiel - {ch.nom}"), ch.texte, 8, c["texteSecondaire"])

    border(section.header.paragraphs[0], "bottom", c["bordure"], size=6, space=1)
    foot = section.footer.paragraphs[0]
    foot.paragraph_format.tab_stops.add_tab_stop(usable, WD_TAB_ALIGNMENT.RIGHT)
    font(foot.add_run(f"{{candidat}} - Rapport de Scoring - {ch.nom}"), ch.texte, 8, c["texteSecondaire"])
    font(foot.add_run("\tPage "), ch.texte, 8, c["texteSecondaire"])
    field(foot, "PAGE", ch.texte, c["texteSecondaire"])

    logo = first_paragraph(doc)
    logo_or_name(logo, ch, ch.marque, 2.4)

    def centered(text: str, size: float, color: str, *, bold: bool = False, before: float = 0, after: float = 6):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_before, p.paragraph_format.space_after = Pt(before), Pt(after)
        font(p.add_run(text), ch.titres, size, color, bold=bold)
        return p

    centered("ANALYSE DE PROFIL", 30, c["primaire"], bold=True, before=190, after=10)
    rule = doc.add_paragraph()
    rule.paragraph_format.left_indent = rule.paragraph_format.right_indent = Cm(3)
    rule.paragraph_format.space_after = Pt(8)
    border(rule, "top", c["tertiaire"], size=24, space=1)
    centered("Scoring de Compétences", 16, c["secondaire"], after=24)
    centered("{candidat}", 14, c["primaire"], bold=True)
    centered("{poste} · {client}", 10.5, c["texte"], after=0).add_run().add_break(WD_BREAK.PAGE)

    doc.add_paragraph("{corps}")
    return save(doc, out, ch.palette("analyse"))


# ====================================================================================== programme principal
def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("charte", type=Path, help="charte JSON de la société")
    parser.add_argument("--out", type=Path, help="dossier de sortie (par défaut : celui de la charte)")
    parser.add_argument("--cv-base", type=Path, help="modèle de CV Word existant à habiller")
    args = parser.parse_args(argv)

    ch = Charte(args.charte)
    out = args.out or args.charte.parent
    files = [
        build_cv(ch, out / f"cv.{ch.slug}.docx", args.cv_base),
        build_report(ch, out / f"rapport-scoring.{ch.slug}.docx"),
        build_report_analyse(ch, out / f"rapport-scoring-analyse.{ch.slug}.docx"),
    ]
    print(f"Gabarits générés pour {ch.nom} :")
    for f in files:
        print(f"  {f}")

    print("\nContrastes (WCAG 2.1 ; seuil 4,5:1 pour un texte, 3:1 pour un libellé en gras) :")
    low = 0
    for name, fg, bg, ratio, seuil in ch.contrastes():
        flag = "ok " if ratio >= seuil else "BAS"
        low += ratio < seuil
        print(f"  [{flag}] {name:<48} {fg} sur {bg} : {ratio:4.1f}:1")
    if low:
        print(f"\n{low} couple(s) sous le seuil : assombrissez la couleur concernée dans la charte, ou fixez la couleur "
              "voulue dans sa section « palette ».")  # fmt: skip


if __name__ == "__main__":
    main()
