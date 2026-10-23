#!/usr/bin/env python3
"""Génère le logo Mizu (水) et les icônes des plateformes.

Source unique : le kanji 水 dessiné avec Noto Sans CJK JP, posé sur un carré
arrondi dégradé. Sorties :

    app/assets/logo.png         512 px, fond arrondi (in-app, docs)
    app/assets/logo_256.png     256 px (icône de fenêtre Linux)
    app/assets/logo_mark.png    512 px, glyphe seul sur fond transparent
    app/android/.../mipmap-*/   icônes de lancement Android (si le dossier existe)

Usage : python3 tools/make_icons.py
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = "/usr/share/fonts/noto-cjk/NotoSansCJK-Bold.ttc"
GLYPH = "水"

TOP = (22, 48, 63)      # bleu profond
BOTTOM = (8, 13, 18)    # presque noir
GLYPH_COLOR = (191, 233, 245)
GLYPH_GLOW = (120, 200, 230)


def rounded_mask(size: int, radius_ratio: float = 0.22) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    r = int(size * radius_ratio)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return mask


def gradient(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        row = tuple(
            int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)
        )
        for x in range(size):
            px[x, y] = row
    return img


def glyph_layer(size: int, color, scale: float = 0.62) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    font = ImageFont.truetype(FONT, int(size * scale), index=0)
    left, top, right, bottom = draw.textbbox((0, 0), GLYPH, font=font)
    x = (size - (right - left)) / 2 - left
    y = (size - (bottom - top)) / 2 - top
    draw.text((x, y), GLYPH, font=font, fill=color)
    return layer


def build_logo(size: int) -> Image.Image:
    base = gradient(size).convert("RGBA")
    base.putalpha(rounded_mask(size))

    glow = glyph_layer(size, (*GLYPH_GLOW, 160))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=size * 0.045))
    base = Image.alpha_composite(base, glow)

    base = Image.alpha_composite(base, glyph_layer(size, (*GLYPH_COLOR, 255)))
    return base


def build_mark(size: int) -> Image.Image:
    mark = glyph_layer(size, (*GLYPH_COLOR, 255))
    glow = glyph_layer(size, (*GLYPH_GLOW, 120)).filter(
        ImageFilter.GaussianBlur(radius=size * 0.05)
    )
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out = Image.alpha_composite(out, glow)
    return Image.alpha_composite(out, mark)


def build_banner(width: int = 320, height: int = 180) -> Image.Image:
    """Bannière Android TV (320x180)."""
    banner = Image.new("RGB", (width, height))
    px = banner.load()
    for y in range(height):
        t = y / max(1, height - 1)
        row = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        for x in range(width):
            px[x, y] = row
    banner = banner.convert("RGBA")

    mark = build_mark(height).resize((height, height), Image.LANCZOS)
    banner.paste(mark, (0, 0), mark)

    draw = ImageDraw.Draw(banner)
    font = ImageFont.truetype(FONT, int(height * 0.24), index=0)
    label = "Mizu"
    left, top, right, bottom = draw.textbbox((0, 0), label, font=font)
    x = height * 0.92
    y = (height - (bottom - top)) / 2 - top
    draw.text((x, y), label, font=font, fill=(*GLYPH_COLOR, 255))
    return banner


def write_android(logo: Image.Image) -> None:
    base = os.path.join(ROOT, "app", "android", "app", "src", "main", "res")
    if not os.path.isdir(base):
        return
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, px in densities.items():
        target = os.path.join(base, folder)
        os.makedirs(target, exist_ok=True)
        logo.resize((px, px), Image.LANCZOS).save(
            os.path.join(target, "ic_launcher.png")
        )
        # icône ronde (TV / launchers récents)
        round_mask = Image.new("L", (px, px), 0)
        ImageDraw.Draw(round_mask).ellipse((0, 0, px - 1, px - 1), fill=255)
        round_icon = logo.resize((px, px), Image.LANCZOS)
        round_icon.putalpha(round_mask)
        round_icon.save(os.path.join(target, "ic_launcher_round.png"))
    drawable = os.path.join(base, "drawable")
    os.makedirs(drawable, exist_ok=True)
    build_banner().save(os.path.join(drawable, "tv_banner.png"))
    print("icônes Android + bannière TV écrites")


def main() -> None:
    assets = os.path.join(ROOT, "app", "assets")
    os.makedirs(assets, exist_ok=True)

    logo = build_logo(512)
    logo.save(os.path.join(assets, "logo.png"))
    logo.resize((256, 256), Image.LANCZOS).save(
        os.path.join(assets, "logo_256.png")
    )
    build_mark(512).save(os.path.join(assets, "logo_mark.png"))
    print("assets écrits : logo.png, logo_256.png, logo_mark.png")

    write_android(logo)


if __name__ == "__main__":
    main()
