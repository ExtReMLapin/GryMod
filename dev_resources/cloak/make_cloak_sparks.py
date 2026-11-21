"""Pre-computes the picture of the camouflage's electric sparks from the original game's own textures, for GryMod.

    python dev_resources/cloak/make_cloak_sparks.py DDS_DIR [--out materials/grymod/cloak/cloak_sparks.vtf] [--preview FILE.png]

DDS_DIR holds the originals that dev_resources/cloak/extract_cloak_textures.py writes into its `dds` folder (noise3d.dds, cloak_sparks.dds,
cloak_interlation.dds). This tool holds no resource of the game, only the arithmetic of the shader CloakLayer.cfx (pass 2,
`CloakSparksPS`), which the Source engine cannot run:

    n  = noise3d(P + v)                      three lookups in a chain, each moved by the one before
    n  = noise3d(P + n * 0.2 + v)
    n  = noise3d(P + n * 0.4 + v)
    rgb = ( sparks.r(n + t + 0.1),  sparks.g(n * 1.53 + 2 t + 0.4),  sparks.b(n * 1.7 + 1.4 t + 0.2) )
    spark = (SparksColor * dot(rgb, 2)) ^ 2  ->  nearly pure blue, SparksColor being (0.3, 0.3, 1)
    result = interlation.a(screen row * 0.25) * spark * max(speed, transition ^ 2)

Source has no volume texture and no pixel shader here, so the picture is a SLICE of the volume, one cell per moment of the flash at the
start of the change (the volume's offset v and the time t differ from one cell to the next), the cells side by side in one I8 picture,
shown in turn 30 a second by the Lua. The interlation (a triangle wave read at 0.25 per screen row, so four rows to a period) is baked in: it multiplies
every cell; the thin lines of the sparks are widened and brightened a little (glow), standing in for the original's bloom. The
blue and the strength over time come from the Lua (cl_cloak_lines.lua): the picture is the intensity only.

Needs Python 3.12 and numpy.
"""
import argparse
import os
import sys

import numpy as np

# `python -I` and `python tools/x.py` do not put the repository on the path (tools/ is a namespace package)
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))

from dev_resources.cloak import extract_cloak_textures as ect  # noqa: E402
from dev_resources.flash2lua import vtf  # noqa: E402

FRAMES = 8
CELL = 512
# The cells are shown in turn at 30 a second in the Lua (cl_cloak_lines.lua), so they are the sparks at moments spread over a couple of
# seconds of the shader's time, not a smooth sweep: each one has its own contours. The shader's time is the game's time x 0.4 and the
# level of the change is only the first part of it (the flash is over by the time half of it is done).
TIME_STEP = 0.2
FLASH_LEVEL = 0.5
# where the slice is cut in the volume (a fixed depth, the noise has no preferred one)
SLICE_Z = 0.37


def sample_volume(vol, x, y, z):
    """Trilinear sample of a (depth, height, width) volume at voxel coordinates, wrapping in every direction."""
    depth, height, width = vol.shape
    x0, y0, z0 = np.floor(x), np.floor(y), np.floor(z)
    fx, fy, fz = x - x0, y - y0, z - z0
    xi, yi, zi = x0.astype(int), y0.astype(int), z0.astype(int)

    def at(dz, dy, dx):
        return vol[(zi + dz) % depth, (yi + dy) % height, (xi + dx) % width]

    c00 = at(0, 0, 0) * (1 - fx) + at(0, 0, 1) * fx
    c01 = at(0, 1, 0) * (1 - fx) + at(0, 1, 1) * fx
    c10 = at(1, 0, 0) * (1 - fx) + at(1, 0, 1) * fx
    c11 = at(1, 1, 0) * (1 - fx) + at(1, 1, 1) * fx
    c0 = c00 * (1 - fy) + c01 * fy
    c1 = c10 * (1 - fy) + c11 * fy

    return c0 * (1 - fz) + c1 * fz


def noise_chain(vol, px, py, pz, v):
    """The shader's three chained lookups. P is in volume units (0..1 is the whole volume); v is added to every coordinate."""
    depth, height, width = vol.shape

    def n(offset):
        return sample_volume(vol, (px + offset + v) * width, (py + offset + v) * height, (pz + offset + v) * depth)

    first = n(0.0)
    second = sample_volume(vol, (px + first * 0.2 + v) * width, (py + first * 0.2 + v) * height, (pz + first * 0.2 + v) * depth)

    return sample_volume(vol, (px + second * 0.4 + v) * width, (py + second * 0.4 + v) * height, (pz + second * 0.4 + v) * depth)


