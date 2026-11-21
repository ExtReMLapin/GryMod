"""Writer for Valve Texture Files (VTF 7.2) and a DXT5 / BGRA8888 encoder, to turn the atlas PNGs into textures the
engine loads by itself (no synchronous PNG decoding when a part of the interface comes up) and keeps four times
smaller in video memory (DXT5: one byte per pixel, against four for the RGBA8 texture a PNG becomes).

    python -m tools.flash2lua.vtf in.png out.vtf [--format dxt5|bgra8888] [--no-srgb] [--no-mips]

Everything works on (height, width, 4) uint8 arrays. The colours of the atlases are sRGB-encoded (see rasterize.py),
so a texture made from them carries the sRGB flag: the engine decodes it when it samples it, like it does for PNGs,
and the mip levels are averaged in linear light, like a renderer that draws the shapes smaller would.
"""
import argparse
import os
import struct

import numpy as np
from PIL import Image

FORMATS = {"rgba8888": 0, "i8": 5, "bgra8888": 12, "dxt1": 13, "dxt5": 15}

FLAG_CLAMPS = 0x4
FLAG_CLAMPT = 0x8
FLAG_SRGB = 0x40
FLAG_NOMIP = 0x100
FLAG_NOLOD = 0x200
FLAG_EIGHTBITALPHA = 0x2000

HEADER_SIZE = 80


def _srgb_decode_table():
    x = np.arange(256) / 255.0
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4).astype(np.float32)


_DECODE = _srgb_decode_table()


def _srgb_encode(linear):
    x = np.clip(linear, 0.0, 1.0)
    y = np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)
    return np.clip(np.rint(y * 255.0), 0, 255).astype(np.uint8)


def _halved(rgba, srgb):
    """One mip level down: the mean of each 2x2 block (a side of one pixel stays as it is)."""
    h, w = rgba.shape[:2]
    nh, nw = max(1, h // 2), max(1, w // 2)
    sy, sx = (2 if h > 1 else 1), (2 if w > 1 else 1)
    acc_c = np.zeros((nh, nw, 3), dtype=np.float32)
    acc_a = np.zeros((nh, nw), dtype=np.float32)
    for dy in range(sy):
        for dx in range(sx):
            part = rgba[dy:dy + nh * sy:sy, dx:dx + nw * sx:sx]
            acc_c += _DECODE[part[:, :, :3]] if srgb else part[:, :, :3].astype(np.float32) / 255.0
            acc_a += part[:, :, 3]
    acc_c /= sy * sx
    out = np.zeros((nh, nw, 4), dtype=np.uint8)
    out[:, :, :3] = _srgb_encode(acc_c) if srgb else np.clip(np.rint(acc_c * 255.0), 0, 255).astype(np.uint8)
    out[:, :, 3] = np.clip(np.rint(acc_a / (sy * sx)), 0, 255).astype(np.uint8)
    return out


def mip_chain(rgba, srgb=True):
    """[full size, half, ... 1x1]."""
    chain = [rgba]
    while chain[-1].shape[0] > 1 or chain[-1].shape[1] > 1:
        chain.append(_halved(chain[-1], srgb))
    return chain


# ---------------------------------------------------------------------------------------------------------------
# DXT5

def _to_blocks(rgba):
    h, w = rgba.shape[:2]
    ph, pw = (h + 3) // 4 * 4, (w + 3) // 4 * 4
    if (ph, pw) != (h, w):
        rgba = np.pad(rgba, ((0, ph - h), (0, pw - w), (0, 0)), mode="edge")
    blocks = rgba.reshape(ph // 4, 4, pw // 4, 4, 4).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 4)

    return blocks


def _expand565(v):
    r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
    return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], axis=-1).astype(np.float32)


def _pack565(rgb):
    c = np.clip(np.rint(rgb), 0, 255).astype(np.int32)
    r = np.clip(np.rint(c[..., 0] * 31 / 255.0), 0, 31).astype(np.int32)
    g = np.clip(np.rint(c[..., 1] * 63 / 255.0), 0, 63).astype(np.int32)
    b = np.clip(np.rint(c[..., 2] * 31 / 255.0), 0, 31).astype(np.int32)
    return (r << 11) | (g << 5) | b


_COEF = np.array([1.0, 0.0, 2.0 / 3.0, 1.0 / 3.0], dtype=np.float32)  # weight of c0 in palette entries 0..3


