#!/usr/bin/env python3
"""Dessine un cadre de téléphone ORIGINAL (dos du téléphone + îlot caméra) avec une zone transparente pour l'écran arrière.
Sorties : docs/frame/phone-frame.png (RGBA, trou transparent), docs/frame/phone-frame.json (position de l'écran), docs/frame/preview.png.
Tout est dessiné en code : aucun pixel d'une image Xiaomi/Leica n'est utilisé. Dépend de Pillow."""
import json, math, os
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "docs", "frame"); os.makedirs(OUT, exist_ok=True)
S = 2                                            # sur-échantillonnage
W, H = 1000, 1400

# géométrie (px de l'image finale) — l'écran arrière est 976×596 (rapport 1,6376)
SCR_W = 740; SCR_H = round(SCR_W * 596 / 976)    # 452
SCR_X, SCR_Y, SCR_R = 130, 196, 77       # rayon des coins = celui de l'écran réel (101 px pour 976 de large)
BEZEL = 17                                       # bordure noire autour de l'écran
ISL_M = 32                                       # marge de l'îlot autour de l'écran
BODY = (48, 108, 952, 1500)                      # dos du téléphone (déborde en bas)

def box(x0, y0, x1, y1): return [round(v * S) for v in (x0, y0, x1, y1)]
def new(): return Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
def lerp(a, b, t): return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def vgrad_rrect(bx, stops, radius):
    x0, y0, x1, y1 = box(*bx); w, h = x1 - x0, y1 - y0
    g = Image.new("RGB", (w, h)); d = ImageDraw.Draw(g)
    for y in range(h):
        t = y / max(h - 1, 1)
        for i in range(len(stops) - 1):
            (t0, c0), (t1, c1) = stops[i], stops[i + 1]
            if t0 <= t <= t1:
                d.line([(0, y), (w, y)], fill=lerp(c0, c1, (t - t0) / (t1 - t0))); break
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius * S, fill=255)
    layer = new(); layer.paste(g.convert("RGBA"), (x0, y0), m)
    return layer

def radial(cx, cy, r, inner, outer, power=1.0):
    """disque à dégradé radial (couleurs RGB), centré en (cx, cy) de rayon r — coordonnées image finale."""
    n = round(2 * r * S); img = Image.new("RGBA", (n, n), (0, 0, 0, 0)); px = img.load()
    c = n / 2
    for y in range(n):
        for x in range(n):
            dd = math.hypot(x - c, y - c) / c
            if dd <= 1:
                px[x, y] = lerp(inner, outer, dd ** power) + (255,)
    layer = new(); layer.alpha_composite(img, (round((cx - r) * S), round((cy - r) * S)))
    return layer

canvas = new()
ox0, oy0, ox1, oy1 = SCR_X - ISL_M, SCR_Y - ISL_M, SCR_X + SCR_W + ISL_M, SCR_Y + SCR_H + ISL_M
ISL = (ox0, oy0, ox1, oy1)

# ── ombre portée sous l'îlot ──
sh = new(); ImageDraw.Draw(sh).rounded_rectangle(box(ISL[0] + 8, ISL[1] + 22, ISL[2] - 8, ISL[3] + 26), radius=90 * S, fill=(0, 0, 0, 140))
canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(20 * S)))

# ── dos : graphite satiné, grain fin, bord clair en haut, fondu en bas ──
body = vgrad_rrect(BODY, [(0.0, (118, 122, 130)), (0.30, (92, 96, 104)), (0.65, (58, 61, 67)), (1.0, (30, 32, 36))], 150)
grain = Image.effect_noise(body.size, 18).convert("RGB")
rgb = Image.blend(body.convert("RGB"), grain, 0.05); a0 = body.getchannel("A")
body = rgb.convert("RGBA"); body.putalpha(a0)
edge = new(); ImageDraw.Draw(edge).rounded_rectangle(box(*BODY), radius=150 * S, outline=(214, 219, 228, 255), width=3 * S)
vm = Image.new("L", edge.size, 0); vp = vm.load()
for y in range(edge.size[1]):
    v = max(0, 255 - round(255 * (y / (900 * S)))) if y < 900 * S else 0
    for x in range(0, edge.size[0], 1): vp[x, y] = v
