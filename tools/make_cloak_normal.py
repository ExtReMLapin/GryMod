"""Generates materials/grymod/cloak/cloak_n.vtf, the small tileable normal map that bends the picture behind a
camouflaged player. Only numpy is used (no pip): the VTF file is written here, uncompressed, with its mipmaps.

    python tools/make_cloak_normal.py

The map is made of a few waves with random phases (a fixed seed), so it tiles and always comes out the same.
128 x 128, RGBA8888, mipmaps: about 87 KB of video memory.
"""
import os
import struct
import sys

import numpy as np

SIZE = 128
SEED = 20261121
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "materials", "grymod", "cloak", "cloak_n.vtf")


def height_field(size, rng):
    """Sum of periodic waves: wide slow ones for the ripple, small ones for the shimmer."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float64) / size
    h = np.zeros((size, size))

    for cycles, amplitude, count in ((1, 1.0, 3), (2, 0.7, 4), (4, 0.4, 5), (8, 0.18, 6)):
        for _ in range(count):
            kx = rng.integers(-cycles, cycles + 1)
            ky = rng.integers(-cycles, cycles + 1)

            if kx == 0 and ky == 0:
                kx = cycles

            phase = rng.uniform(0, 2 * np.pi)
            h += amplitude / count * np.sin(2 * np.pi * (kx * x + ky * y) + phase)

    return h


def normal_map(h, strength):
    """Tangent-space normals from the gradient of a tiling height field (the edges wrap around)."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(h)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    return nx / length, ny / length, nz / length


def to_rgba(n):
    nx, ny, nz = n
    rgba = np.zeros(nx.shape + (4,), dtype=np.uint8)
    rgba[..., 0] = np.clip((nx * 0.5 + 0.5) * 255 + 0.5, 0, 255)
    rgba[..., 1] = np.clip((ny * 0.5 + 0.5) * 255 + 0.5, 0, 255)
    rgba[..., 2] = np.clip((nz * 0.5 + 0.5) * 255 + 0.5, 0, 255)
    rgba[..., 3] = 255
    return rgba


def mip_chain(rgba):
    """Halves the picture down to 1x1, renormalising the normals at every step."""
    chain = [rgba]

    while chain[-1].shape[0] > 1:
        prev = chain[-1].astype(np.float64)
        v = prev[..., :3] / 255 * 2 - 1
        v = (v[0::2, 0::2] + v[1::2, 0::2] + v[0::2, 1::2] + v[1::2, 1::2]) / 4
        length = np.maximum(np.sqrt((v * v).sum(axis=-1, keepdims=True)), 1e-6)
        v = v / length
        nxt = np.zeros(v.shape[:2] + (4,), dtype=np.uint8)
        nxt[..., :3] = np.clip((v * 0.5 + 0.5) * 255 + 0.5, 0, 255)
        nxt[..., 3] = 255
        chain.append(nxt)

    return chain


def vtf(chain):
    width = chain[0].shape[1]
    height = chain[0].shape[0]
    flags = 0x80 | 0x02  # NORMAL, TRILINEAR
    header = bytearray(80)
    header[0:4] = b"VTF\0"
    struct.pack_into("<II", header, 4, 7, 2)
    struct.pack_into("<I", header, 12, 80)
    struct.pack_into("<HH", header, 16, width, height)
    struct.pack_into("<I", header, 20, flags)
    struct.pack_into("<HH", header, 24, 1, 0)  # frames, first frame
    struct.pack_into("<fff", header, 32, 0.5, 0.5, 1.0)  # reflectivity
    struct.pack_into("<f", header, 48, 1.0)  # bump scale
    struct.pack_into("<i", header, 52, 0)  # IMAGE_FORMAT_RGBA8888
    header[56] = len(chain)  # mipmap count
    struct.pack_into("<i", header, 57, -1)  # no thumbnail
    header[61] = 0
    header[62] = 0
    struct.pack_into("<H", header, 63, 1)  # depth
    body = b"".join(level.tobytes() for level in reversed(chain))  # smallest mip first
    return bytes(header) + body


def main():
    rng = np.random.default_rng(SEED)
    h = height_field(SIZE, rng)
    h = h / np.abs(h).max()
    data = vtf(mip_chain(to_rgba(normal_map(h, 6.0))))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)

    with open(OUT, "wb") as f:
        f.write(data)

    print("%s: %d bytes" % (os.path.normpath(OUT), len(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
