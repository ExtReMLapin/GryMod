"""Generates materials/grymod/cloak/cloak_lines.vtf, the tiled picture of the camouflage's scan lines: blotches of
electric blue crossed by fine horizontal lines (cl_cloak_lines.lua draws it in screen space over the silhouette of a
camouflaged player and moves it every frame). Only numpy is used (no pip): the VTF file is written here.

    python tools/make_cloak_lines.py

512 x 512, RGBA8888, no mipmaps, point sampled (the lines stay sharp), tiling. The blotches are smooth value noise at three
scales with a fixed seed, so the picture tiles and always comes out the same. One texel is one pixel of a 1080 screen (the
Lua scales the quad on other heights). The lines are PERIOD texels apart, the first half of each period bright.
"""
import os
import struct
import sys

import numpy as np

SIZE = 512
PERIOD = 4
SEED = 20261122
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "materials", "grymod", "cloak", "cloak_lines.vtf")

BLUE = np.array([0.30, 0.45, 1.0])
WHITE = np.array([0.75, 0.85, 1.0])


def smooth(t):
    return t * t * (3 - 2 * t)


def value_noise(size, cells, rng):
    """Smooth periodic noise in [0, 1]: random values on a cells x cells grid that wraps, blended with a smoothstep."""
    grid = rng.random((cells, cells))
    coords = np.arange(size) * cells / size
    i0 = np.floor(coords).astype(int) % cells
    i1 = (i0 + 1) % cells
    f = smooth(coords - np.floor(coords))
    top = grid[np.ix_(i0, i0)] * (1 - f)[None, :] + grid[np.ix_(i0, i1)] * f[None, :]
    bottom = grid[np.ix_(i1, i0)] * (1 - f)[None, :] + grid[np.ix_(i1, i1)] * f[None, :]

    return top * (1 - f)[:, None] + bottom * f[:, None]


def blotches(size, rng):
    n = 0.5 * value_noise(size, 8, rng) + 0.3 * value_noise(size, 16, rng) + 0.2 * value_noise(size, 32, rng)

    return np.clip((n - 0.48) / 0.28, 0, 1) ** 1.4


def lines(size, period):
    """1 on the first half of every period, a faint 0.12 on the rest (the lines are dark gaps, not black bars)."""
    row = np.where(np.arange(size) % period < period // 2, 1.0, 0.12)

    return np.repeat(row[:, None], size, axis=1)


def picture(rng):
    b = blotches(SIZE, rng)
    v = b * lines(SIZE, PERIOD)
    core = np.clip((b - 0.7) / 0.3, 0, 1)[..., None]
    colour = BLUE * (1 - core) + WHITE * core
    rgba = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    rgba[..., :3] = np.clip(colour * v[..., None] * 255 + 0.5, 0, 255)
    rgba[..., 3] = 255

    return rgba


def vtf(rgba):
    height, width = rgba.shape[:2]
    flags = 0x01 | 0x100 | 0x200  # POINTSAMPLE, NOMIP, NOLOD: not clamped, so it tiles
    header = bytearray(80)
    header[0:4] = b"VTF\0"
    struct.pack_into("<II", header, 4, 7, 2)
    struct.pack_into("<I", header, 12, 80)
    struct.pack_into("<HH", header, 16, width, height)
    struct.pack_into("<I", header, 20, flags)
    struct.pack_into("<HH", header, 24, 1, 0)
    struct.pack_into("<fff", header, 32, 0.5, 0.5, 1.0)
    struct.pack_into("<f", header, 48, 1.0)
    struct.pack_into("<i", header, 52, 0)  # IMAGE_FORMAT_RGBA8888
    header[56] = 1
    struct.pack_into("<i", header, 57, -1)
    struct.pack_into("<H", header, 63, 1)

    return bytes(header) + rgba.tobytes()


def main():
    rng = np.random.default_rng(SEED)
    data = vtf(picture(rng))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)

    with open(OUT, "wb") as f:
        f.write(data)

    print("%s: %d bytes" % (os.path.normpath(OUT), len(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