ea = ImageChops.multiply(edge.getchannel("A"), vm); edge.putalpha(ea)
inner = new(); ImageDraw.Draw(inner).rounded_rectangle(box(BODY[0] + 4, BODY[1] + 4, BODY[2] - 4, BODY[3] - 4), radius=146 * S, outline=(26, 28, 32, 170), width=2 * S)
body = Image.alpha_composite(Image.alpha_composite(body, inner), edge)
gl = new(); ImageDraw.Draw(gl).polygon([(150 * S, 110 * S), (560 * S, 110 * S), (300 * S, 1500 * S), (60 * S, 1500 * S)], fill=(255, 255, 255, 9))
body = Image.alpha_composite(body, gl.filter(ImageFilter.GaussianBlur(34 * S)))
fade = Image.new("L", body.size, 255); fp = fade.load(); y0f = 840 * S
for y in range(y0f, H * S):
    t = (y - y0f) / (H * S - y0f); t = t * t * (3 - 2 * t)
    v = round(255 * (1 - t))
    for x in range(body.size[0]): fp[x, y] = v
body.putalpha(ImageChops.multiply(body.getchannel("A"), fade))
canvas = Image.alpha_composite(canvas, body)

# ── boutons latéraux : deux à gauche (volume), un petit à droite (marche) ──
btn = new(); d = ImageDraw.Draw(btn)
for (x0, x1, y0, y1) in ((36, 50, 458, 612), (36, 50, 650, 748), (950, 964, 590, 640)):
    d.rounded_rectangle(box(x0, y0, x1, y1), radius=7 * S, fill=(70, 74, 82, 255), outline=(150, 156, 168, 255), width=2 * S)
canvas = Image.alpha_composite(canvas, btn)

# ── îlot : même matière, un peu plus clair, arête lumineuse, sillon sombre ──
isl = vgrad_rrect(ISL, [(0.0, (122, 126, 134)), (1.0, (84, 88, 96))], 94)
ring = new(); d = ImageDraw.Draw(ring)
d.rounded_rectangle(box(*ISL), radius=94 * S, outline=(208, 213, 223, 255), width=3 * S)
d.rounded_rectangle(box(ISL[0] + 6, ISL[1] + 6, ISL[2] - 6, ISL[3] - 6), radius=88 * S, outline=(24, 26, 30, 255), width=4 * S)
canvas = Image.alpha_composite(Image.alpha_composite(canvas, isl), ring)

# ── bordure noire de l'écran puis trou transparent ──
bz = new(); ImageDraw.Draw(bz).rounded_rectangle(box(SCR_X - BEZEL, SCR_Y - BEZEL, SCR_X + SCR_W + BEZEL, SCR_Y + SCR_H + BEZEL), radius=(SCR_R + BEZEL) * S, fill=(6, 6, 8, 255))
canvas = Image.alpha_composite(canvas, bz)
hole = Image.new("L", canvas.size, 255)
ImageDraw.Draw(hole).rounded_rectangle(box(SCR_X, SCR_Y, SCR_X + SCR_W, SCR_Y + SCR_H), radius=SCR_R * S, fill=0)
canvas.putalpha(ImageChops.multiply(canvas.getchannel("A"), hole))

# ── objectifs : verre noir brillant, petite lentille centrale ──
def lens(cx, cy, r, periscope=False):
    global canvas
    canvas = Image.alpha_composite(canvas, radial(cx, cy, r + 4, (58, 60, 68), (40, 42, 48), 1))                 # anneau
    canvas = Image.alpha_composite(canvas, radial(cx, cy, r, (30, 31, 38), (9, 9, 12), 1.6))                      # verre
    L = new(); d = ImageDraw.Draw(L)
    d.ellipse(box(cx - r * 0.86, cy - r * 0.86, cx + r * 0.86, cy + r * 0.86), outline=(44, 46, 54, 255), width=2 * S)
    canvas = Image.alpha_composite(canvas, L)
    if periscope:                                   # logement rectangulaire du second objectif
        hw, hh = r * 0.40, r * 0.70
        L = new(); d = ImageDraw.Draw(L)
        d.rounded_rectangle(box(cx - hw, cy - hh, cx + hw, cy + hh), radius=int(hw * 0.7) * S, fill=(10, 11, 14, 255), outline=(66, 68, 78, 255), width=2 * S)
        canvas = Image.alpha_composite(canvas, L)
    ri = r * (0.33 if periscope else 0.24)
    canvas = Image.alpha_composite(canvas, radial(cx, cy, ri + 3, (74, 76, 88), (28, 30, 38), 1))
    canvas = Image.alpha_composite(canvas, radial(cx, cy, ri, (78, 92, 178), (8, 10, 24), 0.9))
    canvas = Image.alpha_composite(canvas, radial(cx, cy, ri * 0.42, (20, 22, 44), (8, 9, 18), 1))
    L = new(); d = ImageDraw.Draw(L)
    d.ellipse(box(cx - ri * 0.55, cy - ri * 0.62, cx - ri * 0.10, cy - ri * 0.22), fill=(255, 255, 255, 120))
    d.arc(box(cx - ri * 0.9, cy - ri * 0.9, cx + ri * 0.9, cy + ri * 0.9), 200, 300, fill=(150, 130, 255, 110), width=2 * S)
    canvas = Image.alpha_composite(canvas, L.filter(ImageFilter.GaussianBlur(0.6 * S)))
