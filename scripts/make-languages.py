#!/usr/bin/env python3
"""Génère docs/languages.png : planche des captures de l'app dans les 6 langues (docs/captures/app-<code>.png).
Dépend de Pillow. Pour mettre à jour : remplacer les captures (même cadrage) puis relancer."""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LANGS = [("fr", "Français"), ("en", "English"), ("de", "Deutsch"), ("es", "Español"), ("it", "Italiano"), ("pt", "Português")]
CROP = (28, 30, 830, 1143)       # fenêtre seule (sans le fond noir du bureau)
S = 2
COLS, ROWS = 3, 2
CW = 520                         # largeur d'une fenêtre dans la planche
GAP_X, GAP_Y, PAD, TOP = 50, 36, 60, 120
INK, GREY = (28, 28, 30), (90, 90, 96)

def font(size, bold=False):
    path = "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Helvetica.ttc"
    return ImageFont.truetype(path, size * S)

ch = round((CROP[3] - CROP[1]) * CW / (CROP[2] - CROP[0]))
W = PAD * 2 + COLS * CW + (COLS - 1) * GAP_X
H = TOP + ROWS * (ch + 70) + (ROWS - 1) * GAP_Y + PAD // 2
canvas = Image.new("RGB", (W * S, H * S), (255, 255, 255))
d = ImageDraw.Draw(canvas)
title = "Six languages, one window"
d.text((W * S / 2 - d.textlength(title, font=font(44, True)) / 2, 36 * S), title, font=font(44, True), fill=INK)
sub = "Follows your system language — switch any time from the menu in the top-right corner"
d.text((W * S / 2 - d.textlength(sub, font=font(24)) / 2, 90 * S), sub, font=font(24), fill=GREY)

for i, (code, name) in enumerate(LANGS):
    r, c = divmod(i, COLS)
    x = PAD + c * (CW + GAP_X)
    y = TOP + r * (ch + 70 + GAP_Y)
    win = Image.open(os.path.join(ROOT, "docs", "captures", f"app-{code}.png")).convert("RGB").crop(CROP)
    win = win.resize((CW * S, ch * S), Image.LANCZOS)
    mask = Image.new("L", win.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, win.width - 1, win.height - 1], radius=36 * S, fill=255)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x * S, (y + 8) * S, x * S + win.width, (y + 8) * S + win.height], radius=36 * S, fill=(0, 0, 0, 85))
    shadow = shadow.filter(ImageFilter.GaussianBlur(12 * S))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
    canvas.paste(win, (x * S, y * S), mask)
    d = ImageDraw.Draw(canvas)
    d.text(((x + CW / 2) * S - d.textlength(name, font=font(30, True)) / 2, (y + ch + 18) * S), name, font=font(30, True), fill=INK)

out = canvas.resize((W, H), Image.LANCZOS)
out.save(os.path.join(ROOT, "docs", "languages.png"), optimize=True)
print("OK :", out.size)
