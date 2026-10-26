#!/usr/bin/env python3
"""Transforme une image de téléphone (rendu, photo…) en cadre utilisable par Rear Screen.

Tu donnes la position de l'écran dans l'image ; l'outil découpe cette zone (elle devient transparente) et écrit :
    frame.png   image RGBA avec le trou transparent
    frame.json  position de l'écran, taille, fond
    preview.png aperçu avec un contenu d'exemple derrière le trou
dans TON dossier personnel (jamais dans le dépôt) :
    macOS    ~/Library/Application Support/Rear Screen/frames/<nom>/
    Windows  %APPDATA%\\RearScreen\\frames\\<nom>\\
    Linux    ~/.local/share/rear-screen/frames/<nom>/
Rear Screen détecte automatiquement les cadres de ce dossier (menu « Cadre »).

Exemples
    # 1) repérer les coordonnées : écrit une image quadrillée
    make-custom-frame.py rendu.webp --grid
    #    ou détecter l'écran à partir de la couleur de son fond d'écran
    make-custom-frame.py rendu.webp --detect-color 120,110,240

    # 2) créer le cadre : écran en (160,125), 1060×650, coins arrondis de 70 px,
    #    et on garde les deux objectifs visibles par-dessus l'écran
    make-custom-frame.py rendu.webp --screen 160,125,1060,650 --radius 70 --name mon-cadre \\
        --keep-ellipse 323,288,138,138 --keep-ellipse 323,610,138,138

Les images de marque (rendus Xiaomi, etc.) restent dans ton dossier personnel : ne les ajoute pas au dépôt.
Dépend de Pillow.
"""
import argparse, json, os, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCREEN_RATIO = 976 / 596          # écran arrière du Xiaomi 18 Pro Max
SS = 4                            # sur-échantillonnage du masque (bords lisses)


def personal_dir():
    if sys.platform == "darwin":
        return os.path.expanduser("~/Library/Application Support/Rear Screen/frames")
    if os.name == "nt":
        return os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "RearScreen", "frames")
    return os.path.expanduser("~/.local/share/rear-screen/frames")


def ints(text, n, what):
    try:
        v = [float(x) for x in text.split(",")]
    except ValueError:
        sys.exit(f"{what} : « {text} » n'est pas une liste de nombres")
    if len(v) != n:
        sys.exit(f"{what} : {n} valeurs attendues (reçu {len(v)})")
    return v


