"""Reads the textures of the Crysis camouflage (the shader CloakLayer.cfx and the ones around it) from the game's own
archives and writes them as VTF files, for GryMod to try. It holds no resource of the game, only code.

    python tools/extract_cloak_textures.py "C:/Program Files (x86)/Electronic Arts/Crytek/Crysis SP Demo/Game" --out DIR
        [--png DIR] [--manifest FILE] [--only name ...]

The archives are ZIP files (Textures.pak, GameData.pak, Objects.pak). Every texture is decoded from its DDS (DXT1/3/5,
ATI2, A8, L8 and the usual uncompressed layouts) and written as DIR/<name>.vtf: a VTF 7.2 in BGRA8888 (or I8 for the
noise), no sRGB flag (these are data, not colours), with the clamp flags the shader's samplers ask for (a texture the
shader repeats does not get CLAMPS/CLAMPT, tools/flash2lua/vtf.py writes both by default). Nothing is copied into
materials/: --out refuses a folder under a `materials` folder, a human decides what goes into the addon.

What the conversions do:
  * a DDS that is only alpha (A8) is written as opaque grey (v, v, v, 255): the value is in every colour channel;
  * the 3D noise (a 128 x 128 x 128 volume, which the Source engine does not have) is cut into its slices, laid out
    row by row in one picture (slice k at column k % columns, row k // columns), 16 x 8 slices for the 128 cube;
  * the two normal maps (ATI2: only x and y are stored) get z rebuilt, RGB = (x, y, z) * 0.5 + 0.5, alpha 255;
    the orientation of y was not checked against the Source convention;
  * only the first mip level of a DDS is read; the VTF gets its own mip chain when the texture needs one.
Every VTF is read back and compared with the decoded DDS pixel by pixel: the largest difference per channel goes in the
manifest (0 for the lossless formats).

Needs Python 3.12, numpy and Pillow.
"""
import argparse
import json
import math
import os
import struct
import sys
import zipfile
from dataclasses import dataclass

import numpy as np

# `python -I` and `python tools/x.py` do not put the repository on the path (tools/ is a namespace package)
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))

from tools.flash2lua import vtf  # noqa: E402

DDSD_MIPMAPCOUNT = 0x20000
DDSD_DEPTH = 0x800000
DDPF_ALPHAPIXELS = 0x1
DDPF_ALPHA = 0x2
DDPF_FOURCC = 0x4
DDPF_RGB = 0x40
DDPF_LUMINANCE = 0x20000
BLOCK_BYTES = {"DXT1": 8, "DXT3": 16, "DXT5": 16, "ATI2": 16}


@dataclass(frozen=True)
class DdsInfo:
    width: int
    height: int
    depth: int
    mips: int
    format: str
    bits: int
    flags: int
    masks: tuple  # r, g, b, a

    @property
    def is_volume(self):
        return self.depth > 1

    @property
    def alpha_only(self):
        return self.format == "A8"

    @property
    def compressed(self):
        return self.format in BLOCK_BYTES

    def level0_size(self):
        """Bytes of the first mip level (every slice of a volume)."""
        if self.compressed:
            return ((self.width + 3) // 4) * ((self.height + 3) // 4) * BLOCK_BYTES[self.format] * self.depth
        return self.width * self.height * self.depth * (self.bits // 8)


def parse_dds(data):
    if len(data) < 128 or data[:4] != b"DDS ":
        raise ValueError("not a DDS file")
    size, flags, height, width, _, depth, mips = struct.unpack_from("<7I", data, 4)
    if size != 124:
        raise ValueError(f"unexpected DDS header size {size}")
    pf_size, pf_flags, fourcc, bits, rm, gm, bm, am = struct.unpack_from("<II4s5I", data, 76)
    if pf_size != 32:
        raise ValueError(f"unexpected DDS pixel format size {pf_size}")
    depth = depth if flags & DDSD_DEPTH and depth > 1 else 1
    mips = mips if flags & DDSD_MIPMAPCOUNT and mips > 0 else 1
    masks = (rm, gm, bm, am)

    if pf_flags & DDPF_FOURCC:
        name = fourcc.decode("latin1")
        if name not in BLOCK_BYTES:
            raise ValueError(f"unsupported DDS compression {name!r}")
        fmt, bits = name, 0
    elif bits == 8 and (pf_flags & DDPF_ALPHA or (pf_flags & DDPF_ALPHAPIXELS and not pf_flags & DDPF_RGB and am)):
        fmt = "A8"  # Crytek's files set either flag; only an alpha mask, no colour
    elif pf_flags & DDPF_LUMINANCE and bits == 8:
        fmt = "L8"
    elif pf_flags & (DDPF_RGB | DDPF_ALPHAPIXELS) and bits in (8, 16, 24, 32):
        std = (0xFF0000, 0xFF00, 0xFF)
        if masks[:3] == std and bits == 32:
            fmt = "ARGB8888" if am == 0xFF000000 else "XRGB8888"
        elif masks[:3] == std and bits == 24:
            fmt = "RGB888"
        else:
            fmt = f"MASKS{bits}"
    else:
        raise ValueError(f"unsupported DDS pixel format (flags {pf_flags:#x}, {bits} bits)")

    return DdsInfo(width, height, depth, mips, fmt, bits, pf_flags, masks)


# ---------------------------------------------------------------------------------------------------------------
# block compression

def _expand565(v):
    r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
    return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], axis=-1).astype(np.int32)