lx = SCR_X + 0.165 * SCR_W
lens(lx, SCR_Y + 0.247 * SCR_H, 96)
lens(lx, SCR_Y + 0.745 * SCR_H, 96, periscope=True)

# ── sous l'îlot : capsule (objectif + capteurs) et flash métallique ──
by = SCR_Y + SCR_H                                # bas de l'écran
px0, px1, py0, py1 = 158, 326, by + 84, by + 154
cap = new(); d = ImageDraw.Draw(cap)
d.rounded_rectangle(box(px0, py0, px1, py1), radius=35 * S, fill=(9, 9, 11, 255), outline=(52, 54, 62, 255), width=3 * S)
for cx in (px1 - 66, px1 - 34):
    d.ellipse(box(cx - 9, (py0 + py1) / 2 - 9, cx + 9, (py0 + py1) / 2 + 9), fill=(22, 24, 30, 255), outline=(36, 38, 46, 255), width=2 * S)
canvas = Image.alpha_composite(canvas, cap)
ccx, ccy = px0 + 36, (py0 + py1) / 2
canvas = Image.alpha_composite(canvas, radial(ccx, ccy, 25, (34, 36, 44), (14, 15, 19), 1))
canvas = Image.alpha_composite(canvas, radial(ccx, ccy, 15, (84, 98, 180), (10, 12, 26), 0.9))
L = new(); ImageDraw.Draw(L).ellipse(box(ccx - 8, ccy - 10, ccx - 2, ccy - 4), fill=(255, 255, 255, 140)); canvas = Image.alpha_composite(canvas, L)
fx, fy, fr = 374, (py0 + py1) / 2, 31
canvas = Image.alpha_composite(canvas, radial(fx, fy, fr + 4, (120, 124, 134), (70, 74, 84), 1))
canvas = Image.alpha_composite(canvas, radial(fx, fy, fr, (244, 236, 214), (178, 168, 146), 1.2))
L = new(); d = ImageDraw.Draw(L)
for k in range(48):                                # stries du métal brossé
    ang = k * math.tau / 48
    d.line([(fx * S, fy * S), ((fx + math.cos(ang) * fr) * S, (fy + math.sin(ang) * fr) * S)], fill=(255, 255, 255, 34 if k % 2 else 0), width=2)
d.ellipse(box(fx - 7, fy - 7, fx + 7, fy + 7), fill=(255, 250, 236, 200))
canvas = Image.alpha_composite(canvas, L)

frame = canvas.resize((W, H), Image.LANCZOS)
frame.save(os.path.join(OUT, "phone-frame.png"), optimize=True)
json.dump({"name": "Default", "width": W, "height": H, "background": "transparent",
           "screen": {"x": SCR_X, "y": SCR_Y, "w": SCR_W, "h": SCR_H, "radius": SCR_R},
           "note": "Zone transparente = écran arrière (976x596). Les objectifs recouvrent la zone caméra à gauche."},
          open(os.path.join(OUT, "phone-frame.json"), "w"), indent=2)

# ── aperçu : contenu d'exemple derrière le trou ──
bg = Image.new("RGB", (W, H), (0, 0, 0))
scr = Image.new("RGB", (SCR_W, SCR_H)); sp = scr.load()
for y in range(SCR_H):
    for x in range(SCR_W):
        t = (x / SCR_W * 0.6 + y / SCR_H * 0.4)
        sp[x, y] = (round(84 + 70 * t), round(96 + 46 * t), round(238 - 34 * t))
dd = ImageDraw.Draw(scr)
try: f = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 120)
except Exception: f = ImageFont.load_default()
dd.text((SCR_W - 20 - dd.textlength("21:33", font=f), 30), "21:33", font=f, fill=(255, 255, 255))
bgmask = Image.new("L", (SCR_W, SCR_H), 0); ImageDraw.Draw(bgmask).rounded_rectangle([0, 0, SCR_W - 1, SCR_H - 1], radius=SCR_R, fill=255)
bg.paste(scr, (SCR_X, SCR_Y), bgmask)
Image.alpha_composite(bg.convert("RGBA"), frame).convert("RGB").save(os.path.join(OUT, "preview.png"), optimize=True)
print("OK", frame.size, "écran", (SCR_X, SCR_Y, SCR_W, SCR_H))
