"""Rasterise the shapes of a movie with FFDec and pack them into PNG atlases.

Each atlas rect describes where the shape bitmap lives and where to draw it, in stage pixels:
    {"atlas": file name, "x", "y", "w", "h": pixels in the atlas,
     "ox", "oy": top-left of the shape relative to its origin (stage px),
     "dw", "dh": size to draw it at (stage px)}
FFDec exports a shape's PNG over exactly its bounds, zoomed; the PNG size is rounded up, so the
draw size is the bounds extent (not w/zoom) to avoid drift.
"""
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image

PADDING = 2
MAX_SIDE = 1024  # largest shape bitmap; bigger ones (backdrops) are downscaled
ATLAS_WIDTH = 2048


def _srgb_encode_table():
    """The engine decodes PNG textures as sRGB when it samples them, but Flash blends the plain 0-255
    values. Storing the sRGB-encoded colour makes the shader see the original one (error <= 1-2 levels)."""
    table = np.zeros(256, dtype=np.uint8)
    for v in range(256):
        x = v / 255
        y = 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055
        table[v] = int(round(255 * y))
    return table


SRGB_ENCODE = _srgb_encode_table()


def _next_pow2(n):
    p = 1
    while p < n:
        p *= 2
    return p


def export_shapes(ffdec, swf_path, out_dir, zoom):
    """Run FFDec; returns {shape id: PNG path}."""
    subprocess.run([ffdec, "-zoom", str(zoom), "-format", "shape:png", "-export", "shape",
                    out_dir, swf_path], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    found = {}
    for folder, _, files in os.walk(out_dir):  # FFDec adds a "shapes" folder only with several export types
        for f in files:
            if f.endswith(".png") and f[:-4].isdigit():
                found[int(f[:-4])] = os.path.join(folder, f)
    return found


def bleed_colour(rgba):
    """Give fully transparent pixels the colour of a neighbouring visible pixel, so bilinear
    filtering does not blend black into the edges. rgba: uint8 array (H, W, 4), modified in place."""
    known = rgba[:, :, 3] > 0
    if not known.any():
        return rgba
    for _ in range(64):
        unknown = ~known
        if not unknown.any():
            break
        grown = np.zeros_like(known)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                src_known = np.roll(np.roll(known, dy, axis=0), dx, axis=1)
                src_rgb = np.roll(np.roll(rgba[:, :, :3], dy, axis=0), dx, axis=1)
                take = unknown & ~grown & src_known
                rgba[:, :, :3][take] = src_rgb[take]
                grown |= take
        if not grown.any():
            break
        known = known | grown
    return rgba


def _capped(im):
    w, h = im.size
    longest = max(w, h)
    if longest <= MAX_SIDE:
        return im
    k = MAX_SIDE / longest
    return im.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)


def _padded(im):
    """The shape bitmap on a canvas one pixel larger on every side, transparent pixels given the
    colour of their visible neighbours (bilinear filtering must not blend black into the edges)."""
    w, h = im.size
    canvas = np.zeros((h + 2, w + 2, 4), dtype=np.uint8)
    canvas[1:h + 1, 1:w + 1] = np.asarray(im)
    return Image.fromarray(bleed_colour(canvas), "RGBA")


def _pack(images, max_atlas):
    """Shelf packing. images: [(id, PIL image)] -> ([(id, atlas index, x, y)], [(width, height)])."""
    order = sorted(images, key=lambda item: -item[1].size[1])
    placements, sizes = [], []
    x = y = shelf_h = 0
    atlas = 0
    used_w = 0
    for cid, im in order:
        w, h = im.size
        if x + w > ATLAS_WIDTH:
            x, y, shelf_h = 0, y + shelf_h + PADDING, 0
        if y + h > max_atlas:
            sizes.append((used_w, y + shelf_h))
            atlas += 1
            x = y = shelf_h = used_w = 0
        placements.append((cid, atlas, x, y))
        x += w + PADDING
        used_w = max(used_w, x)
        shelf_h = max(shelf_h, h)
    sizes.append((used_w, y + shelf_h))
    return placements, sizes


def rasterize_movie(movie, swf_path, out_dir, ffdec, zoom=4, max_atlas=4096, prefix="atlas"):
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        pngs = export_shapes(ffdec, swf_path, tmp, zoom)
        images = []
        for cid, char in movie.characters.items():
            if char.kind == "shape" and cid in pngs:
                images.append((cid, _padded(_capped(Image.open(pngs[cid]).convert("RGBA")))))
        by_id = dict(images)
        placements, sizes = _pack(images, max_atlas)
        sheets = [np.zeros((_next_pow2(max(h, 1)), _next_pow2(max(w, 1)), 4), dtype=np.uint8)
                  for w, h in sizes]
        rects = {}
        for cid, atlas, x, y in placements:
            im = by_id[cid]
            w, h = im.size[0] - 2, im.size[1] - 2
            sheets[atlas][y:y + h + 2, x:x + w + 2] = np.asarray(im)
            x, y = x + 1, y + 1
            x0, y0, x1, y1 = movie.characters[cid].bounds
            rects[cid] = {"atlas": f"{prefix}_{atlas + 1}.png", "x": x, "y": y, "w": w, "h": h,
                          "ox": x0, "oy": y0, "dw": x1 - x0, "dh": y1 - y0}
        for index, sheet in enumerate(sheets):
            # the all-white twin, for shapes whose colour a colour-set clip replaces (see emit_lua `white`)
            silhouette = sheet.copy()
            silhouette[:, :, :3] = 255
            Image.fromarray(silhouette, "RGBA").save(
                os.path.join(out_dir, f"{prefix}_{index + 1}_w.png"), optimize=True)
            sheet[:, :, :3] = SRGB_ENCODE[sheet[:, :, :3]]
            Image.fromarray(sheet, "RGBA").save(
                os.path.join(out_dir, f"{prefix}_{index + 1}.png"), optimize=True)
    return rects