def decode_bc1_colour_blocks(raw, opaque_four_colours=False):
    """(N, 8) uint8 colour blocks -> (N, 16, 4) uint8. A DXT1 block with c0 <= c1 has three colours and a transparent
    black texel; the colour block of DXT3/5 never does (opaque_four_colours)."""
    raw = np.ascontiguousarray(raw)
    c0 = raw[:, 0].astype(np.int32) | (raw[:, 1].astype(np.int32) << 8)
    c1 = raw[:, 2].astype(np.int32) | (raw[:, 3].astype(np.int32) << 8)
    e0, e1 = _expand565(c0), _expand565(c1)
    pal = np.zeros((raw.shape[0], 4, 4), dtype=np.int32)
    pal[:, :, 3] = 255
    pal[:, 0, :3], pal[:, 1, :3] = e0, e1
    four = (c0 > c1) | opaque_four_colours
    pal[:, 2, :3] = np.where(four[:, None], (2 * e0 + e1) // 3, (e0 + e1) // 2)
    pal[:, 3, :3] = np.where(four[:, None], (e0 + 2 * e1) // 3, 0)
    pal[:, 3, 3] = np.where(four, 255, 0)
    bits = raw[:, 4].astype(np.uint32) | (raw[:, 5].astype(np.uint32) << 8) | (raw[:, 6].astype(np.uint32) << 16) \
        | (raw[:, 7].astype(np.uint32) << 24)
    idx = ((bits[:, None] >> (np.arange(16, dtype=np.uint32) * 2)[None, :]) & 3).astype(np.int64)

    return np.take_along_axis(pal, idx[:, :, None], axis=1).astype(np.uint8)


def decode_bc4_blocks(raw):
    """(N, 8) uint8 single-channel blocks (the alpha block of DXT5, a channel of ATI2) -> (N, 16) uint8."""
    raw = np.ascontiguousarray(raw)
    n = raw.shape[0]
    a0, a1 = raw[:, 0].astype(np.float32), raw[:, 1].astype(np.float32)
    pal = np.empty((n, 8), dtype=np.float32)
    pal[:, 0], pal[:, 1] = a0, a1
    eight = raw[:, 0] > raw[:, 1]
    for i in range(2, 8):
        if i < 6:
            pal[:, i] = np.where(eight, ((8 - i) * a0 + (i - 1) * a1) / 7.0, ((6 - i) * a0 + (i - 1) * a1) / 5.0)
        else:
            pal[:, i] = np.where(eight, ((8 - i) * a0 + (i - 1) * a1) / 7.0, 0.0 if i == 6 else 255.0)
    bits = np.zeros(n, dtype=np.uint64)
    for i in range(6):
        bits |= raw[:, 2 + i].astype(np.uint64) << np.uint64(8 * i)
    idx = ((bits[:, None] >> (np.arange(16, dtype=np.uint64) * 3)[None, :]) & np.uint64(7)).astype(np.int64)

    return np.rint(np.take_along_axis(pal, idx, axis=1)).clip(0, 255).astype(np.uint8)


def _assemble(blocks, width, height):
    """(N, 16, C) block pixels, row by row of blocks -> (height, width, C)."""
    bw, bh = (width + 3) // 4, (height + 3) // 4
    c = blocks.shape[2]
    img = blocks.reshape(bh, bw, 4, 4, c).transpose(0, 2, 1, 3, 4).reshape(bh * 4, bw * 4, c)

    return img[:height, :width]


def _decode_compressed(info, data):
    w, h, fmt = info.width, info.height, info.format
    if fmt == "DXT5":
        return vtf.decode_dxt5(data, w, h)
    raw = np.frombuffer(data, dtype=np.uint8).reshape(-1, BLOCK_BYTES[fmt])
    if fmt == "DXT1":
        return _assemble(decode_bc1_colour_blocks(raw), w, h)
    if fmt == "DXT3":
        nibbles = np.empty((raw.shape[0], 16), dtype=np.uint8)
        nibbles[:, 0::2] = (raw[:, :8] & 15)
        nibbles[:, 1::2] = (raw[:, :8] >> 4)
        out = decode_bc1_colour_blocks(raw[:, 8:], opaque_four_colours=True)
        out[:, :, 3] = nibbles * 17
        return _assemble(out, w, h)
    # ATI2: x then y, z rebuilt
    out = np.empty((raw.shape[0], 16, 4), dtype=np.uint8)
    out[:, :, 0] = decode_bc4_blocks(raw[:, :8])
    out[:, :, 1] = decode_bc4_blocks(raw[:, 8:])
    x = out[:, :, 0].astype(np.float32) / 255.0 * 2.0 - 1.0
    y = out[:, :, 1].astype(np.float32) / 255.0 * 2.0 - 1.0
    z = np.sqrt(np.clip(1.0 - x * x - y * y, 0.0, 1.0))
    out[:, :, 2] = np.rint((z * 0.5 + 0.5) * 255.0).clip(0, 255).astype(np.uint8)
    out[:, :, 3] = 255

    return _assemble(out, w, h)


def _decode_uncompressed(info, data):
    n = info.width * info.height * info.depth
    bpp = info.bits // 8
    raw = np.frombuffer(data, dtype=np.uint8).reshape(n, bpp).astype(np.uint32)
    px = np.zeros(n, dtype=np.uint32)
    for i in range(bpp):
        px |= raw[:, i] << np.uint32(8 * i)
    out = np.empty((n, 4), dtype=np.uint8)

    def channel(mask):
        if mask == 0:
            return None
        shift = (mask & -mask).bit_length() - 1
        top = (mask >> shift)
        return np.rint(((px & np.uint32(mask)) >> np.uint32(shift)).astype(np.float64) * 255.0 / top).astype(np.uint8)

    if info.format in ("A8", "L8"):
        v = px.astype(np.uint8)
        out[:, :3] = v[:, None]
        out[:, 3] = 255
    else:
        r, g, b, a = (channel(m) for m in info.masks)
        out[:, 0], out[:, 1], out[:, 2] = r, g, b
        out[:, 3] = a if a is not None else 255

    return out.reshape(info.depth, info.height, info.width, 4)


def decode_dds(data):
    """(info, pixels): the first mip level as (depth, height, width, 4) uint8 RGBA, depth 1 unless it is a volume."""
    info = parse_dds(data)
    need = info.level0_size()
    body = data[128:128 + need]
    if len(body) < need:
        raise ValueError(f"DDS data too short: {len(body)} bytes for {need}")
    if info.compressed:
        img = _decode_compressed(info, body)
        return info, img.reshape(info.depth, info.height, info.width, 4)
    return info, _decode_uncompressed(info, body)


# ---------------------------------------------------------------------------------------------------------------
# volumes and archives

def volume_atlas(volume, columns=None):
    """(atlas, columns, rows): the slices of a (depth, h, w, 4) volume side by side, row by row."""
    depth, h, w = volume.shape[:3]
    if columns is None:
        columns = 1 << math.ceil(math.log2(max(1.0, math.sqrt(depth))))
    rows = -(-depth // columns)
    atlas = np.zeros((rows * h, columns * w, volume.shape[3]), dtype=volume.dtype)
    for k in range(depth):
        y, x = divmod(k, columns)
        atlas[y * h:(y + 1) * h, x * w:(x + 1) * w] = volume[k]

    return atlas, columns, rows


def read_pak_entry(pak_path, name):
    """The bytes of an entry of a ZIP archive (names compared without case, with / or \\)."""
    wanted = name.replace("\\", "/").lower()
    with zipfile.ZipFile(pak_path) as pak:
        for entry in pak.namelist():
            if entry.replace("\\", "/").lower() == wanted:
                return pak.read(entry)
    raise KeyError(f"{name} is not in {pak_path}")


# ---------------------------------------------------------------------------------------------------------------
# the textures

@dataclass(frozen=True)
class Spec:
    name: str
    pak: str
    path: str
    vtf_format: str
    mips: bool = False
    clamp: str = "st"
    atlas_columns: int = None
    role: str = ""


_P = "textures/defaults/palette/"
# `clamp` is the address mode of the shader's sampler (CloakLayer.cfx, Cloak.cfx, Cloth.cfx): Wrap on an axis = no flag
SPECS = (
    Spec("cloak_interlation", "Textures.pak", _P + "cloak_interlation.dds", "bgra8888", clamp="t",
         role="CloakLayer.cfx, pass 1 and 2: scan lines, sampled at (screen y + random) x screen height x 0.25; "
              "R,G modulate the refraction and the palette lookup, A is the triangle wave (sparks)"),
    Spec("cloak_sparks", "Textures.pak", _P + "cloak_sparks.dds", "bgra8888", clamp="t",
         role="CloakLayer.cfx, pass 2: the spark profile, R, G and B read at three different offsets of the noise"),
    Spec("cloak_palette", "Textures.pak", _P + "cloak_palette.dds", "bgra8888", clamp="st",
         role="CloakLayer.cfx, pass 1: rim colour, indexed by interlation.G x (1 - N.V)"),
    Spec("cloak_transition", "Textures.pak", _P + "cloak_transition.dds", "bgra8888", clamp="st",
         role="CloakLayer.cfx, pass 2: the curve of the sparks against the cloak blend (A8, value in every channel)"),
    Spec("noise3d", "Textures.pak", "textures/defaults/noise3d.dds", "i8", clamp="", atlas_columns=16,
         role="CloakLayer.cfx, pass 2: the 3D noise (128 cube, A8) that indexes cloak_sparks; here its 128 slices"),
    Spec("fringe_map", "Textures.pak", "textures/defaults/fringe_map.dds", "bgra8888", clamp="t",
         role="Cloak.cfx (props, mat_cloak.mtl): diffraction colour"),
    Spec("interference", "Textures.pak", "textures/defaults/interference.dds", "bgra8888", mips=True, clamp="",
         role="Cloak.cfx (props): the interference noise, tiled every 64 screen pixels, scrolled in time"),
    Spec("noise", "Textures.pak", "textures/defaults/noise.dds", "bgra8888", mips=True, clamp="",
         role="Cloth.cfx (the suit's own material): cloakFluidSampler, the dither of the chameleon colour"),
    Spec("organic_ddn", "GameData.pak", "Materials/Presets/MaterialTypes/textures/organic_ddn.dds", "bgra8888",
         mips=True, clamp="", role="mat_cloak.mtl: the normal map of the props' cloak"),
    Spec("nanosuit_us_ddn", "Objects.pak", "objects/characters/human/us/nanosuit/nanosuit_us_ddn.dds", "bgra8888",
         mips=True, clamp="", role="nanosuit_us_cloak.mtl: the suit's normal map (the layer's bump), x and y stored, z rebuilt"),
)


def _pow2_up(n):
    return 1 << (n - 1).bit_length()


def convert(spec, game_dir, out_dir, png_dir=None):
    """Writes out_dir/<name>.vtf (and png_dir/<name>.png); returns the description of the texture for the manifest."""
    pak_path = os.path.join(game_dir, spec.pak)
    try:
        data = read_pak_entry(pak_path, spec.path)
    except KeyError as error:
        raise KeyError(f"{spec.path} is not in {spec.pak} ({pak_path})") from error
    info, pixels = decode_dds(data)

    atlas = None
    if info.is_volume:
        image, cols, rows = volume_atlas(pixels, spec.atlas_columns)
        atlas = {"columns": cols, "rows": rows, "tile": [info.width, info.height]}
    else:
        image = pixels[0]
    # the VTF wants power-of-two sides: pad an atlas that is not (the padding is black)
    h, w = image.shape[:2]
    ph, pw = _pow2_up(h), _pow2_up(w)
    if (ph, pw) != (h, w):
        image = np.pad(image, ((0, ph - h), (0, pw - w), (0, 0)))
        if atlas:
            atlas["padded_to"] = [pw, ph]

    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, spec.name + ".vtf")
    vtf.write_vtf(path, image, spec.vtf_format, srgb=False, mips=spec.mips, clamp=spec.clamp)
    back = vtf.read_vtf_top(path)
    want = image if spec.vtf_format != "i8" else np.stack([image[:, :, 0]] * 3 + [np.full(image.shape[:2], 255, np.uint8)], axis=2)
    error = int(np.abs(back.astype(int) - want.astype(int)).max())

    if png_dir:
        from PIL import Image
        os.makedirs(png_dir, exist_ok=True)
        if info.alpha_only:
            Image.fromarray(image[:, :, 0], "L").save(os.path.join(png_dir, spec.name + ".png"))
        elif (image[:, :, 3] == 255).all():
            Image.fromarray(image[:, :, :3], "RGB").save(os.path.join(png_dir, spec.name + ".png"))
        else:
            Image.fromarray(image, "RGBA").save(os.path.join(png_dir, spec.name + ".png"))

    return {
        "name": spec.name, "archive": spec.pak, "path": spec.path, "role": spec.role,
        "dds_bytes": len(data), "dds_format": info.format, "dds_mips": info.mips,
        "width": info.width, "height": info.height, "depth": info.depth, "volume": info.is_volume,
        "atlas": atlas, "vtf": spec.name + ".vtf", "vtf_format": spec.vtf_format, "vtf_width": image.shape[1],
        "vtf_height": image.shape[0], "vtf_mips": len(vtf.mip_chain(image, False)) if spec.mips else 1,
        "vtf_bytes": os.path.getsize(path), "clamp": spec.clamp, "round_trip_max_error": error,
    }


def main(argv=None, quiet=False):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("game", help="the Crysis Game folder (Textures.pak, GameData.pak, Objects.pak)")
    parser.add_argument("--out", required=True, help="folder for the VTF files (not under a materials folder)")
    parser.add_argument("--png", help="also write the decoded pictures here (a PNG per texture)")
    parser.add_argument("--manifest", help="write what was read (sizes, formats, mips, errors) as JSON")
    parser.add_argument("--only", nargs="+", metavar="NAME", help="only these textures")
    args = parser.parse_args(argv)

    if not os.path.isdir(args.game):
        parser.error(f"not a folder: {args.game}")
    parts = [p.lower() for p in os.path.normpath(os.path.abspath(args.out)).split(os.sep)]
    if "materials" in parts:
        parser.error("--out is under a materials folder: the textures are not placed in the addon by this tool")
    specs = SPECS
    if args.only:
        unknown = set(args.only) - {s.name for s in SPECS}
        if unknown:
            parser.error("unknown texture: " + ", ".join(sorted(unknown)))
        specs = tuple(s for s in SPECS if s.name in args.only)

    entries = []
    for spec in specs:
        entry = convert(spec, args.game, args.out, args.png)
        entries.append(entry)
        if not quiet:
            print(f"{spec.name}: {entry['dds_format']} {entry['width']}x{entry['height']}"
                  f"{'x%d' % entry['depth'] if entry['volume'] else ''} -> {entry['vtf']} "
                  f"({entry['vtf_format']}, {entry['vtf_bytes']} bytes, max error {entry['round_trip_max_error']})")
    if args.manifest:
        with open(args.manifest, "w", encoding="utf8", newline="\n") as out:
            json.dump({"textures": entries}, out, indent=2)
            out.write("\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
