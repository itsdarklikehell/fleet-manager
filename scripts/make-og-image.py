#!/usr/bin/env python3
"""Genereer een social-preview-kaart (1200x630) voor de CV-pagina.

Waarom: og:image wees naar profile.jpg (460x460, vierkant). LinkedIn, X en
WhatsApp croppen naar 1.91:1, dus een vierkant portret wordt afgesneden of
krijgt zwarte balken. Deze kaart heeft de juiste verhouding en toont naam +
tagline + de belangrijkste cijfers.

Gebruik:
    python3 make-og-image.py [--out PAD] [--repos N] [--stars N]

Het portret wordt uit profile.jpg gehaald en rond uitgesneden; als dat
bestand ontbreekt, valt het script terug op initialen.
"""

import argparse
import json
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("PIL ontbreekt — installeer pillow", file=sys.stderr)
    sys.exit(1)

W, H = 1200, 630
BG = (13, 17, 23)
CARD = (22, 27, 34)
ACCENT = (78, 205, 196)
ACCENT2 = (255, 149, 0)
TEXT = (230, 237, 243)
MUTED = (176, 186, 196)
BORDER = (48, 54, 61)

REPO_DIR = os.environ.get(
    "RPG_REPO_DIR", os.path.expanduser("~/.hermes/cache/scratch/itsdarklikehell-my-resume")
)


def font(size, bold=False):
    """Eerste beschikbare font, met DejaVu als vangnet."""
    kandidaten = []
    if bold:
        kandidaten = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        ]
    else:
        kandidaten = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        ]
    for p in kandidaten:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def lees_stats(repo_dir):
    """Haal de cijfers uit github-data.json; None als het niet lukt."""
    try:
        with open(os.path.join(repo_dir, "github-data.json")) as f:
            d = json.load(f)
        inner = d["stats"]["stats"]
        return {
            "repos": inner.get("own_repos", inner.get("total_repos", 0)),
            "stars": inner.get("own_stars", inner.get("total_stars", 0)),
            "langs": inner.get("languages", 0),
        }
    except Exception:
        return None


def maak_portret(size):
    """Rond uitgesneden portret uit profile.jpg, of None."""
    p = os.path.join(REPO_DIR, "profile.jpg")
    if not os.path.exists(p):
        return None
    try:
        img = Image.open(p).convert("RGBA")
        # Vierkant uitsnijden vanuit het midden
        z = min(img.size)
        left = (img.width - z) // 2
        top = (img.height - z) // 2
        img = img.crop((left, top, left + z, top + z)).resize((size, size), Image.LANCZOS)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, size, size), fill=255)
        img.putalpha(mask)
        return img
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(REPO_DIR, "og-image.png"))
    ap.add_argument("--repos", type=int)
    ap.add_argument("--stars", type=int)
    ap.add_argument("--langs", type=int)
    args = ap.parse_args()

    stats = lees_stats(REPO_DIR) or {"repos": 0, "stars": 0, "langs": 0}
    repos = args.repos if args.repos is not None else stats["repos"]
    stars = args.stars if args.stars is not None else stats["stars"]
    langs = args.langs if args.langs is not None else stats["langs"]

    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # Achtergrondaccent links
    for i in range(6):
        d.rectangle([0, i * (H // 6), 8, (i + 1) * (H // 6)], fill=ACCENT)

    # Portret
    AV = 190
    portret = maak_portret(AV)
    px, py = 90, (H - AV) // 2
    if portret:
        img.paste(portret, (px, py), portret)
    else:
        d.ellipse([px, py, px + AV, py + AV], fill=CARD, outline=ACCENT, width=3)
        f = font(72, bold=True)
        tb = d.textbbox((0, 0), "BM", font=f)
        d.text(
            (px + (AV - (tb[2] - tb[0])) / 2, py + (AV - (tb[3] - tb[1])) / 2 - 8),
            "BM", font=f, fill=ACCENT,
        )

    # Tekstkolom
    tx = px + AV + 60

    f_naam = font(58, bold=True)
    d.text((tx, 120), "Bauke Molenaar", font=f_naam, fill=TEXT)

    f_tag = font(27)
    d.text((tx, 196), "Technisch professional · ICT & Security", font=f_tag, fill=ACCENT)

    f_sub = font(24)
    d.text((tx, 236), "Shell/Bash · Python · JavaScript · Linux", font=f_sub, fill=MUTED)

    # Cijferkaarten
    f_num = font(46, bold=True)
    f_lbl = font(20)
    kaarten = [("Projecten", repos), ("Sterren", stars), ("Talen", langs)]
    cw, ch, gap = 250, 112, 24
    cy = 320
    for i, (label, val) in enumerate(kaarten):
        cx = tx + i * (cw + gap)
        d.rounded_rectangle([cx, cy, cx + cw, cy + ch], radius=12, fill=CARD, outline=BORDER, width=1)
        vs = str(val)
        vb = d.textbbox((0, 0), vs, font=f_num)
        d.text((cx + (cw - (vb[2] - vb[0])) / 2, cy + 14), vs, font=f_num, fill=ACCENT2)
        lb = d.textbbox((0, 0), label, font=f_lbl)
        d.text((cx + (cw - (lb[2] - lb[0])) / 2, cy + 72), label, font=f_lbl, fill=MUTED)

    # Onderregel
    f_url = font(22)
    d.text((tx, 470), "itsdarklikehell.github.io/my-resume", font=f_url, fill=MUTED)
    d.ellipse([tx, 512, tx + 10, 512 + 10], fill=ACCENT)
    d.text((tx + 22, 503), "github.com/itsdarklikehell", font=f_url, fill=MUTED)

    img.save(args.out, "PNG", optimize=True)
    print(f"✅ {args.out} ({os.path.getsize(args.out)/1024:.0f} KB, {W}x{H})")
    print(f"   projecten={repos} sterren={stars} talen={langs}")


if __name__ == "__main__":
    main()
