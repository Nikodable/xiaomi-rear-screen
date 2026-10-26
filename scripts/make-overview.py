#!/usr/bin/env python3
"""Génère docs/overview.png : capture de l'app (docs/app-screenshot.png) + légendes numérotées en anglais.
Pour changer l'image : remplacer docs/app-screenshot.png (même mise en page) puis relancer ce script. Dépend de Pillow."""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
shot = Image.open(os.path.join(ROOT, "docs", "app-screenshot.png")).convert("RGB")

S = 2                                   # sur-échantillonnage pour des traits propres
SCALE = 0.92                            # taille de la capture dans l'illustration
W, H = 1760, 1120
PAD_X, PAD_Y = 50, 40
CROP = (28, 30, 830, 1143)              # fenêtre seule dans la capture d'origine (sans le fond noir du bureau)
LABEL_X = 1010                          # colonne des textes
INK, LINE, WARN, GREY = (28, 28, 30), (59, 111, 212), (200, 40, 40), (90, 90, 96)

def font(size, bold=False):
    path = "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Helvetica.ttc"
    return ImageFont.truetype(path, size * S)

canvas = Image.new("RGB", (W * S, H * S), (255, 255, 255))

# fenêtre : coins arrondis + ombre douce
win = shot.crop(CROP)
ww, wh = int(win.width * SCALE) * S, int(win.height * SCALE) * S
win = win.resize((ww, wh), Image.LANCZOS)
mask = Image.new("L", (ww, wh), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, ww - 1, wh - 1], radius=int(40 * SCALE) * S, fill=255)
shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle(
    [PAD_X * S, (PAD_Y + 10) * S, PAD_X * S + ww, (PAD_Y + 10) * S + wh], radius=int(40 * SCALE) * S, fill=(0, 0, 0, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(14 * S))
canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
canvas.paste(win, (PAD_X * S, PAD_Y * S), mask)
d = ImageDraw.Draw(canvas)

def sx(x): return (PAD_X + (x - CROP[0]) * SCALE) * S
def sy(y): return (PAD_Y + (y - CROP[1]) * SCALE) * S

# (numéro, y de l'élément, x où la flèche le touche [capture d'origine], y du texte [illustration], titre, détail, avertissement ?)
items = [
    (1,  136, 796, 150, "Language",               "French, English, German, Spanish, Italian, Portuguese", False),
    (2,  324, 796, 300, "Phone",                  "Your phone, connected by USB (the refresh button searches again)", False),
    (3,  396, 703, 368, "Screen",                 "Rear screen, front screen, or both screens at once", False),
    (4,  464, 703, 436, "Quality",                "Light / Normal / Max — choose Max for the best result", False),
    (5,  532, 703, 504, "Frame",                  "No frame by default — or show the rear screen inside a phone", False),
    (6,  664, 767, 600, "Live mirror",            "Opens a live window of the selected screen(s)", False),
    (7,  740, 767, 668, "Record",                 "Records to MP4 — one file per screen", False),
    (8,  803, 535, 736, "Mirror while recording", "Untick to record without opening the window", False),
    (9,  855, 560, 804, "HD ×2 (experimental)",   "Sharper rear screen — needs “USB debugging (Security settings)”", False),
    (10, 919, 767, 872, "Photo · Open folder",    "Saves a PNG screenshot · opens the folder with your files", False),
    (11, 1055, 767, 960, "Wi-Fi (optional)",      "USB is more stable for long recordings", True),
]

for n, y, x, ty, title, detail, warn in items:
    col = WARN if warn else LINE
    ey = sy(y); tyy = ty * S
    x0 = sx(x) + 6 * S                       # pointe sur l'élément
    xe = (LABEL_X - 120) * S                 # début du coude
    xb = (LABEL_X - 50) * S                  # bord gauche de la pastille
    d.line([(x0 + 12 * S, ey), (xe, ey), (xb, tyy)], fill=col, width=2 * S, joint="curve")
    d.polygon([(x0, ey), (x0 + 14 * S, ey - 6 * S), (x0 + 14 * S, ey + 6 * S)], fill=col)
    r = 21 * S; cx = (LABEL_X - 28) * S
    d.ellipse([cx - r, tyy - r, cx + r, tyy + r], fill=col)
    f = font(24, True); tw = d.textlength(str(n), font=f)
    d.text((cx - tw / 2, tyy - 15 * S), str(n), font=f, fill=(255, 255, 255))
    d.text((LABEL_X * S, tyy - 30 * S), title, font=font(30, True), fill=WARN if warn else INK)
    d.text((LABEL_X * S, tyy + 4 * S), detail, font=font(24), fill=WARN if warn else GREY)

# titre
d.text((LABEL_X * S, 34 * S), "Rear Screen — quick tour", font=font(40, True), fill=INK)
d.text((LABEL_X * S, 86 * S), "Mirror, record and photograph your phone's rear screen", font=font(26), fill=(90, 90, 96))

out = canvas.resize((W, H), Image.LANCZOS)
out.save(os.path.join(ROOT, "docs", "overview.png"), optimize=True)
print("OK :", out.size)
