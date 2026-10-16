#!/usr/bin/env python3
"""Génère l'icône de l'app (original, sans image tierce) : macos/icon/AppIcon.icns, windows/icon.ico, docs/icon.png.
Dépend de Pillow ; la conversion .icns utilise `iconutil` (macOS)."""
import os, shutil, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
S = 4                       # sur-échantillonnage
N = 1024 * S

def rr(d, box, r, **kw):
    d.rounded_rectangle([v * S for v in box], radius=r * S, **kw)

def gradient(size, c1, c2):
    g = Image.new("RGB", (size, size))
    px = g.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return g

def make():
    body = 824 * S
    # fond : dégradé indigo → violet dans un carré arrondi (gabarit macOS : 824 px centrés)
    bg = gradient(body // 4, (0x4F, 0x5B, 0xF0), (0x9B, 0x5C, 0xF6)).resize((body, body), Image.BICUBIC)
    mask = Image.new("L", (N, N), 0)
    rr(ImageDraw.Draw(mask), (100, 100, 924, 924), 185, fill=255)
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    canvas.paste(bg, (100 * S, 100 * S))
    canvas.putalpha(mask)

    # reflet « verre » en haut du fond
    gloss = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse([-200 * S, -520 * S, 1224 * S, 400 * S], fill=(255, 255, 255, 38))
    gloss.putalpha(Image.composite(gloss.getchannel("A"), Image.new("L", (N, N), 0), mask))
    canvas = Image.alpha_composite(canvas, gloss)

    # ombre douce du téléphone
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    rr(ImageDraw.Draw(shadow), (352, 232, 692, 842), 78, fill=(20, 10, 70, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(26 * S))
    canvas = Image.alpha_composite(canvas, shadow)

    d = ImageDraw.Draw(canvas)
    # dos du téléphone (verre clair)
    rr(d, (342, 212, 682, 812), 78, fill=(246, 247, 255, 255))
    rr(d, (352, 222, 672, 802), 70, outline=(255, 255, 255, 255), width=6, fill=(236, 238, 252, 255))
    # îlot caméra, avec l'écran arrière dedans
    rr(d, (372, 252, 652, 452), 56, fill=(34, 36, 70, 255))
    rr(d, (392, 272, 632, 432), 40, fill=(70, 84, 214, 255))          # écran arrière allumé
    d.polygon([(486 * S, 318 * S), (486 * S, 386 * S), (544 * S, 352 * S)], fill=(255, 255, 255, 255))  # ▶
    # deux objectifs sous l'îlot
    for cx, cy in ((432, 506), (432, 580)):
        d.ellipse([(cx - 26) * S, (cy - 26) * S, (cx + 26) * S, (cy + 26) * S], fill=(34, 36, 70, 255))
        d.ellipse([(cx - 11) * S, (cy - 11) * S, (cx + 11) * S, (cy + 11) * S], fill=(120, 130, 235, 255))
    return canvas.resize((1024, 1024), Image.LANCZOS)

def main():
    icon = make()
    docs = os.path.join(ROOT, "docs"); os.makedirs(docs, exist_ok=True)
    icon.save(os.path.join(docs, "icon.png"))
    # Windows : on retire la marge du gabarit macOS
    icon.crop((100, 100, 924, 924)).save(os.path.join(ROOT, "windows", "icon.ico"),
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    # macOS : .icns via iconutil
    if shutil.which("iconutil"):
        iset = os.path.join(ROOT, "macos", "icon", "AppIcon.iconset")
        shutil.rmtree(iset, ignore_errors=True); os.makedirs(iset)
        for s in (16, 32, 128, 256, 512):
            icon.resize((s, s), Image.LANCZOS).save(os.path.join(iset, f"icon_{s}x{s}.png"))
            icon.resize((s * 2, s * 2), Image.LANCZOS).save(os.path.join(iset, f"icon_{s}x{s}@2x.png"))
        subprocess.run(["iconutil", "-c", "icns", iset, "-o", os.path.join(ROOT, "macos", "icon", "AppIcon.icns")], check=True)
        shutil.rmtree(iset)
    else:
        print("iconutil introuvable : AppIcon.icns non régénéré", file=sys.stderr)
    print("OK")

main()