def _palette(c0, c1):
    """(N, 4, 3) colours of the four-colour mode, from the two 565 endpoints (c0 > c1)."""
    e0, e1 = _expand565(c0), _expand565(c1)
    return _COEF[None, :, None] * e0[:, None, :] + (1.0 - _COEF)[None, :, None] * e1[:, None, :]


def _indices(pix, weights, pal):
    d = ((pix[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(axis=3)  # (N, 16, 4)
    idx = d.argmin(axis=2)
    err = (np.take_along_axis(d, idx[:, :, None], axis=2)[:, :, 0] * weights).sum(axis=1)

    return idx, err


def _color_blocks(pix, alpha):
    """pix (N, 16, 3) float, alpha (N, 16) 0..255 -> (c0, c1 as 565 ints, idx (N, 16))."""
    n = pix.shape[0]
    w = 0.02 + alpha / 255.0
    wsum = w.sum(axis=1)
    mean = (pix * w[:, :, None]).sum(axis=1) / wsum[:, None]
    d = pix - mean[:, None, :]
    cov = np.einsum("nk,nki,nkj->nij", w, d, d)
    # power iteration from the column of the covariance with the largest variance (the range of the channels can be
    # orthogonal to the main axis: red against blue)
    diag = np.einsum("nii->ni", cov)
    axis = np.take_along_axis(cov, diag.argmax(axis=1)[:, None, None], axis=2)[:, :, 0]
    flat = (axis ** 2).sum(axis=1) < 1e-12
    axis = np.where(flat[:, None], np.array([0.57735, 0.57735, 0.57735], dtype=np.float32), axis)
    for _ in range(5):
        norm = np.sqrt((axis ** 2).sum(axis=1, keepdims=True))
        axis = axis / np.maximum(norm, 1e-12)
        axis = np.where(flat[:, None], axis, np.einsum("nij,nj->ni", cov, axis))
    norm = np.sqrt((axis ** 2).sum(axis=1, keepdims=True))
    axis = axis / np.maximum(norm, 1e-12)
    t = (d * axis[:, None, :]).sum(axis=2)
    lo = mean + axis * t.min(axis=1)[:, None]
    hi = mean + axis * t.max(axis=1)[:, None]
    best_err = np.full(n, np.inf, dtype=np.float32)
    best = [np.zeros(n, np.int32), np.zeros(n, np.int32), np.zeros((n, 16), np.int64)]

    for step in range(3):
        c_hi, c_lo = _pack565(hi), _pack565(lo)
        swap = c_hi < c_lo
        c0 = np.where(swap, c_lo, c_hi)
        c1 = np.where(swap, c_hi, c_lo)
        pal = _palette(c0, c1)
        idx, err = _indices(pix, w, pal)
        same = c0 == c1
        idx = np.where(same[:, None], 0, idx)
        err = np.where(same, (((pix - pal[:, 0:1, :]) ** 2).sum(axis=2) * w).sum(axis=1), err)
        better = err < best_err
        best_err = np.where(better, err, best_err)
        best[0] = np.where(better, c0, best[0])
        best[1] = np.where(better, c1, best[1])
        best[2] = np.where(better[:, None], idx, best[2])
        if step == 2:
            break
        # least squares: the endpoints that fit the chosen indices best
        t0 = _COEF[idx]
        t1 = 1.0 - t0
        a00 = (w * t0 * t0).sum(axis=1)
        a01 = (w * t0 * t1).sum(axis=1)
        a11 = (w * t1 * t1).sum(axis=1)
        b0 = ((w * t0)[:, :, None] * pix).sum(axis=1)
        b1 = ((w * t1)[:, :, None] * pix).sum(axis=1)
        det = a00 * a11 - a01 * a01
        ok = np.abs(det) > 1e-5
        safe = np.where(ok, det, 1.0)
        e0 = (a11[:, None] * b0 - a01[:, None] * b1) / safe[:, None]
        e1 = (a00[:, None] * b1 - a01[:, None] * b0) / safe[:, None]
        hi = np.where(ok[:, None], np.clip(e0, 0, 255), hi)
        lo = np.where(ok[:, None], np.clip(e1, 0, 255), lo)

    c0, c1, idx = best[0].astype(np.int32), best[1].astype(np.int32), best[2]
    # a flat colour only lands on a multiple of the 565 step: move one endpoint a step to use the thirds in between
    for _ in range(2):
        cur_pal = _palette(c0, c1)
        cur_idx, cur_err = _indices(pix, w, cur_pal)
        improved = False
        for shift in (11, 5, 0):
            for end in (0, 1):
                for delta in (-1, 1):
                    limit = 63 if shift == 5 else 31
                    field = (c0 if end == 0 else c1) >> shift & limit
                    moved = field + delta
                    ok = (moved >= 0) & (moved <= limit)
                    trial = (c0 if end == 0 else c1) + np.where(ok, delta << shift, 0)
                    t0, t1 = (trial, c1) if end == 0 else (c0, trial)
                    lo_c, hi_c = np.minimum(t0, t1), np.maximum(t0, t1)
                    pal = _palette(hi_c, lo_c)
                    new_idx, err = _indices(pix, w, pal)
                    same = hi_c == lo_c
                    new_idx = np.where(same[:, None], 0, new_idx)
                    err = np.where(same, (((pix - pal[:, 0:1, :]) ** 2).sum(axis=2) * w).sum(axis=1), err)
                    better = err < cur_err - 1e-6
                    if better.any():
                        improved = True
                        c0 = np.where(better, hi_c, c0)
                        c1 = np.where(better, lo_c, c1)
                        cur_err = np.where(better, err, cur_err)
                        cur_idx = np.where(better[:, None], new_idx, cur_idx)
        idx = cur_idx
        if not improved:
            break

    return c0.astype(np.uint16), c1.astype(np.uint16), idx


def _alpha_blocks(alpha):
    """alpha (N, 16) float -> (byte0, byte1 (N,), idx (N, 16)): the better of the eight-level mode and the six-level
    mode (which keeps 0 and 255 exact)."""
    n = alpha.shape[0]
    amax, amin = alpha.max(axis=1), alpha.min(axis=1)
    k = np.arange(8, dtype=np.float32)

    # eight levels: a0 > a1
    a0, a1 = np.rint(amax), np.rint(amin)
    pal8 = np.empty((n, 8), dtype=np.float32)
    pal8[:, 0], pal8[:, 1] = a0, a1
    for i in range(2, 8):
        pal8[:, i] = ((8 - i) * a0 + (i - 1) * a1) / 7.0
    # when a0 == a1 the decoder uses the six-level mode: every index must then point at a0 or a1
    d8 = np.abs(alpha[:, :, None] - pal8[:, None, :])
    i8 = d8.argmin(axis=2)
    same = a0 == a1
    i8 = np.where(same[:, None], 0, i8)
    e8 = np.where(same, np.abs(alpha - a0[:, None]).sum(axis=1), np.take_along_axis(d8, i8[:, :, None], axis=2)[:, :, 0].sum(axis=1))

    # six levels: b0 < b1, plus 0 and 255
    inner = (alpha > 0.5) & (alpha < 254.5)
    big = np.float32(1e9)
    b0 = np.where(inner, alpha, big).min(axis=1)
    b1 = np.where(inner, alpha, -big).max(axis=1)
    none = ~inner.any(axis=1)
    b0 = np.where(none, 0, b0)
    b1 = np.where(none, 255, b1)
    b0, b1 = np.rint(b0), np.rint(b1)
    flat = b0 >= b1
    b0 = np.where(flat, np.maximum(b1 - 1, 0), b0)
    b1 = np.where(flat, np.minimum(b0 + 1, 255), b1)
    pal6 = np.empty((n, 8), dtype=np.float32)
    pal6[:, 0], pal6[:, 1] = b0, b1
    for i in range(2, 6):
        pal6[:, i] = ((6 - i) * b0 + (i - 1) * b1) / 5.0
    pal6[:, 6], pal6[:, 7] = 0.0, 255.0
    d6 = np.abs(alpha[:, :, None] - pal6[:, None, :])
    i6 = d6.argmin(axis=2)
    e6 = np.take_along_axis(d6, i6[:, :, None], axis=2)[:, :, 0].sum(axis=1)

    use6 = (e6 < e8) & ~same
    byte0 = np.where(use6, b0, a0).astype(np.uint8)
    byte1 = np.where(use6, b1, a1).astype(np.uint8)
    idx = np.where(use6[:, None], i6, i8)

    return byte0, byte1, idx


def encode_dxt5(rgba, chunk=65536):
    """DXT5 data of an (h, w, 4) uint8 image: 16 bytes per 4x4 block, row by row."""
    blocks = _to_blocks(rgba)
    out = np.empty((blocks.shape[0], 16), dtype=np.uint8)

    for start in range(0, blocks.shape[0], chunk):
        part = blocks[start:start + chunk].astype(np.float32)
        n = part.shape[0]
        a0, a1, aidx = _alpha_blocks(part[:, :, 3])
        c0, c1, cidx = _color_blocks(part[:, :, :3], part[:, :, 3])
        res = out[start:start + n]
        res[:, 0], res[:, 1] = a0, a1
        shifts = (np.arange(16, dtype=np.uint64) * 3)[None, :]
        bits = (aidx.astype(np.uint64) << shifts).sum(axis=1)
        for i in range(6):
            res[:, 2 + i] = ((bits >> np.uint64(8 * i)) & np.uint64(255)).astype(np.uint8)
        res[:, 8] = (c0 & 255).astype(np.uint8)
        res[:, 9] = (c0 >> 8).astype(np.uint8)
        res[:, 10] = (c1 & 255).astype(np.uint8)
        res[:, 11] = (c1 >> 8).astype(np.uint8)
        cbits = (cidx.astype(np.uint64) << (np.arange(16, dtype=np.uint64) * 2)[None, :]).sum(axis=1)
        for i in range(4):
            res[:, 12 + i] = ((cbits >> np.uint64(8 * i)) & np.uint64(255)).astype(np.uint8)

    return out.tobytes()


def decode_dxt5(data, width, height):
    """The image (height, width, 4) a DXT5 data stream stands for (a GPU's decoding, to the rounding)."""
    bw, bh = (width + 3) // 4, (height + 3) // 4
    raw = np.frombuffer(data, dtype=np.uint8).reshape(-1, 16)
    n = raw.shape[0]
    assert n == bw * bh, (n, bw, bh)
    a0, a1 = raw[:, 0].astype(np.float32), raw[:, 1].astype(np.float32)
    bits = np.zeros(n, dtype=np.uint64)
    for i in range(6):
        bits |= raw[:, 2 + i].astype(np.uint64) << np.uint64(8 * i)
    aidx = ((bits[:, None] >> (np.arange(16, dtype=np.uint64) * 3)[None, :]) & np.uint64(7)).astype(np.int64)
    pal = np.empty((n, 8), dtype=np.float32)
    pal[:, 0], pal[:, 1] = a0, a1
    eight = raw[:, 0] > raw[:, 1]
    for i in range(2, 8):
        pal[:, i] = np.where(eight, ((8 - i) * a0 + (i - 1) * a1) / 7.0,
                             ((6 - i) * a0 + (i - 1) * a1) / 5.0 if i < 6 else (0.0 if i == 6 else 255.0))
    alpha = np.take_along_axis(pal, aidx, axis=1)
    c0 = raw[:, 8].astype(np.uint16) | (raw[:, 9].astype(np.uint16) << 8)
    c1 = raw[:, 10].astype(np.uint16) | (raw[:, 11].astype(np.uint16) << 8)
    cpal = _palette(c0.astype(np.int32), c1.astype(np.int32))
    cbits = np.zeros(n, dtype=np.uint64)
    for i in range(4):
        cbits |= raw[:, 12 + i].astype(np.uint64) << np.uint64(8 * i)
    cidx = ((cbits[:, None] >> (np.arange(16, dtype=np.uint64) * 2)[None, :]) & np.uint64(3)).astype(np.int64)
    rgb = np.take_along_axis(cpal, cidx[:, :, None], axis=1)
    out = np.empty((n, 16, 4), dtype=np.float32)
    out[:, :, :3], out[:, :, 3] = rgb, alpha
    img = np.rint(out).clip(0, 255).astype(np.uint8)
    img = img.reshape(bh, bw, 4, 4, 4).transpose(0, 2, 1, 3, 4).reshape(bh * 4, bw * 4, 4)

    return img[:height, :width]


# ---------------------------------------------------------------------------------------------------------------
# VTF

def _mip_bytes(rgba, fmt):
    if fmt == "dxt5":
        return encode_dxt5(rgba)
    if fmt == "bgra8888":
        return np.ascontiguousarray(rgba[:, :, [2, 1, 0, 3]]).tobytes()
    if fmt == "rgba8888":
        return np.ascontiguousarray(rgba).tobytes()
    if fmt == "i8":
        # one byte per pixel: the red channel (the engine reads it back as grey, alpha 255)
        return np.ascontiguousarray(rgba[:, :, 0]).tobytes()
    raise ValueError(fmt)


def vtf_bytes(rgba, fmt="dxt5", srgb=True, mips=True, nolod=True, clamp="st"):
    """The content of a VTF 7.2 file for an (h, w, 4) uint8 image (sizes are powers of two).

    clamp: the axes whose texture coordinates are clamped ("s" and/or "t", "" for a texture that repeats on both)."""
    depth = 1
    if rgba.ndim == 4:
        # a volume texture: (depth, height, width, 4), the slices one after the other, with no mip levels
        depth = rgba.shape[0]
        if depth & (depth - 1):
            raise ValueError("the depth of a volume texture is a power of two")
        if mips:
            raise ValueError("a volume texture is written without mip levels")
    h, w = rgba.shape[-3:-1]
    if w & (w - 1) or h & (h - 1):
        raise ValueError("the size of a texture is a power of two")
    if set(clamp) - set("st"):
        raise ValueError(f"clamp is made of 's' and 't': {clamp!r}")
    slices = list(rgba) if depth > 1 or rgba.ndim == 4 else [rgba]
    chain = mip_chain(rgba, srgb) if mips else [slices[0]]
    flags = (FLAG_CLAMPS if "s" in clamp else 0) | (FLAG_CLAMPT if "t" in clamp else 0)
    if srgb:
        flags |= FLAG_SRGB
    if not mips:
        flags |= FLAG_NOMIP
    if nolod:
        flags |= FLAG_NOLOD
    if (rgba[..., 3] != 255).any():
        flags |= FLAG_EIGHTBITALPHA
    header = struct.pack("<4sIIIHHIHH4x3f4xfiBibbH", b"VTF\0", 7, 2, HEADER_SIZE, w, h, flags, 1, 0,
                         0.5, 0.5, 0.5, 1.0, FORMATS[fmt], len(chain), -1, 0, 0, depth)
    header = header.ljust(HEADER_SIZE, b"\0")
    if depth > 1 or rgba.ndim == 4:
        body = b"".join(_mip_bytes(piece, fmt) for piece in slices)
    else:
        body = b"".join(_mip_bytes(level, fmt) for level in reversed(chain))

    return header + body


def write_vtf(path, rgba, fmt="dxt5", srgb=True, mips=True, nolod=True, clamp="st"):
    with open(path, "wb") as out:
        out.write(vtf_bytes(rgba, fmt, srgb, mips, nolod, clamp))


def read_vtf_top(path):
    """The biggest image of a VTF this module wrote (DXT5, BGRA8888, RGBA8888 or I8), as (h, w, 4) uint8: tests and comparisons."""
    with open(path, "rb") as source:
        raw = source.read()
    width, height = struct.unpack_from("<HH", raw, 16)
    fmt = struct.unpack_from("<i", raw, 52)[0]
    levels = raw[56]

    def size(level):
        w, h = max(1, width >> level), max(1, height >> level)
        if fmt == FORMATS["dxt5"]:
            return ((w + 3) // 4) * ((h + 3) // 4) * 16
        if fmt == FORMATS["i8"]:
            return w * h
        return w * h * 4

    top = size(0)
    start = len(raw) - top
    assert start == HEADER_SIZE + sum(size(m) for m in range(1, levels))
    data = raw[start:]
    if fmt == FORMATS["dxt5"]:
        return decode_dxt5(data, width, height)
    if fmt == FORMATS["i8"]:
        grey = np.frombuffer(data, dtype=np.uint8).reshape(height, width)
        return np.stack([grey, grey, grey, np.full_like(grey, 255)], axis=2)
    arr = np.frombuffer(data, dtype=np.uint8).reshape(height, width, 4)
    if fmt == FORMATS["bgra8888"]:
        arr = arr[:, :, [2, 1, 0, 3]]

    return arr.copy()


def vmt_text(texture):
    """The material of an atlas texture, like the engine makes one of a PNG (see cl_flash_draw.lua)."""
    return ('"UnlitGeneric"\n{\n\t"$basetexture" "%s"\n\t"$vertexcolor" 1\n\t"$vertexalpha" 1\n\t"$nocull" 1\n'
            '\t"$linearwrite" 1\n}\n' % texture)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source")
    parser.add_argument("target")
    parser.add_argument("--format", default="dxt5", choices=["dxt5", "bgra8888", "rgba8888"])
    parser.add_argument("--no-srgb", action="store_true")
    parser.add_argument("--no-mips", action="store_true")
    args = parser.parse_args()
    rgba = np.asarray(Image.open(args.source).convert("RGBA"))
    write_vtf(args.target, rgba, args.format, srgb=not args.no_srgb, mips=not args.no_mips)
    print(os.path.getsize(args.target), "bytes")


if __name__ == "__main__":
    main()
