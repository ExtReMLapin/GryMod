"""Numerical reproduction of the quick menu pointer (see docs/superpowers/plans/2026-11-21-quickmenu-pointer-research.md).

Models a mouse moving at a constant velocity towards the bottom right (counts reported at 1 kHz, integers, with an optional
lateral hand tremor), sampled by frames of 30 to 240 fps, and feeds it to:
  orig   the game's rule on every frame: v += delta, clamp to 25, reset under 12.5 (what the first port did)
  fixedN the same rule run on a fixed clock of 1/N s (the frame's counts spread evenly over the frame), the angle shown eased
For each: the standard deviation of the angle, its peak-to-peak range and the number of direction reversals per second.

Run: python -I tools/quickmenu_pointer_sim.py
"""

import math
import random
import statistics


def theta(x, y):
    length = math.hypot(x, y)
    if length == 0:
        return 0.0
    angle = math.degrees(math.acos(max(-1.0, min(1.0, x / length))))
    if y >= 0:
        angle = 360 - angle
    return angle % 360


def angdiff(a, b):
    return (a - b + 180) % 360 - 180


class Pointer:
    SELECT, RELEASE = 25.0, 12.5

    def __init__(self):
        self.x = self.y = 0.0
        self.active = False
        self.move(0, -30)  # the game's start vector for the Speed mode

    def move(self, dx, dy):
        self.x += dx
        self.y += dy
        length = math.hypot(self.x, self.y)
        if self.active and length < self.RELEASE:
            self.x = self.y = 0.0
            self.active = False
        elif length > self.SELECT:
            self.x, self.y = self.x / length * self.SELECT, self.y / length * self.SELECT
            self.active = True


def mouse_counts(speed, angle_deg, seconds, rng, tremor=0.0, hz=1000):
    """Integer counts reported at `hz`; the path is a constant velocity plus a lateral tremor (AR(1) noise)."""
    a = math.radians(angle_deg)
    ux, uy = math.cos(a), math.sin(a)
    px = py = 0.0
    cx = cy = 0
    lateral = 0.0
    dt = 1.0 / hz
    out = []
    for i in range(int(seconds * hz)):
        lateral = 0.98 * lateral + rng.gauss(0, 1) * tremor * speed * 0.2
        px += (ux * speed - uy * lateral) * dt
        py += (uy * speed + ux * lateral) * dt
        nx, ny = math.floor(px), math.floor(py)
        out.append(((i + 1) * dt, nx - cx, ny - cy))
        cx, cy = nx, ny
    return out


def frames(counts, fps, rng, jitter=0.1):
    out = []
    ax = ay = 0
    nxt = rng.uniform(0, 1 / fps)
    last = 0.0
    for t, dx, dy in counts:
        ax += dx
        ay += dy
        if t >= nxt:
            out.append((t, t - last, ax, ay))
            last = t
            ax = ay = 0
            nxt += (1 / fps) * (1 + rng.uniform(-jitter, jitter))
    return out


def run_orig(fr):
    p = Pointer()
    out = []
    for t, dt, dx, dy in fr:
        p.move(dx, dy)
        out.append((t, theta(p.x, p.y) if p.active else None))
    return out


def run_fixed(fr, step, tau):
    p = Pointer()
    shown = theta(p.x, p.y)
    pend = 0.0
    px = py = 0.0
    out = []
    for t, dt, dx, dy in fr:
        vx, vy = dx / dt, dy / dt
        left = dt
        while left > 1e-12:
            use = min(step - pend, left)
            px += vx * use
            py += vy * use
            pend += use
            left -= use
            if p.active and tau > 0:
                shown = (shown + angdiff(theta(p.x, p.y), shown) * (1 - math.exp(-use / tau))) % 360
            if pend >= step - 1e-12:
                was = p.active
                p.move(px, py)
                px = py = pend = 0.0
                if p.active and not was:
                    shown = theta(p.x, p.y)
                elif p.active and tau <= 0:
                    shown = theta(p.x, p.y)
        out.append((t, shown if p.active else None))
    return out


def metrics(res, warm=0.6):
    th = [a for t, a in res if t >= warm and a is not None]
    d = [angdiff(th[i + 1], th[i]) for i in range(len(th) - 1)]
    reversals = sum(1 for i in range(len(d) - 1) if d[i] * d[i + 1] < 0)
    return statistics.pstdev(th), max(th) - min(th), reversals / (res[-1][0] - warm)


def main():
    designs = {
        "orig": run_orig,
        "fixed 1/60 + ease 20 ms": lambda fr: run_fixed(fr, 1 / 60, 0.020),
        "fixed 1/30 + ease 15 ms": lambda fr: run_fixed(fr, 1 / 30, 0.015),
    }
    for tremor in (0.0, 0.05, 0.15):
        print(f"tremor {tremor}: sd / peak-to-peak (deg) / direction reversals per second")
        for speed in (400, 1600):
            counts = mouse_counts(speed, 35.3, 4.0, random.Random(7), tremor)
            for name, fn in designs.items():
                row = []
                for fps in (30, 60, 166, 240):
                    m = metrics(fn(frames(counts, fps, random.Random(3))))
                    row.append(f"{fps} fps {m[0]:4.1f}/{m[1]:5.1f}/{m[2]:4.0f}")
                print(f"  {speed:5d} c/s {name:24s} " + " | ".join(row))


if __name__ == "__main__":
    main()
