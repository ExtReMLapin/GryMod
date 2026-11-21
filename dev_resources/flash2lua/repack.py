"""Turn the PNG atlases of a converted movie into VTF textures (and their VMT materials), packed tighter.

    python -m dev_resources.flash2lua.repack --png-dir <folder with <movie>_<n>.png> [--format dxt5|bgra8888] movie ...

The Lua data of a movie (lua/grymod/flash/<movie>.lua) says where each shape sits in its atlas. This reads the
atlas pictures, cuts every shape out (with the pixel of bled colour around it), packs them again in the smallest
power-of-two sheet, writes the sheet as `<movie>_1.vtf` (+ the all-white twin `<movie>_1_w.vtf` of the shapes whose
colour a colour-set clip replaces), points the Lua at the new places, and shares the glyph atlas between the movies
(it is the same picture in every movie).

The colours stay sRGB-encoded with the sRGB flag, as in the PNG atlases: the engine decodes every colour texture it
samples (a texture holding the plain values and no flag came out darker, measured), so the encoding is what cancels it.
The glyph atlas is not compressed (text is the most looked-at thing and its edges are what DXT5 changes most);
the shape sheets are DXT5.
"""
import argparse
import hashlib
import os
import re

import numpy as np
from PIL import Image

from dev_resources.flash2lua import pack, vtf

MATERIAL_DIR = "grymod/flash"
FONT_NAME = "hud_font"
PADDING = 2

_SHAPE = re.compile(r'(\[(\d+)\]=\{k="shape",a=)(\d+)(,x=)(\d+)(,y=)(\d+)(,w=)(\d+)(,h=)(\d+)')
_ATLASES = re.compile(r'atlases=\{([^}]*)\}')
_WHITE = re.compile(r'white=\{([^}]*)\}')
_FONT = re.compile(r'(\[\d+\]=\{a=)(\d+)(,em=)')


def read_atlas_names(text):
    match = _ATLASES.search(text)
    return re.findall(r'"([^"]+)"', match.group(1))


def shape_atlas_indices(text):
    match = _WHITE.search(text)
    return {int(i) for i in re.findall(r'\[(\d+)\]=true', match.group(1))} if match else set()


SHRINK_STEPS = (2, 4, 8, 16, 32)
SHRINK_MEAN = 0.25      # mean error (levels, premultiplied) a shrunk shape may have
SHRINK_PEAK = 4         # error (levels) 99.9 % of its pixels stay under
MIN_SIDE = 4


def _resize_channels(arr, size, mode):
    return np.stack([np.asarray(Image.fromarray(arr[:, :, i]).resize(size, mode)) for i in range(4)], axis=2)


def shrink_picture(rgba):
    """A shape bitmap (h, w, 4 uint8, without its padding) at the smallest size that looks the same: flat colours and
    smooth gradients do not need four texels per stage pixel. Compares the picture with its shrunk-and-stretched-back
    self (colours premultiplied by alpha: what the screen gets). Returns the same array when it cannot shrink."""
    h, w = rgba.shape[:2]
    premultiplied = rgba.astype(np.float32).copy()
    premultiplied[:, :, :3] *= premultiplied[:, :, 3:4] / 255.0
    pm8 = np.clip(np.rint(premultiplied), 0, 255).astype(np.uint8)
    best = None
    for k in SHRINK_STEPS:
        nw, nh = max(MIN_SIDE, round(w / k)), max(MIN_SIDE, round(h / k))
        if nw >= w or nh >= h:
            break
        small = _resize_channels(pm8, (nw, nh), Image.BOX)
        back = _resize_channels(small, (w, h), Image.BILINEAR).astype(np.float32)
        err = np.abs(back - premultiplied).max(axis=2)
        if err.mean() > SHRINK_MEAN or np.percentile(err, 99.9) > SHRINK_PEAK:
            if err.mean() > 2.0:
                break  # a smaller one will not do better
            continue  # rounding noise of a ramp can fail one size and pass the next
        best = small
    if best is None:
        return rgba
    # back to straight alpha where there is some
    out = best.astype(np.float32)
    alpha = out[:, :, 3:4]
    out[:, :, :3] = np.where(alpha > 0, out[:, :, :3] * 255.0 / np.maximum(alpha, 1.0), 0)

    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


def write_texture(directory, name, rgba, fmt, srgb=True, twin_of=None):
    """`name`.vtf and `name`.vmt in directory."""
    vtf.write_vtf(os.path.join(directory, name + ".vtf"), rgba, fmt, srgb=srgb)
    with open(os.path.join(directory, name + ".vmt"), "w", encoding="utf8", newline="\n") as out:
        out.write(vtf.vmt_text("%s/%s" % (MATERIAL_DIR, name)))


