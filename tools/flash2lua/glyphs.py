"""Glyph atlas of the HUD font (Agency FB, imported by the HUD movies from HUD_Font_LocFont.swf).

FFDec exports the DefineFont3 of that SWF as a TTF; Pillow renders each printable ASCII glyph white on
transparent at EM pixels. The player draws text as quads from this atlas, so the HUD does not depend on
the font being installed and scales like the rest of the movie.
"""
import os
import subprocess
import tempfile
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

EM = 128
CHARSET = [chr(c) for c in range(32, 127)]
PADDING = 2
ATLAS_WIDTH = 1024


def _extract(pak_path, swf_name, dest_dir):
    wanted = f"languages/{swf_name}".lower()
    with zipfile.ZipFile(pak_path) as pak:
        for entry in pak.namelist():
            if entry.lower() == wanted:
                path = os.path.join(dest_dir, swf_name)
                with open(path, "wb") as out:
                    out.write(pak.read(entry))
                return path
    raise KeyError(f"{swf_name} is not in {pak_path}")


def _next_pow2(n):
    p = 1
    while p < n:
        p *= 2
    return p


def build_font_atlas(localized_pak, font_swf, ffdec, out_dir, prefix):
    """Returns {"atlas": file name, "em", "asc", "desc", "glyphs": {code: {x, y, w, h, ox, oy, adv}}}.
    ox, oy: top-left of the bitmap relative to the pen position on the baseline; all in pixels at EM."""
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        swf = _extract(localized_pak, font_swf, tmp)
        subprocess.run([ffdec, "-format", "font:ttf", "-export", "font", tmp, swf], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        ttf = None
        for folder, _, files in os.walk(tmp):
            for name in files:
                if name.lower().endswith(".ttf"):
                    ttf = os.path.join(folder, name)
        if ttf is None:
            raise RuntimeError(f"FFDec exported no font from {font_swf}")
        font = ImageFont.truetype(ttf, EM)
        ascent, descent = font.getmetrics()

        bitmaps, metrics = [], {}
        for ch in CHARSET:
            adv = font.getlength(ch)
            left, top, right, bottom = font.getbbox(ch, anchor="ls")
            w, h = right - left, bottom - top
            if ch == " " or w <= 0 or h <= 0:
                metrics[ord(ch)] = {"x": 0, "y": 0, "w": 0, "h": 0, "ox": 0, "oy": 0, "adv": adv}
                continue
            image = Image.new("L", (w + 2, h + 2), 0)
            ImageDraw.Draw(image).text((1 - left, 1 - top), ch, font=font, fill=255, anchor="ls")
            bitmaps.append((ord(ch), image))
            metrics[ord(ch)] = {"w": w, "h": h, "ox": left, "oy": top, "adv": adv}

        # shelf packing
        x = y = shelf = 0
        placed = []
        for code, image in sorted(bitmaps, key=lambda item: -item[1].size[1]):
            w, h = image.size
            if x + w > ATLAS_WIDTH:
                x, y, shelf = 0, y + shelf + PADDING, 0
            placed.append((code, image, x, y))
            x += w + PADDING
            shelf = max(shelf, h)
        height = _next_pow2(y + shelf)
        sheet = np.zeros((height, ATLAS_WIDTH, 4), dtype=np.uint8)
        sheet[:, :, :3] = 255
        for code, image, px, py in placed:
            w, h = image.size
            sheet[py:py + h, px:px + w, 3] = np.asarray(image)
            metrics[code]["x"] = px + 1
            metrics[code]["y"] = py + 1
        name = f"{prefix}.png"
        Image.fromarray(sheet, "RGBA").save(os.path.join(out_dir, name), optimize=True)
    return {"atlas": name, "em": EM, "asc": ascent, "desc": descent, "glyphs": metrics}