def lookup(profile, u):
    """A 1D texture read with wrapping and linear filtering (profile: 0..1 samples)."""
    size = len(profile)
    pos = np.asarray(u, dtype=np.float64) * size - 0.5
    i0 = np.floor(pos).astype(int)
    f = pos - i0

    return profile[i0 % size] * (1 - f) + profile[(i0 + 1) % size] * f


def interlation_rows(alpha, rows):
    """The alpha of the interlation texture for each screen row: the shader reads it at row x 0.25 (four rows to a period)."""
    u = (np.arange(rows) * 0.25) % 1.0

    return alpha[np.floor(u * len(alpha)).astype(int) % len(alpha)]


# The original's sparks are thin contour lines that its HDR output and bloom make glow; Source here has neither, so the lines are
# widened and brightened a little in the picture itself (a box blur that wraps, so that the cell still tiles, mixed back with a gain).
GLOW_RADIUS = 3
GLOW_GAIN = 3.0


def glow(img, radius=GLOW_RADIUS, gain=GLOW_GAIN):
    """The picture with its bright lines widened by `radius` pixels and brightened: never dimmer than the input, at most 1, wrapping."""
    if radius <= 0:
        return img.copy()

    blurred = img.astype(np.float64)
    for axis in (0, 1):
        acc = np.zeros_like(blurred)
        for shift in range(-radius, radius + 1):
            acc += np.roll(blurred, shift, axis=axis)
        blurred = acc / (2 * radius + 1)

    return np.clip(np.maximum(img, blurred * gain), 0.0, 1.0)


def build_atlas(volume, profile, interlation, frames=FRAMES, cell=CELL):
    """(cell, cell x frames) uint8: the intensity of the sparks for `frames` moments of the change, side by side.

    volume: (d, h, w) floats 0..1; profile: (n, 3) floats 0..1 (the r, g, b of cloak_sparks); interlation: (n,) floats 0..1."""
    ys, xs = np.mgrid[0:cell, 0:cell]
    px, py = xs / cell, ys / cell
    pz = np.full(px.shape, SLICE_Z)
    rows = interlation_rows(interlation, cell)[:, None]
    atlas = np.zeros((cell, cell * frames), dtype=np.uint8)

    for i in range(frames):
        level = (i + 0.5) / frames * FLASH_LEVEL        # how far the change is: the flash is the first half
        t = i * TIME_STEP                               # the shader's AnimGenParams
        variation = (t % 1.0) * 2 * 0.1 * (1 - level)   # vConstants.x with no motion
        n = noise_chain(volume, px, py, pz, variation)
        rgb = (lookup(profile[:, 0], n + t + 0.1), lookup(profile[:, 1], n * 1.53 + t * 2 + 0.4), lookup(profile[:, 2], n * 1.7 + t * 1.4 + 0.2))
        d = 2 * (rgb[0] + rgb[1] + rgb[2])
        spark = glow(np.clip(d * d, 0.0, 1.0))
        atlas[:, i * cell:(i + 1) * cell] = np.round(np.clip(spark * rows, 0.0, 1.0) * 255).astype(np.uint8)

    return atlas


def write_atlas(path, atlas):
    """The atlas as an I8 VTF: one channel, no mips, no sRGB (it is data), clamped (every cell is read inside its own bounds)."""
    rgba = np.repeat(atlas[:, :, None], 4, axis=2)
    rgba[:, :, 3] = 255
    vtf.write_vtf(path, rgba, fmt="i8", srgb=False, mips=False)


def load_inputs(dds_dir):
    def read(name):
        with open(os.path.join(dds_dir, name), "rb") as f:
            return ect.decode_dds(f.read())

    _, noise = read("noise3d.dds")
    _, sparks = read("cloak_sparks.dds")
    _, interlation = read("cloak_interlation.dds")

    volume = noise[:, :, :, 0].astype(np.float64) / 255
    profile = sparks[0, 0, :, :3].astype(np.float64) / 255
    alpha = interlation[0, 0, :, 3].astype(np.float64) / 255

    return volume, profile, alpha


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("dds_dir", help="the folder with noise3d.dds, cloak_sparks.dds and cloak_interlation.dds")
    parser.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "materials", "grymod", "cloak", "cloak_sparks.vtf"))
    parser.add_argument("--preview", help="also write the atlas as a PNG (needs Pillow)")
    args = parser.parse_args(argv)

    volume, profile, alpha = load_inputs(args.dds_dir)
    atlas = build_atlas(volume, profile, alpha)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    write_atlas(args.out, atlas)
    print("%s: %d x %d, %d cells, lit share %.3f" % (os.path.normpath(args.out), atlas.shape[1], atlas.shape[0], FRAMES, (atlas > 20).mean()))

    if args.preview:
        from PIL import Image
        Image.fromarray(atlas).save(args.preview)

    return 0


if __name__ == "__main__":
    sys.exit(main())
