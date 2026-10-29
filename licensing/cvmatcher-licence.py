#!/usr/bin/env python3
"""Émission des licences CVMatcher (SFG §11.3, spec de déploiement §4.1 étape 1 et §7).

    keygen  --out-dir <coffre>                      paire Ed25519 ; la clé privée va au coffre, jamais dans un dépôt
    pubkey  --key <privée.pem>                      clé publique PEM à reporter dans TRUSTED_PUBLIC_KEYS (cvmatcher)
    sign    --key <privée.pem> --customer … --domain … --expires AAAA-MM-JJ --seats rôle=n,…
            [--cv-quota n] [--features mcp,a2a] --out <fichier.lic>
    verify  --pub <publique.pem> <fichier.lic>

Format identique à `cvmatcher/server/cvmatcher/admin/licence.py` : enveloppe JSON
`{format, version, alg, kid, issuedAt, licence, sig}`, signature Ed25519 sur le JSON canonique (clés triées,
séparateurs compacts) de tous les champs sauf `sig` ; `kid` = 16 premiers hex du SHA-256 de la clé publique DER.
Dépendance : `cryptography` (pip install cryptography).
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import sys
from datetime import UTC, date, datetime
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

FORMAT, VERSION, ALG = "cvmatcher-licence", 1, "Ed25519"
ROLES = {"administrator", "steward", "recruiter", "business_manager", "visitor"}
FEATURES = {"mcp", "mcp.write", "a2a"}
REPO_ROOT = Path(__file__).resolve().parents[1]


def _canonical(envelope: dict) -> bytes:
    body = {k: envelope[k] for k in ("format", "version", "alg", "kid", "issuedAt", "licence") if k in envelope}
    return json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def key_id(public_key: Ed25519PublicKey) -> str:
    der = public_key.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return hashlib.sha256(der).hexdigest()[:16]


def _outside_repo(path: Path) -> Path:
    """La clé privée ne doit jamais se trouver dans ce dépôt (spec §7)."""
    resolved = path.resolve()
    if resolved == REPO_ROOT or REPO_ROOT in resolved.parents:
        sys.exit(f"refus : {path} est dans le dépôt CVMatcher-Deploy ; la clé privée reste dans le coffre")
    return resolved


def load_private(path: str) -> Ed25519PrivateKey:
    data = _outside_repo(Path(path)).read_bytes()
    key = serialization.load_pem_private_key(data, password=None)
    if not isinstance(key, Ed25519PrivateKey):
        sys.exit("la clé n'est pas une clé Ed25519")
    return key


def parse_seats(spec: str) -> dict[str, int]:
    seats: dict[str, int] = {}
    for item in filter(None, (s.strip() for s in spec.split(","))):
        role, _, n = item.partition("=")
        if role not in ROLES:
            sys.exit(f"rôle inconnu : {role} (attendus : {', '.join(sorted(ROLES))})")
        seats[role] = int(n)  # -1 = illimité
        if seats[role] < -1:
            sys.exit(f"nombre de comptes invalide pour {role}")
    if seats.get("administrator", 0) == 0:
        sys.exit("au moins un compte administrator est requis")
    return seats


def sign(document: dict, key: Ed25519PrivateKey) -> dict:
    envelope = {
        "format": FORMAT,
        "version": VERSION,
        "alg": ALG,
        "kid": key_id(key.public_key()),
        "issuedAt": datetime.now(UTC).isoformat(timespec="seconds"),
        "licence": document,
    }
    envelope["sig"] = base64.b64encode(key.sign(_canonical(envelope))).decode("ascii")
    return envelope


def verify(envelope: dict, public: Ed25519PublicKey) -> dict:
    if envelope.get("format") != FORMAT or envelope.get("version") != VERSION or envelope.get("alg") != ALG:
        raise ValueError("format de licence inattendu")
    if envelope.get("kid") != key_id(public):
        raise ValueError(f"licence signée par la clé {envelope.get('kid')}, pas par {key_id(public)}")
    try:
        public.verify(base64.b64decode(envelope["sig"]), _canonical(envelope))
    except InvalidSignature as e:
        raise ValueError("signature invalide") from e
    return envelope["licence"]


def cmd_keygen(args: argparse.Namespace) -> None:
    out = _outside_repo(Path(args.out_dir))
    out.mkdir(parents=True, exist_ok=True)
    key = Ed25519PrivateKey.generate()
    priv = out / "cvmatcher-licence-signing.pem"
    pub = out / "cvmatcher-licence-public.pem"
    if priv.exists():
        sys.exit(f"refus : {priv} existe déjà")
    priv.write_bytes(
        key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    )
    priv.chmod(0o600)
    pub.write_bytes(key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
    print(f"clé privée : {priv} (à verser au coffre puis à effacer du poste)")
    print(f"clé publique : {pub} (kid {key_id(key.public_key())}) à ajouter à TRUSTED_PUBLIC_KEYS de cvmatcher")


def cmd_pubkey(args: argparse.Namespace) -> None:
    key = load_private(args.key)
    sys.stdout.write(key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode())
    print(f"# kid {key_id(key.public_key())}")


def cmd_sign(args: argparse.Namespace) -> None:
    expires = date.fromisoformat(args.expires)
    if expires <= date.today():
        sys.exit("date d'expiration passée")
    doc: dict = {
        "customer": args.customer,
        "domain": args.domain.lower(),
        "expires": expires.isoformat(),
        "seats": parse_seats(args.seats),
    }
    if args.cv_quota is not None:
        doc["cvMonthlyQuota"] = args.cv_quota
    if args.features:
        feats = sorted(set(filter(None, args.features.split(","))))
        unknown = set(feats) - FEATURES
        if unknown:
            sys.exit(f"fonctions inconnues : {', '.join(sorted(unknown))}")
        if "mcp.write" in feats and "mcp" not in feats:
            sys.exit("mcp.write exige mcp")
        doc["features"] = feats
    envelope = sign(doc, load_private(args.key))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(envelope, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"licence écrite : {out} (kid {envelope['kid']}, {doc['domain']}, expire le {doc['expires']})")


def cmd_verify(args: argparse.Namespace) -> None:
    public = serialization.load_pem_public_key(Path(args.pub).read_bytes())
    if not isinstance(public, Ed25519PublicKey):
        sys.exit("la clé publique n'est pas une clé Ed25519")
    try:
        doc = verify(json.loads(Path(args.licence).read_text(encoding="utf-8")), public)
    except ValueError as e:
        sys.exit(f"licence refusée : {e}")
    print(json.dumps(doc, ensure_ascii=False, indent=2))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    k = sub.add_parser("keygen")
    k.add_argument("--out-dir", required=True)
    k.set_defaults(func=cmd_keygen)
    pk = sub.add_parser("pubkey")
    pk.add_argument("--key", required=True)
    pk.set_defaults(func=cmd_pubkey)
    s = sub.add_parser("sign")
    s.add_argument("--key", required=True)
    s.add_argument("--customer", required=True)
    s.add_argument("--domain", required=True)
    s.add_argument("--expires", required=True)
    s.add_argument("--seats", required=True, help="administrator=2,recruiter=10,visitor=-1")
    s.add_argument("--cv-quota", type=int)
    s.add_argument("--features", default="")
    s.add_argument("--out", required=True)
    s.set_defaults(func=cmd_sign)
    v = sub.add_parser("verify")
    v.add_argument("--pub", required=True)
    v.add_argument("licence")
    v.set_defaults(func=cmd_verify)
    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
