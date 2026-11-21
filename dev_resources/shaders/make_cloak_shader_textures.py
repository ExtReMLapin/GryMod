"""Writes the textures the camouflage's pixel shader reads, from the originals that dev_resources/cloak/extract_cloak_textures.py puts in its `dds` folder.

    python dev_resources/shaders/make_cloak_shader_textures.py DDS_DIR [--out-dir materials/grymod/cloak]

- noise3d.vtf          the original's 128 cube of noise, a real VOLUME texture (one 8-bit channel, repeating, data: no sRGB, no mips);
- spark_profile.vtf    the 256 x 1 colours of cloak_sparks, read at three offsets of the noise (repeating along the row);
- cloak_palette.vtf    the 256 x 1 rim colours of the refraction layer, indexed by the scan lines' G times (1 - N.V);
- cloak_interlation.vtf  the 256 x 1 scan lines (R and G modulate the bend and the rim, repeating along the row).

The shader itself is grymod_cloak_*.hlsl next to this file (build_shaders.py compiles it into shaders/fxc); the material that runs it is made by
lua/grymod/client/cl_cloak_shader.lua. Both textures are DATA the shader calculates with, so that material reads them without the engine's sRGB
conversion ($linearread_*). Holds no resource of the game.

Needs Python 3.12 and numpy.
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))

from dev_resources.cloak import extract_cloak_textures as ect  # noqa: E402
from dev_resources.flash2lua import vtf  # noqa: E402


def noise_volume_bytes(volume):
    """The VTF of a (depth, height, width, 4) volume: only its first channel is kept (the noise), repeating, no mips."""
    return vtf.vtf_bytes(volume, "i8", srgb=False, mips=False, clamp="")


# The original's sparks are thin lines that its HDR output and bloom make glow; Source here has neither, so the peaks of the profile are widened
# and brightened a little in the data itself (the lines of the noise they are read through get thicker, in step with the peaks).
PROFILE_GLOW_RADIUS = 2
PROFILE_GLOW_GAIN = 2.0


def glow_profile(profile, radius=PROFILE_GLOW_RADIUS, gain=PROFILE_GLOW_GAIN):
    """(n, 3) floats 0..1 -> the same with every channel's peaks widened by `radius` texels and brightened: never dimmer than the input,
    at most 1, and wrapping round the ends (the profile repeats)."""
    if radius <= 0:
        return profile.copy()

    acc = np.zeros_like(profile, dtype=np.float64)
    for shift in range(-radius, radius + 1):
        acc += np.roll(profile, shift, axis=0)

    return np.clip(np.maximum(profile, acc / (2 * radius + 1) * gain), 0.0, 1.0)


def spark_profile_bytes(profile):
    """The VTF of the (1, 256, 4) spark profile, glowing: colours that repeat along the row, no mips, no sRGB."""
    rgb = profile[0, :, :3].astype(np.float64) / 255
    out = profile.copy()
    out[0, :, :3] = np.round(glow_profile(rgb) * 255).astype(np.uint8)

    return vtf.vtf_bytes(out, "rgba8888", srgb=False, mips=False, clamp="t")


def palette_bytes(row):
    """The VTF of the (1, 256, 4) palette of the refraction layer: clamped on both axes, read as data."""
    return vtf.vtf_bytes(row, "rgba8888", srgb=False, mips=False, clamp="st")


def interlation_bytes(row):
    """The VTF of the (1, 256, 4) scan lines: repeating along the row, no mips, read as data."""
    return vtf.vtf_bytes(row, "rgba8888", srgb=False, mips=False, clamp="t")


def load_inputs(dds_dir):
    def read(name):
        with open(os.path.join(dds_dir, name), "rb") as f:
            return ect.decode_dds(f.read())[1]

    return read("noise3d.dds"), read("cloak_sparks.dds"), read("cloak_palette.dds"), read("cloak_interlation.dds")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("dds_dir")
    parser.add_argument("--out-dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "materials", "grymod", "cloak"))
    args = parser.parse_args(argv)

    volume, profile, palette, interlation = load_inputs(args.dds_dir)
    os.makedirs(args.out_dir, exist_ok=True)
    files = {
        "noise3d.vtf": noise_volume_bytes(volume),
        "spark_profile.vtf": spark_profile_bytes(profile),
        "cloak_palette.vtf": palette_bytes(palette[0]),
        "cloak_interlation.vtf": interlation_bytes(interlation[0]),
    }
    for name, data in files.items():
        with open(os.path.join(args.out_dir, name), "wb") as out:
            out.write(data)
        print("%s: %d bytes" % (os.path.normpath(os.path.join(args.out_dir, name)), len(data)))

    return 0


if __name__ == "__main__":
    sys.exit(main())
