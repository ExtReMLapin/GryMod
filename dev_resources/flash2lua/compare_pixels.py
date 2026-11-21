"""Compare two renders of the HUD (FFDec's and the game's) pixel by pixel.

    python -m dev_resources.flash2lua.compare_pixels ref.png got.png --bg 51,51,51 [--tolerance 16] [--diff diff.png]

`content` = pixels that are not the background in at least one image; `different` = content pixels whose
largest channel difference exceeds the tolerance; `fraction` = different / content.
"""
import argparse
import json

import numpy as np
from PIL import Image


def compare(ref_path, got_path, bg, tolerance=16, diff_path=None):
    ref = np.asarray(Image.open(ref_path).convert("RGB")).astype(int)
    got = np.asarray(Image.open(got_path).convert("RGB")).astype(int)
    if ref.shape != got.shape:
        raise ValueError(f"size mismatch: {ref.shape} vs {got.shape}")
    background = np.array(bg).reshape(1, 1, 3)
    content = (np.abs(ref - background).max(axis=2) > 2) | (np.abs(got - background).max(axis=2) > 2)
    delta = np.abs(ref - got).max(axis=2)
    different = content & (delta > tolerance)
    if diff_path:
        out = np.zeros(ref.shape, dtype=np.uint8)
        out[content] = (60, 60, 60)
        out[different] = (255, 0, 0)
        Image.fromarray(out).save(diff_path)
    n_content = int(content.sum())
    n_different = int(different.sum())
    return {"content": n_content, "different": n_different,
            "fraction": (n_different / n_content) if n_content else 0.0}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ref")
    parser.add_argument("got")
    parser.add_argument("--bg", default="51,51,51")
    parser.add_argument("--tolerance", type=int, default=16)
    parser.add_argument("--diff")
    args = parser.parse_args()
    bg = tuple(int(v) for v in args.bg.split(","))
    print(json.dumps(compare(args.ref, args.got, bg, args.tolerance, args.diff)))


if __name__ == "__main__":
    main()
