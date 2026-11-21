"""Rectangle packing for the atlas sheets (MaxRects, best short side fit), with power-of-two sheets.

Texture sizes are powers of two, so a sheet wastes everything between the shapes and the next power of two:
`pack_pow2` looks for the smallest sheet (by area) every rectangle fits in, instead of filling shelves of a fixed
width and rounding the height up.
"""

MAX_SIDE = 4096


def _best_fit(free, w, h):
    best = None
    for index, (fx, fy, fw, fh) in enumerate(free):
        if w <= fw and h <= fh:
            short = min(fw - w, fh - h)
            long_ = max(fw - w, fh - h)
            key = (short, long_, fy, fx)
            if best is None or key < best[0]:
                best = (key, index, fx, fy)
    return best


def _split(free, px, py, pw, ph):
    out = []
    for fx, fy, fw, fh in free:
        if px >= fx + fw or px + pw <= fx or py >= fy + fh or py + ph <= fy:
            out.append((fx, fy, fw, fh))
            continue
        if px > fx:
            out.append((fx, fy, px - fx, fh))
        if px + pw < fx + fw:
            out.append((px + pw, fy, fx + fw - px - pw, fh))
        if py > fy:
            out.append((fx, fy, fw, py - fy))
        if py + ph < fy + fh:
            out.append((fx, py + ph, fw, fy + fh - py - ph))
    # drop the free rectangles that sit inside another one
    kept = []
    for i, a in enumerate(out):
        inside = False
        for j, b in enumerate(out):
            if i != j and a[0] >= b[0] and a[1] >= b[1] and a[0] + a[2] <= b[0] + b[2] and a[1] + a[3] <= b[1] + b[3] \
                    and (a != b or j < i):
                inside = True
                break
        if not inside:
            kept.append(a)
    return kept


def pack(items, width, height):
    """items: [(key, w, h)] -> {key: (x, y)} or None when they do not fit in width x height."""
    free = [(0, 0, width, height)]
    placed = {}
    for key, w, h in sorted(items, key=lambda item: (-max(item[1], item[2]), -item[1] * item[2])):
        fit = _best_fit(free, w, h)
        if fit is None:
            return None
        _, _, x, y = fit
        placed[key] = (x, y)
        free = _split(free, x, y, w, h)
    return placed


def pack_pow2(items, gap=2, max_side=MAX_SIDE):
    """items: [(key, w, h)] (sizes of the images). Returns (width, height, {key: (x, y)}): the smallest power-of-two
    sheet, `gap` pixels left between two images. Raises ValueError when no sheet up to max_side holds them."""
    padded = [(key, w + gap, h + gap) for key, w, h in items]
    total = sum(w * h for _, w, h in padded)
    sizes = []
    side = 1
    sizes_pow = []
    while side <= max_side:
        sizes_pow.append(side)
        side *= 2
    for w in sizes_pow:
        for h in sizes_pow:
            if w * h >= total:
                sizes.append((w * h, max(w, h) - min(w, h), w, h))
    sizes.sort()
    for _, _, w, h in sizes:
        # the last image of a row or a column does not need its gap: the sheet is `gap` bigger for the packer
        placed = pack(padded, w + gap, h + gap)
        if placed is not None:
            return w, h, placed
    raise ValueError("the shapes do not fit in one %dx%d sheet" % (max_side, max_side))


def pack_sheets(items, gap=2, max_sheets=3, max_side=MAX_SIDE, min_side=64):
    """Like pack_pow2 but the shapes may go in several sheets: a movie whose shapes need 46 % of a 2048 x 4096 sheet
    fits a 2048 x 2048 one and a 1024 x 1024 one, which is less video memory (and file) than the one big sheet.
    Returns ([(width, height)], {key: (sheet index, x, y)}): the sets of sheets are tried by growing total area."""
    padded = [(key, w + gap, h + gap) for key, w, h in items]
    total = sum(w * h for _, w, h in padded)
    sides = []
    side = min_side
    while side <= max_side:
        sides.append(side)
        side *= 2
    shapes = [(w, h) for w in sides for h in sides]
    biggest = max(max(w, h) for _, w, h in padded)
    shapes = [s for s in shapes if s[0] * s[1] >= 1]
    configs = []
    for count in range(1, max_sheets + 1):
        configs.extend(_combos(shapes, count))
    configs = [c for c in configs if sum(w * h for w, h in c) >= total and max(max(w, h) for w, h in c) >= biggest]
    configs.sort(key=lambda c: (sum(w * h for w, h in c), len(c)))
    for config in configs:
        result = _pack_into(padded, config, gap)
        if result is not None:
            return list(config), result
    raise ValueError("the shapes do not fit in %d sheets of %d x %d" % (max_sheets, max_side, max_side))


def _combos(shapes, count, start=0):
    if count == 0:
        yield ()
        return
    for index in range(start, len(shapes)):
        for rest in _combos(shapes, count - 1, index):
            yield (shapes[index],) + rest


def _pack_into(padded, config, gap):
    """First fit of the shapes (biggest first) in the sheets of config, each one packed with MaxRects."""
    free = [[(0, 0, w + gap, h + gap)] for w, h in config]
    placed = {}
    for key, w, h in sorted(padded, key=lambda item: (-max(item[1], item[2]), -item[1] * item[2])):
        for sheet, rects in enumerate(free):
            fit = _best_fit(rects, w, h)
            if fit is not None:
                _, _, x, y = fit
                placed[key] = (sheet, x, y)
                free[sheet] = _split(rects, x, y, w, h)
                break
        else:
            return None
    return placed