def font(size):
    for p in ("/System/Library/Fonts/Helvetica.ttc", "/System/Library/Fonts/Supplemental/Arial.ttf",
              "C:\\Windows\\Fonts\\arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            pass
    return ImageFont.load_default()


def write_grid(img, out_dir):
    """image quadrillée avec les coordonnées en pixels, pour lire la position de l'écran."""
    g = img.convert("RGB").copy()
    d = ImageDraw.Draw(g, "RGBA")
    step = 50 if max(g.size) <= 1200 else 100
    f = font(max(14, g.width // 90))
    for x in range(0, g.width, step):
        major = x % (step * 2) == 0
        d.line([(x, 0), (x, g.height)], fill=(255, 40, 40, 150 if major else 70), width=1)
        if major:
            d.text((x + 3, 3), str(x), font=f, fill=(255, 255, 0, 255), stroke_width=2, stroke_fill=(0, 0, 0, 255))
    for y in range(0, g.height, step):
        major = y % (step * 2) == 0
        d.line([(0, y), (g.width, y)], fill=(255, 40, 40, 150 if major else 70), width=1)
        if major:
            d.text((3, y + 3), str(y), font=f, fill=(255, 255, 0, 255), stroke_width=2, stroke_fill=(0, 0, 0, 255))
    path = os.path.join(out_dir, "grid.png")
    g.save(path)
    return path


def remove_background(img, tol):
    """Rend transparent le fond uni connecté aux bords (remplissage par diffusion depuis les bords), avec un bord adouci."""
    w, h = img.size
    px = img.load()
    edge = [px[x, 0][:3] for x in range(0, w, 7)] + [px[x, h - 1][:3] for x in range(0, w, 7)] \
         + [px[0, y][:3] for y in range(0, h, 7)] + [px[w - 1, y][:3] for y in range(0, h, 7)]
    base = max(set(edge), key=edge.count)                       # couleur dominante des bords
    def close(c): return max(abs(c[0] - base[0]), abs(c[1] - base[1]), abs(c[2] - base[2])) <= tol
    seen = bytearray(w * h)
    stack = []
    for x in range(w):
        stack += [(x, 0), (x, h - 1)]
    for y in range(h):
        stack += [(0, y), (w - 1, y)]
    n = 0
    while stack:
        x, y = stack.pop()
        i = y * w + x
        if seen[i] or not close(px[x, y]):
            continue
        seen[i] = 1; n += 1
        if x > 0: stack.append((x - 1, y))
        if x < w - 1: stack.append((x + 1, y))
        if y > 0: stack.append((x, y - 1))
        if y < h - 1: stack.append((x, y + 1))
    mask = Image.frombytes("L", (w, h), bytes(255 if v else 0 for v in seen)).filter(ImageFilter.GaussianBlur(0.9))
    out = img.copy()
    out.putalpha(ImageChops.multiply(out.getchannel("A"), mask.point(lambda v: 255 - v)))
    print(f"fond retiré : {n * 100 // (w * h)} % de l'image (couleur de fond {base})")
    return out


def main():
    ap = argparse.ArgumentParser(description="Crée un cadre Rear Screen à partir d'une image de téléphone.",
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    ap.add_argument("image", help="image du téléphone (png, jpg, webp…)")
    ap.add_argument("--screen", help="position de l'écran dans l'image : X,Y,LARGEUR,HAUTEUR (en pixels)")
    ap.add_argument("--radius", type=float, default=0, help="rayon des coins de l'écran, en pixels (défaut 0)")
    ap.add_argument("--keep-ellipse", action="append", default=[], metavar="CX,CY,RX,RY",
                    help="zone ovale à garder visible par-dessus l'écran (ex. un objectif) ; répétable")
    ap.add_argument("--keep-rect", action="append", default=[], metavar="X,Y,L,H",
                    help="zone rectangulaire à garder visible par-dessus l'écran ; répétable")
    ap.add_argument("--name", help="nom du cadre (défaut : nom du fichier)")
    ap.add_argument("--background", choices=("black", "transparent"), default="transparent",
                    help="fond autour du téléphone dans les photos et le miroir en direct (défaut : transparent). "
                         "Une vidéo MP4 ne peut pas être transparente : son fond reste noir")
    ap.add_argument("--blacken-fringe", type=int, default=0, metavar="LARGEUR",
                    help="remplace par du noir les pixels violets/bleus restés autour de l'écran (reste du fond d'écran du rendu, "
                         "visible dans les coins) sur cette largeur en pixels, ex. 40. Les zones --keep-* sont épargnées")
    ap.add_argument("--remove-background", action="store_true",
                    help="rend transparent le fond uni autour du téléphone (couleur des bords de l'image, ex. le noir d'un rendu)")
    ap.add_argument("--bg-tolerance", type=int, default=28, help="tolérance de --remove-background (défaut 28)")
    ap.add_argument("--max-size", type=int, default=2000, help="réduit l'image si sa plus grande dimension dépasse cette valeur (défaut 2000)")
    ap.add_argument("--out", help="dossier de sortie (défaut : ton dossier personnel Rear Screen)")
    ap.add_argument("--detect-color", metavar="R,G,B", help="cherche l'écran : donne la couleur du fond d'écran affiché (ex. 120,110,240) ; "
                    "l'outil propose le --screen correspondant, puis s'arrête")
    ap.add_argument("--tolerance", type=int, default=45, help="tolérance de --detect-color (défaut 45)")
    ap.add_argument("--grid", action="store_true", help="écrit une image quadrillée pour lire les coordonnées, puis s'arrête")
    ap.add_argument("--force", action="store_true", help="autorise l'écriture dans le dépôt (déconseillé)")
    a = ap.parse_args()

    name = a.name or os.path.splitext(os.path.basename(a.image))[0]
    safe = "".join(c if c.isalnum() or c in "-_" else "-" for c in name).strip("-") or "frame"
    out_dir = os.path.abspath(a.out) if a.out else os.path.join(personal_dir(), safe)
    inside = os.path.commonpath([os.path.realpath(out_dir), os.path.realpath(ROOT)]) == os.path.realpath(ROOT)
    if inside and not a.force:
        sys.exit(f"Refusé : {out_dir} est dans le dépôt. Les visuels de marque doivent rester dans ton dossier personnel "
                 f"({personal_dir()}). Utilise --force si tu sais ce que tu fais.")
    os.makedirs(out_dir, exist_ok=True)

    img = Image.open(a.image).convert("RGBA")
    k = 1.0
    if max(img.size) > a.max_size:
        k = a.max_size / max(img.size)
        img = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
        print(f"image réduite à {img.width}×{img.height} (coordonnées à donner sur l'image d'origine : elles seront converties)")

    if a.detect_color:
        tr, tg, tb = [int(v) for v in ints(a.detect_color, 3, "--detect-color")]
        src = Image.open(a.image).convert("RGB"); px = src.load(); cols = {}; rows = {}
        for yy in range(src.height):
            for xx in range(src.width):
                r_, g_, b_ = px[xx, yy]
                if abs(r_ - tr) + abs(g_ - tg) + abs(b_ - tb) <= a.tolerance * 2:
                    cols[xx] = cols.get(xx, 0) + 1; rows[yy] = rows.get(yy, 0) + 1
        xs = [v for v, c in cols.items() if c > 30]; ys = [v for v, c in rows.items() if c > 30]
        if not xs or not ys:
            sys.exit("Aucun pixel de cette couleur : essaie une autre couleur ou une tolérance plus grande (--tolerance).")
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        print(f"Zone détectée : --screen {x0},{y0},{x1 - x0 + 1},{y1 - y0 + 1}   (rapport {(x1 - x0 + 1) / (y1 - y0 + 1):.2f})")
        print("Les objectifs/capteurs posés sur l'écran sont à garder avec --keep-ellipse (voir --grid pour leurs coordonnées).")
        return
    if a.grid:
        print("Grille :", write_grid(Image.open(a.image), out_dir), "(coordonnées de l'image d'origine)")
        return
    if not a.screen:
        sys.exit("Indique la position de l'écran avec --screen X,Y,L,H (utilise --grid pour la lire sur l'image).")

    x, y, w, h = [v * k for v in ints(a.screen, 4, "--screen")]
    r = a.radius * k
    if w <= 0 or h <= 0 or x < 0 or y < 0 or x + w > img.width + 0.5 or y + h > img.height + 0.5:
        sys.exit(f"L'écran ({x:.0f},{y:.0f},{w:.0f},{h:.0f}) sort de l'image ({img.width}×{img.height}).")
    ratio = w / h
    if abs(ratio - SCREEN_RATIO) / SCREEN_RATIO > 0.08:
        print(f"⚠ rapport largeur/hauteur de l'écran : {ratio:.2f} (l'écran arrière fait {SCREEN_RATIO:.2f}). "
              "La vidéo sera centrée avec des bandes noires — vérifie les coordonnées.")

    if a.remove_background:
        img = remove_background(img, a.bg_tolerance)

    # masque : 255 = on garde l'image, 0 = trou transparent (dessiné en grand puis réduit : bords lisses)
    big = Image.new("L", (img.width * SS, img.height * SS), 255)
    d = ImageDraw.Draw(big)
    d.rounded_rectangle([x * SS, y * SS, (x + w) * SS - 1, (y + h) * SS - 1], radius=max(r, 0) * SS, fill=0)
    for t in a.keep_ellipse:
        cx, cy, rx, ry = [v * k for v in ints(t, 4, "--keep-ellipse")]
        d.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=255)
    for t in a.keep_rect:
        kx, ky, kw, kh = [v * k for v in ints(t, 4, "--keep-rect")]
        d.rectangle([kx * SS, ky * SS, (kx + kw) * SS - 1, (ky + kh) * SS - 1], fill=255)
    mask = big.resize(img.size, Image.LANCZOS)

    if a.blacken_fringe > 0:
        # reste de l'ancien fond d'écran : pixels violets/bleus juste hors du trou → noir
        keepbig = Image.new("L", big.size, 0)
        kd = ImageDraw.Draw(keepbig)
        for t in a.keep_ellipse:
            cx, cy, rx, ry = [v * k for v in ints(t, 4, "--keep-ellipse")]
            kd.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=255)
        for t in a.keep_rect:
            kx, ky, kw, kh = [v * k for v in ints(t, 4, "--keep-rect")]
            kd.rectangle([kx * SS, ky * SS, (kx + kw) * SS - 1, (ky + kh) * SS - 1], fill=255)
        keep_m = keepbig.resize(img.size, Image.LANCZOS)
        hole_m = ImageChops.invert(mask)                                   # 255 dans le trou
        near = hole_m.filter(ImageFilter.GaussianBlur(a.blacken_fringe * k / 2)).point(lambda v: 255 if v > 6 else 0)
        r_, g_, b_ = img.convert("RGB").split()
        blue_r = ImageChops.subtract(b_, r_).point(lambda v: 255 if v > 22 else 0)
        blue_g = ImageChops.subtract(b_, g_).point(lambda v: 255 if v > 22 else 0)
        fringe = ImageChops.multiply(ImageChops.multiply(near, ImageChops.multiply(blue_r, blue_g)), ImageChops.invert(keep_m))
        fringe = ImageChops.multiply(fringe, mask).filter(ImageFilter.GaussianBlur(0.6))   # seulement hors du trou, bord adouci
        n_px = sum(1 for v in fringe.getdata() if v > 128)
        img = Image.composite(Image.new("RGBA", img.size, (0, 0, 0, 255)), img, fringe)
        print(f"franges violettes remplacées par du noir : {n_px} pixels")
    img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))

    img.save(os.path.join(out_dir, "frame.png"), optimize=True)
    meta = {"name": name, "width": img.width, "height": img.height,
            "screen": {"x": round(x, 1), "y": round(y, 1), "w": round(w, 1), "h": round(h, 1), "radius": round(r, 1)},
            "background": a.background}
    with open(os.path.join(out_dir, "frame.json"), "w") as fh:
        json.dump(meta, fh, indent=2, ensure_ascii=False)

    # aperçu : contenu d'exemple derrière le trou, fond noir
    ph = Image.new("RGBA", img.size, (0, 0, 0, 255))
    scr = Image.new("RGB", (round(w), round(h)))
    px = scr.load()
    for yy in range(scr.height):
        for xx in range(scr.width):
            t = xx / scr.width * 0.6 + yy / scr.height * 0.4
            px[xx, yy] = (round(84 + 70 * t), round(96 + 46 * t), round(238 - 34 * t))
    dd = ImageDraw.Draw(scr); ff = font(max(24, scr.height // 6))
    dd.text((scr.width - 24 - dd.textlength("21:33", font=ff), scr.height // 14), "21:33", font=ff, fill=(255, 255, 255))
    ph.paste(scr, (round(x), round(y)))
    Image.alpha_composite(ph, img).convert("RGB").save(os.path.join(out_dir, "preview.png"), optimize=True)

    print(f"OK — cadre « {name} » écrit dans :\n  {out_dir}\n  (frame.png, frame.json, preview.png)")
    print("Relance Rear Screen : le cadre apparaît dans le menu « Cadre ».")


if __name__ == "__main__":
    main()