def repack_movie(movie, lua_dir, png_dir, out_dir, fmt="dxt5", font_done=None, png_name=None, font_fmt="bgra8888"):
    """Converts one movie. png_dir has the atlas PNGs under the names the Lua gives (<movie>_<n>.png, <movie>_font.png).
    font_done: {md5 of a glyph atlas: its shared name}, filled in as the movies go. Returns the new Lua text."""
    lua_path = os.path.join(lua_dir, movie + ".lua")
    with open(lua_path, encoding="utf8", newline="") as source:
        text = source.read()
    names = read_atlas_names(text)
    shape_indices = shape_atlas_indices(text)
    font_done = {} if font_done is None else font_done
    os.makedirs(out_dir, exist_ok=True)

    # every shape of the shape atlases, as its padded picture
    sheets = {}
    pictures = {}
    shapes = []
    sizes = {}
    for match in _SHAPE.finditer(text):
        cid, atlas, x, y, w, h = (int(match.group(i)) for i in (2, 3, 5, 7, 9, 11))
        if atlas not in sheets:
            png = os.path.join(png_dir, os.path.basename(names[atlas - 1]) if png_name is None else png_name(names[atlas - 1]))
            sheets[atlas] = np.asarray(Image.open(png).convert("RGBA"))
        picture = sheets[atlas][y - 1:y + h + 1, x - 1:x + w + 1]
        small = shrink_picture(picture[1:-1, 1:-1])
        if small.shape[:2] != (h, w):
            # the new size goes into the data, the drawn size (dw, dh) stays: the texture is stretched over it
            h, w = small.shape[:2]
            picture = np.pad(small, ((1, 1), (1, 1), (0, 0)), mode="edge")
        pictures[cid] = picture
        sizes[cid] = (w, h)
        shapes.append((cid, w, h))
    if not shapes:
        raise ValueError("%s has no shapes" % movie)

    sheet_sizes, placed = pack.pack_sheets([(cid, w + 2, h + 2) for cid, w, h in shapes], gap=PADDING)
    sheet_arrays = [np.zeros((height, width, 4), dtype=np.uint8) for width, height in sheet_sizes]
    for cid, w, h in shapes:
        sheet, px, py = placed[cid]
        sheet_arrays[sheet][py:py + h + 2, px:px + w + 2] = pictures[cid]

    def new_place(match):
        cid = int(match.group(2))
        sheet, px, py = placed[cid]
        g = match.group
        w, h = sizes[cid]
        return "%s%d%s%d%s%d%s%d%s%d" % (g(1), sheet + 1, g(4), px + 1, g(6), py + 1, g(8), w, g(10), h)

    text = _SHAPE.sub(new_place, text)

    new_names = []
    for index, array in enumerate(sheet_arrays, start=1):
        base = "%s_%d" % (movie, index)
        write_texture(out_dir, base, array, fmt)
        if shape_indices:
            silhouette = array.copy()
            silhouette[:, :, :3] = 255
            write_texture(out_dir, base + "_w", silhouette, fmt, srgb=False)
        new_names.append("%s/%s" % (MATERIAL_DIR, base))

    # the atlases that are not shape sheets (glyphs): shared between the movies
    remap = {}
    for index, name in enumerate(names, start=1):
        if index in shape_indices:
            continue
        png = os.path.join(png_dir, os.path.basename(name))
        with open(png, "rb") as source:
            digest = hashlib.md5(source.read()).hexdigest()
        shared = font_done.get(digest)
        if shared is None:
            shared = "%s/%s" % (MATERIAL_DIR, FONT_NAME if not font_done else "%s_%d" % (FONT_NAME, len(font_done) + 1))
            font_done[digest] = shared
            glyphs = np.asarray(Image.open(png).convert("RGBA"))
            write_texture(out_dir, shared.rsplit("/", 1)[1], glyphs, font_fmt, srgb=False)
        if shared in new_names:
            remap[index] = new_names.index(shared) + 1
        else:
            new_names.append(shared)
            remap[index] = len(new_names)

    text = _FONT.sub(lambda m: m.group(1) + str(remap.get(int(m.group(2)), int(m.group(2)))) + m.group(3), text)
    text = _ATLASES.sub(lambda m: "atlases={%s}" % ",".join('"%s"' % n for n in new_names), text, count=1)
    white = ",".join("[%d]=true" % i for i in range(1, len(sheet_arrays) + 1)) if shape_indices else ""
    text = _WHITE.sub("white={%s}" % white, text, count=1)

    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--png-dir", default="materials/grymod/flash")
    parser.add_argument("--lua-dir", default="lua/grymod/flash")
    parser.add_argument("--out-dir", default="materials/grymod/flash")
    parser.add_argument("--format", default="dxt5", choices=["dxt5", "bgra8888"])
    parser.add_argument("--font-format", default="bgra8888", choices=["dxt5", "bgra8888"])
    parser.add_argument("movies", nargs="+")
    args = parser.parse_args()
    font_done = {}
    for movie in args.movies:
        text = repack_movie(movie, args.lua_dir, args.png_dir, args.out_dir, args.format, font_done, font_fmt=args.font_format)
        with open(os.path.join(args.lua_dir, movie + ".lua"), "w", encoding="utf8", newline="\n") as out:
            out.write(text)
        print("repacked", movie)


if __name__ == "__main__":
    main()
