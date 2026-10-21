#!/usr/bin/env python3
"""Génère docs/mirror-rear.png : la fenêtre de miroir (docs/captures/mirror-rear.png) avec coins arrondis et ombre, sur fond blanc.
Dépend de Pillow."""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CROP = (18, 20, 1344, 876)      # fenêtre seule, sans le fond noir du bureau
S, PAD, R = 2, 50, 34
raw = Image.open(os.path.join(ROOT, "docs", "captures", "mirror-rear.png")).convert("RGB").crop(CROP)
w, h = raw.size
W, H = w + 2 * PAD, h + 2 * PAD
win = raw.resize((w * S, h * S), Image.LANCZOS)
mask = Image.new("L", win.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, win.width - 1, win.height - 1], radius=R * S, fill=(255))
canvas = Image.new("RGBA", (W * S, H * S), (255, 255, 255, 255))
shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([PAD * S, (PAD + 10) * S, PAD * S + win.width, (PAD + 10) * S + win.height], radius=R * S, fill=(0, 0, 0, 95))
canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(14 * S)))
canvas.paste(win, (PAD * S, PAD * S), mask)
out = canvas.convert("RGB").resize((W, H), Image.LANCZOS)
out.save(os.path.join(ROOT, "docs", "mirror-rear.png"), optimize=True)
print("OK :", out.size)
