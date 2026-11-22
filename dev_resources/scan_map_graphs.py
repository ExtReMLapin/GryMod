#!/usr/bin/env python3
"""Survey of AI node graphs (.ain) and navigation meshes (.nav) of every map
reachable by a Garry's Mod installation.

Strictly read-only and header-only:
  * the game is never started, nothing is extracted or written next to the
    data; the only files written are the ones given with --csv / --md;
  * GMA archives are never unpacked: only the header and the file table are
    read, then the few bytes needed for each maps/graphs/*.ain (whole entry,
    they are small) and each maps/*.nav (header only) by seeking into the
    archive;
  * LZMA-compressed archives (legacy Workshop ".bin") are NOT read: they are
    only counted and, as a courtesy, the start of their stream is decoded in
    memory (bounded) to list the map file names; their graphs stay unread;
  * VPK archives are not opened (maps living only inside a VPK are not
    covered).

Archives and maps are untrusted data: nothing is executed or interpreted.
Run it as:  python -u -I scan_map_graphs.py --csv out.csv --md out.md
from a directory that is not one containing the data.

Standard library only.
"""

import argparse
import csv
import json
import lzma
import os
import re
import statistics
import struct
import sys
import time

AIN_NODE_SIZE = 61          # bytes of one node record on disk
AIN_LOOKUP_SIZE = 4         # one int32 lookup entry per node, at the end
AIN_LINK_SIZE = 14          # bytes of one link record on disk
AIN_EXPECTED_VERSION = 37
AIN_MAX_READ = 64 * 1024 * 1024   # never read more than this for one .ain
NAV_MAGIC = 0xFEEDFACE
NAV_HEADER_READ = 1024 * 1024
NODE_TYPES = {0: "any", 1: "deleted", 2: "ground", 3: "air", 4: "climb", 5: "water"}
GMA_TABLE_MAX_ENTRIES = 5_000_000
LZMA_PEEK_OUT = 16 * 1024 * 1024   # bounded in-memory decode of a legacy archive start
LZMA_PEEK_IN = 8 * 1024 * 1024

RE_BSP = re.compile(r"^maps/([^/]+)\.bsp$", re.I)
RE_NAV = re.compile(r"^maps/([^/]+)\.nav$", re.I)
RE_AIN = re.compile(r"^maps/graphs/([^/]+)\.ain$", re.I)

# Games whose loose maps/ folders GMod mounts (cfg/mountdepots.txt + HL2 family).
HL2_FAMILY_DIRS = ("hl2", "episodic", "ep2", "lostcoast", "hl2mp", "cstrike", "tf", "portal")
MOUNTABLE_GAME_FOLDERS = ("Half-Life 2", "Counter-Strike Source", "Team Fortress 2",
                          "Half-Life 2 Deathmatch", "Portal")


# ---------------------------------------------------------------- discovery

def steam_roots_auto():
    roots = []
    try:
        import winreg  # type: ignore
        for hive, key in ((winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam"),):
            with winreg.OpenKey(hive, key) as k:
                path, _ = winreg.QueryValueEx(k, "SteamPath")
                roots.append(os.path.normpath(path))
    except Exception:
        pass
    return roots


def libraries_from_root(root):
    """Steam libraries listed in <root>/steamapps/libraryfolders.vdf, plus root itself."""
    libs = [os.path.normpath(root)]
    vdf = os.path.join(root, "steamapps", "libraryfolders.vdf")
    try:
        with open(vdf, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        for m in re.finditer(r'"path"\s+"([^"]+)"', text):
            libs.append(os.path.normpath(m.group(1).replace("\\\\", "\\")))
    except OSError:
        pass
    return libs


def find_libraries(steam_roots, gmod_dir_hint):
    libs = []
    for r in steam_roots:
        libs.extend(libraries_from_root(r))
    if gmod_dir_hint:
        # <library>/steamapps/common/GarrysMod/garrysmod
        p = os.path.abspath(gmod_dir_hint)
        for _ in range(4):
            p = os.path.dirname(p)
        libs.append(p)
    seen, out = set(), []
    for l in libs:
        k = os.path.normcase(l)
        if k not in seen and os.path.isdir(l):
            seen.add(k)
            out.append(l)
    return out


def find_gmod_dir(libs):
    for l in libs:
        d = os.path.join(l, "steamapps", "common", "GarrysMod", "garrysmod")
        if os.path.isdir(d):
            return d
    return None


# ------------------------------------------------------------------ parsing

def parse_ain(data, entry_size):
    """Parse a whole .ain buffer. Returns a dict of facts (never raises)."""
    r = {"ain_size": entry_size}
    if len(data) < 12:
        r["ain_error"] = "trop court (%d octets)" % len(data)
        return r
    ver, mapver, n = struct.unpack_from("<iii", data, 0)
    r.update(ain_version=ver, ain_map_version=mapver, nodes=n)
    notes = []
    if n < 0:
        r["ain_error"] = "N negatif"
        return r
    end_nodes = 12 + AIN_NODE_SIZE * n
    counts = {k: 0 for k in NODE_TYPES}
    other = 0
    avail = min(n, max(0, (len(data) - 12) // AIN_NODE_SIZE))
    if avail < n:
        notes.append("noeuds tronques (%d lus sur %d)" % (avail, n))
    for i in range(avail):
        t = data[12 + AIN_NODE_SIZE * i + 56]
        if t in counts:
            counts[t] += 1
        else:
            other += 1
    r["n_by_type"] = counts
    r["n_unknown_type"] = other
    links = None
    if len(data) >= end_nodes + 4:
        links = struct.unpack_from("<i", data, end_nodes)[0]
        r["links"] = links
    else:
        notes.append("pas de compteur de liens")
    if links is not None and links >= 0:
        expected = 16 + (AIN_NODE_SIZE + AIN_LOOKUP_SIZE) * n + AIN_LINK_SIZE * links
        r["expected_size"] = expected
        if entry_size is not None and expected != entry_size:
            r["size_mismatch"] = entry_size - expected
    elif links is not None:
        notes.append("L negatif")
    r["ain_notes"] = notes
    return r


def parse_nav(data, entry_size):
    r = {"nav_size": entry_size}
    try:
        off = 0
        magic, version = struct.unpack_from("<II", data, off)
        off += 8
        if magic != NAV_MAGIC:
            r["nav_error"] = "magie 0x%08X inattendue" % magic
            return r
        r["nav_version"] = version
        sub = None
        if version >= 10:
            sub = struct.unpack_from("<I", data, off)[0]
            off += 4
        r["nav_subversion"] = sub
        if version >= 4:
            off += 4  # bsp size
        if version >= 14:
            off += 1  # isAnalyzed
        place_count = struct.unpack_from("<H", data, off)[0]
        off += 2
        for _ in range(place_count):
            ln = struct.unpack_from("<H", data, off)[0]
            off += 2 + ln
        if version > 12:
            off += 1  # hasUnnamedAreas
        r["nav_areas"] = struct.unpack_from("<I", data, off)[0]
        r["nav_places"] = place_count
    except struct.error:
        r["nav_error"] = "en-tete tronque ou incoherent"
    return r


class Stream:
    """Small buffered sequential reader over a file object (read-only)."""

    def __init__(self, f, chunk=1 << 20):
        self.f, self.chunk = f, chunk
        self.buf = b""
        self.pos = 0       # position in buf
        self.base = 0      # file offset of buf[0]

    def _fill(self, need):
        while len(self.buf) - self.pos < need:
            more = self.f.read(self.chunk)
            if not more:
                return False
            self.buf = self.buf[self.pos:] + more
            self.base += self.pos
            self.pos = 0
        return True

    def tell(self):
        return self.base + self.pos

    def read(self, n):
        if not self._fill(n):
            raise EOFError
        b = self.buf[self.pos:self.pos + n]
        self.pos += n
        return b

    def cstr(self, limit=4096):
        while True:
            i = self.buf.find(b"\0", self.pos)
            if i >= 0:
                if i - self.pos > limit:
                    raise ValueError("chaine trop longue")
                s = self.buf[self.pos:i]
                self.pos = i + 1
                return s.decode("utf-8", "replace")
            if len(self.buf) - self.pos > limit:
                raise ValueError("chaine trop longue")
            if not self._fill(len(self.buf) - self.pos + 1):
                raise EOFError

    def unpack(self, fmt):
        return struct.unpack("<" + fmt, self.read(struct.calcsize("<" + fmt)))


def parse_gma_header(st):
    """Returns (info, entries, data_start). Entries: (path, size, offset)."""
    if st.read(4) != b"GMAD":
        raise ValueError("pas GMAD")
    (version,) = st.unpack("B")
    if not 1 <= version <= 3:
        raise ValueError("version GMA %d non geree" % version)
    steamid, timestamp = st.unpack("QQ")
    if version >= 2:
        while st.cstr():
            pass
    name = st.cstr()
    desc = st.cstr()
    author = st.cstr()
    (addon_version,) = st.unpack("i")
    title = name
    try:
        j = json.loads(desc)
        if isinstance(j, dict) and j.get("title"):
            title = str(j["title"])
    except (ValueError, TypeError):
        pass
    entries = []
    off = 0
    for _ in range(GMA_TABLE_MAX_ENTRIES):
        (num,) = st.unpack("I")
        if num == 0:
            break
        path = st.cstr()
        size, crc = st.unpack("qI")
        entries.append((path.replace("\\", "/"), size, off))
        off += size
    else:
        raise ValueError("table de fichiers trop grande")
    info = {"gma_version": version, "title": title, "name": name,
            "author": author, "steamid": steamid, "n_files": len(entries)}
    return info, entries, st.tell()


# ------------------------------------------------------------------ sources

class Occurrence:
    """One map as seen in one source (bsp and/or ain and/or nav)."""
    __slots__ = ("map", "source_kind", "source", "container", "wsid", "title",
                 "bsp", "bsp_size", "ain", "nav", "notes")

    def __init__(self, name, kind, source, container="", wsid="", title=""):
        self.map = name
        self.source_kind = kind
        self.source = source
        self.container = container
        self.wsid = wsid
        self.title = title
        self.bsp = False
        self.bsp_size = None
        self.ain = None
        self.nav = None
        self.notes = []


def add_to(occs, name, kind, source, container, wsid, title):
    key = name.lower()
    o = occs.get(key)
    if o is None:
        o = occs[key] = Occurrence(name, kind, source, container, wsid, title)
    return o


def scan_loose_root(root, kind, source, stats):
    """Loose files: <root>/maps/*.bsp|*.nav and <root>/maps/graphs/*.ain."""
    occs = {}
    maps = os.path.join(root, "maps")
    try:
        names = os.listdir(maps)
    except OSError:
        return []
    for fn in names:
        full = os.path.join(maps, fn)
        low = fn.lower()
        try:
            if not os.path.isfile(full):
                continue
            if low.endswith(".bsp"):
                o = add_to(occs, fn[:-4], kind, source, root, "", "")
                o.bsp = True
                o.bsp_size = os.path.getsize(full)
            elif low.endswith(".nav"):
                o = add_to(occs, fn[:-4], kind, source, root, "", "")
                size = os.path.getsize(full)
                with open(full, "rb") as f:
                    o.nav = parse_nav(f.read(NAV_HEADER_READ), size)
        except OSError as e:
            stats["errors"].append("%s: %s" % (full, e))
    gdir = os.path.join(maps, "graphs")
    try:
        gnames = os.listdir(gdir)
    except OSError:
        gnames = []
    for fn in gnames:
        if not fn.lower().endswith(".ain"):
            continue
        full = os.path.join(gdir, fn)
        try:
            size = os.path.getsize(full)
            with open(full, "rb") as f:
                data = f.read(min(size, AIN_MAX_READ))
            o = add_to(occs, fn[:-4], kind, source, root, "", "")
            o.ain = parse_ain(data, size)
        except OSError as e:
            stats["errors"].append("%s: %s" % (full, e))
    return list(occs.values())


def scan_gma(path, kind, source, wsid, stats):
    occs = {}
    try:
        with open(path, "rb") as f:
            st = Stream(f)
            info, entries, data_start = parse_gma_header(st)
            title = info["title"]
            for rel, size, off in entries:
                m = RE_BSP.match(rel)
                if m:
                    o = add_to(occs, m.group(1), kind, source, path, wsid, title)
                    o.bsp = True
                    o.bsp_size = size
                    continue
                m = RE_NAV.match(rel)
                if m:
                    o = add_to(occs, m.group(1), kind, source, path, wsid, title)
                    f.seek(data_start + off)
                    o.nav = parse_nav(f.read(min(size, NAV_HEADER_READ)), size)
                    continue
                m = RE_AIN.match(rel)
                if m:
                    o = add_to(occs, m.group(1), kind, source, path, wsid, title)
                    f.seek(data_start + off)
                    data = f.read(min(size, AIN_MAX_READ))
                    o.ain = parse_ain(data, size)
                    if len(data) < size:
                        o.notes.append("ain lu partiellement")
            stats["gma_read"] += 1
            stats["gma_files"] += info["n_files"]
    except (OSError, EOFError, ValueError, struct.error) as e:
        stats["unread"].append((path, wsid, "erreur de lecture GMA : %s" % e, "", []))
        return []
    return list(occs.values())


def peek_lzma(path):
    """Bounded in-memory look at the start of a legacy (LZMA) archive.

    Returns (title, [map names]) or None. Decodes at most LZMA_PEEK_OUT bytes
    and never writes anything. Graphs are NOT read.
    """
    try:
        with open(path, "rb") as f:
            comp = f.read(LZMA_PEEK_IN)
        d = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE)
        raw = d.decompress(comp, max_length=LZMA_PEEK_OUT)
    except (OSError, lzma.LZMAError, ValueError):
        return None
    import io
    try:
        st = Stream(io.BytesIO(raw))
        info, entries, _ = parse_gma_header(st)
    except (EOFError, ValueError, struct.error):
        return None
    names = sorted({m.group(1) for rel, _s, _o in entries
                    for m in [RE_BSP.match(rel) or RE_AIN.match(rel) or RE_NAV.match(rel)] if m})
    return info["title"], names


def scan_workshop_dir(wdir, stats):
    out = []
    try:
        ids = sorted(os.listdir(wdir))
    except OSError:
        return out
    for wsid in ids:
        d = os.path.join(wdir, wsid)
        if not os.path.isdir(d):
            continue
        try:
            files = sorted(os.listdir(d))
        except OSError:
            continue
        for fn in files:
            low = fn.lower()
            full = os.path.join(d, fn)
            if not (low.endswith(".gma") or low.endswith(".bin")):
                continue
            try:
                with open(full, "rb") as f:
                    magic = f.read(5)
            except OSError as e:
                stats["errors"].append("%s: %s" % (full, e))
                continue
            if magic[:4] == b"GMAD":
                out.extend(scan_gma(full, "workshop", "workshop:" + wsid, wsid, stats))
            elif magic[:1] == b"\x5d" and low.endswith(".bin"):
                peek = peek_lzma(full)
                title, names = peek if peek else ("", [])
                stats["unread"].append((full, wsid, "compressee (LZMA), non lue", title, names))
            else:
                stats["unread"].append((full, wsid, "magie inconnue %r" % magic, "", []))
    return out


def scan_cache_gmas(cdir, stats):
    """garrysmod/cache/workshop/*.cache: Workshop cache; only GMAD ones are read."""
    out = []
    try:
        names = sorted(os.listdir(cdir))
    except OSError:
        return out
    for fn in names:
        full = os.path.join(cdir, fn)
        try:
            if not os.path.isfile(full):
                continue
            with open(full, "rb") as f:
                if f.read(4) != b"GMAD":
                    continue
        except OSError:
            continue
        out.extend(scan_gma(full, "cache", "cache:" + fn, "", stats))
    return out


def list_vpk_dirs(path):
    try:
        return sorted(n for n in os.listdir(path) if n.lower().endswith("_dir.vpk"))
    except OSError:
        return []


def mounted_game_dirs(libs, gmod_dir):
    """Loose game folders GMod mounts: mount.cfg paths, then HL2-family auto-detect."""
    dirs = []
    mc = os.path.join(gmod_dir, "cfg", "mount.cfg") if gmod_dir else None
    if mc and os.path.isfile(mc):
        try:
            with open(mc, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("//"):
                        continue
                    m = re.match(r'"([^"]+)"\s+"([^"]+)"', line)
                    if m and os.path.isdir(m.group(2)):
                        dirs.append(("mount.cfg:" + m.group(1), m.group(2)))
        except OSError:
            pass
    for lib in libs:
        common = os.path.join(lib, "steamapps", "common")
        for g in MOUNTABLE_GAME_FOLDERS:
            gd = os.path.join(common, g)
            if not os.path.isdir(gd):
                continue
            for sub in sorted(os.listdir(gd)):
                p = os.path.join(gd, sub)
                if os.path.isdir(os.path.join(p, "maps")) and sub.lower() in HL2_FAMILY_DIRS:
                    dirs.append(("mount:%s/%s (%s)" % (g, sub, lib[:3]), p))
    return dirs


# ------------------------------------------------------------------- report

def hist_bucket(n):
    for hi, label in ((0, "0"), (250, "1-250"), (500, "251-500"), (1000, "501-1000"),
                      (1500, "1001-1500"), (3000, "1501-3000"), (10000, "3001-10000")):
        if n <= hi:
            return label
    return ">10000"


HIST_ORDER = ["0", "1-250", "251-500", "501-1000", "1001-1500", "1501-3000",
              "3001-10000", ">10000"]

CSV_FIELDS = ["map", "source_kind", "source", "container", "workshop_id", "title",
              "bsp_here", "bsp_elsewhere", "occurrences", "duplicate",
              "ain_present", "ain_size", "ain_version", "ain_map_version", "nodes", "links",
              "n_ground", "n_air", "n_climb", "n_water", "n_any", "n_deleted", "n_unknown",
              "ain_expected_size", "ain_size_mismatch", "ain_notes",
              "nav_present", "nav_size", "nav_version", "nav_subversion", "nav_areas",
              "nav_error", "ain_error", "notes"]


def occ_row(o, total, bsp_elsewhere):
    a = o.ain or {}
    n = o.nav or {}
    t = a.get("n_by_type", {})
    return {
        "map": o.map, "source_kind": o.source_kind, "source": o.source,
        "container": o.container, "workshop_id": o.wsid, "title": o.title,
        "bsp_here": "oui" if o.bsp else "non",
        "bsp_elsewhere": ";".join(bsp_elsewhere),
        "occurrences": total, "duplicate": "oui" if total > 1 else "non",
        "ain_present": "oui" if o.ain else "non",
        "ain_size": a.get("ain_size", ""), "ain_version": a.get("ain_version", ""),
        "ain_map_version": a.get("ain_map_version", ""),
        "nodes": a.get("nodes", ""), "links": a.get("links", ""),
        "n_ground": t.get(2, ""), "n_air": t.get(3, ""), "n_climb": t.get(4, ""),
        "n_water": t.get(5, ""), "n_any": t.get(0, ""), "n_deleted": t.get(1, ""),
        "n_unknown": a.get("n_unknown_type", ""),
        "ain_expected_size": a.get("expected_size", ""),
        "ain_size_mismatch": a.get("size_mismatch", ""),
        "ain_notes": "; ".join(a.get("ain_notes", [])),
        "nav_present": "oui" if o.nav else "non",
        "nav_size": n.get("nav_size", ""), "nav_version": n.get("nav_version", ""),
        "nav_subversion": n.get("nav_subversion", "") if n.get("nav_subversion") is not None else "",
        "nav_areas": n.get("nav_areas", ""), "nav_error": n.get("nav_error", ""),
        "ain_error": a.get("ain_error", ""),
        "notes": "; ".join(o.notes),
    }


def md_escape(s):
    return str(s).replace("|", "\\|")


def short_src(o):
    if o.source_kind == "workshop":
        t = (" " + o.title) if o.title else ""
        return "workshop %s%s" % (o.wsid, t[:40])
    return o.source


def write_md(path, occs, rows, stats, meta, elapsed):
    lines = []
    w = lines.append
    with_ain = [o for o in occs if o.ain and "nodes" in o.ain]
    names_all = sorted({o.map.lower() for o in occs})
    # one graph per map name: the largest (worst case for a size cap)
    best = {}
    for o in with_ain:
        k = o.map.lower()
        if k not in best or o.ain["nodes"] > best[k].ain["nodes"]:
            best[k] = o
    ns = [o.ain["nodes"] for o in best.values()]
    names_with_nav = {o.map.lower() for o in occs if o.nav}
    names_with_bsp = {o.map.lower() for o in occs if o.bsp}
    w("# Releve des graphes de noeuds (.ain) et navmeshes (.nav) - 2026-11-22")
    w("")
    w("Genere par `dev_resources/scan_map_graphs.py` (lecture seule, en-tetes "
      "seulement, aucune extraction) en %.1f s. Tout ce qui suit est **mesure** "
      "sur les fichiers, sauf les mentions explicites de deduction." % elapsed)
    w("")
    w("## Perimetre scanne")
    w("")
    for k, v in meta["sources"]:
        w("- %s : %s" % (k, v))
    w("")
    w("Non couvert : les cartes qui ne seraient que dans un VPK (VPK non ouverts : %s) ; "
      "les archives LZMA (voir plus bas) ; les dossiers ou jeux non montes." % meta["vpk_note"])
    w("")
    w("## Statistiques")
    w("")
    w("- Occurrences (carte x source) : **%d**" % len(occs))
    w("- Cartes distinctes (nom, toutes sources, avec .bsp, .ain ou .nav) : **%d**" % len(names_all))
    w("- Cartes distinctes dont un .bsp est visible : %d" % len(names_with_bsp))
    w("- Cartes distinctes avec au moins un .ain lisible : **%d** ; sans .ain : **%d**"
      % (len(best), len(names_all) - len(best)))
    w("- Cartes distinctes avec .nav : **%d**" % len(names_with_nav))
    dups = [k for k in names_all if sum(1 for o in occs if o.map.lower() == k) > 1]
    w("- Noms presents dans plusieurs sources (doublons) : %d" % len(dups))
    if ns:
        w("- Maximum de N (une valeur par nom, la plus grande) : **%d** (%s, %s)"
          % (max(ns), max(best.values(), key=lambda o: o.ain["nodes"]).map,
             short_src(max(best.values(), key=lambda o: o.ain["nodes"]))))
        w("- Mediane de N : **%s** ; moyenne : %.0f" % (statistics.median(ns), statistics.mean(ns)))
    w("")
    w("### Histogramme de N (cartes distinctes avec .ain, valeur maximale par nom)")
    w("")
    w("| N | cartes |")
    w("|---|---:|")
    hist = {k: 0 for k in HIST_ORDER}
    for n in ns:
        hist[hist_bucket(n)] += 1
    for k in HIST_ORDER:
        w("| %s | %d |" % (k, hist[k]))
    w("")
    occ_hist = {k: 0 for k in HIST_ORDER}
    for o in with_ain:
        occ_hist[hist_bucket(o.ain["nodes"])] += 1
    w("Meme histogramme par occurrence : " + ", ".join("%s : %d" % (k, occ_hist[k]) for k in HIST_ORDER) + ".")
    w("")
    over = sorted((o for o in with_ain if o.ain["nodes"] > 1500),
                  key=lambda o: -o.ain["nodes"])
    w("### Graphes de plus de 1500 noeuds (par occurrence) : %d" % len(over))
    w("")
    if over:
        w("| carte | N | L | taille OK | source |")
        w("|---|---:|---:|:-:|---|")
        for o in over:
            a = o.ain
            ok = "oui" if "size_mismatch" not in a and "expected_size" in a else "NON"
            w("| %s | %d | %s | %s | %s |" % (md_escape(o.map), a["nodes"], a.get("links", "?"), ok,
                                                md_escape(short_src(o))))
        w("")
    bad_ver = [o for o in with_ain if o.ain.get("ain_version") != AIN_EXPECTED_VERSION]
    w("### Graphes de version differente de %d : %d" % (AIN_EXPECTED_VERSION, len(bad_ver)))
    w("")
    for o in bad_ver:
        w("- %s : version %s, N=%s (%s)" % (o.map, o.ain.get("ain_version"), o.ain.get("nodes"), short_src(o)))
    if bad_ver:
        w("")
    bad_size = [o for o in with_ain if "size_mismatch" in o.ain or "expected_size" not in o.ain]
    w("### Graphes dont la taille ne colle pas a 16 + 65 N + 14 L : %d" % len(bad_size))
    w("")
    for o in bad_size:
        a = o.ain
        w("- %s (%s) : taille %s, attendue %s (ecart %s), N=%s, L=%s %s" % (
            o.map, short_src(o), a.get("ain_size"), a.get("expected_size", "?"),
            a.get("size_mismatch", "?"), a.get("nodes"), a.get("links", "?"),
            "; ".join(a.get("ain_notes", []))))
    if bad_size:
        w("")
    ain_err = [o for o in occs if o.ain and "nodes" not in o.ain]
    if ain_err:
        w("### .ain illisibles : %d" % len(ain_err))
        w("")
        for o in ain_err:
            w("- %s (%s) : %s" % (o.map, short_src(o), o.ain.get("ain_error")))
        w("")
    zeros = [o for o in with_ain if o.ain["nodes"] == 0]
    w("### Graphes vides (N = 0) : %d" % len(zeros))
    w("")
    # nodes by type totals
    tot = {k: 0 for k in NODE_TYPES}
    for o in best.values():
        for k, v in o.ain.get("n_by_type", {}).items():
            tot[k] += v
    w("Noeuds par type, somme des graphes retenus (une valeur par nom) : "
      + ", ".join("%s : %d" % (NODE_TYPES[k], tot[k]) for k in NODE_TYPES) + ".")
    w("")
    w("### Navmeshes (.nav)")
    w("")
    nav_occ = [o for o in occs if o.nav]
    navv = {}
    for o in nav_occ:
        navv[o.nav.get("nav_version", "?")] = navv.get(o.nav.get("nav_version", "?"), 0) + 1
    w("Occurrences avec .nav : %d. Versions : %s. Analyse en echec : %d."
      % (len(nav_occ), ", ".join("v%s x%d" % kv for kv in sorted(navv.items(), key=str)) or "-",
         sum(1 for o in nav_occ if "nav_error" in o.nav)))
    w("")
    if nav_occ:
        w("| carte | version | zones | taille | source |")
        w("|---|---:|---:|---:|---|")
        for o in sorted(nav_occ, key=lambda o: -(o.nav.get("nav_areas") or 0)):
            n = o.nav
            w("| %s | %s | %s | %s | %s |" % (md_escape(o.map), n.get("nav_version", "?"),
                                              n.get("nav_areas", n.get("nav_error", "?")),
                                              n.get("nav_size"), md_escape(short_src(o))))
        w("")
    w("### Archives non lues : %d" % len(stats["unread"]))
    w("")
    for path_, wsid, why, title, names in stats["unread"]:
        extra = ""
        if title or names:
            extra = " ; titre `%s` ; fichiers carte vus dans le debut du flux : %s" % (
                title, ", ".join(names) if names else "aucun")
        w("- workshop %s `%s` : %s%s" % (wsid, os.path.basename(path_), why, extra))
    if not stats["unread"]:
        w("- aucune")
    w("")
    orphans = [o for o in occs if (o.ain or o.nav) and not o.bsp]
    w("### .ain / .nav sans .bsp dans la meme source : %d" % len(orphans))
    w("")
    orph_total = [o for o in orphans if not rows[id(o)]["bsp_elsewhere"]]
    w("Dont sans aucun .bsp visible dans les autres sources scannees : %d "
      "(leur .bsp doit etre dans un VPK, ou la carte a disparu : graphe perime)." % len(orph_total))
    w("")
    for o in sorted(orph_total, key=lambda o: o.map):
        w("- %s (%s) : %s" % (o.map, short_src(o),
                              ("N=%s" % o.ain.get("nodes")) if o.ain else "nav seul"))
    w("")
    w("### Carte presente dans plusieurs sources (doublons) : %d noms" % len(dups))
    w("")
    for k in dups:
        grp = [o for o in occs if o.map.lower() == k]
        w("- %s : " % k + " | ".join("%s%s" % (short_src(o), (" N=%s" % o.ain["nodes"]) if o.ain and "nodes" in o.ain else "")
                                    for o in grp))
    w("")
    w("## Les 40 plus grandes (par N decroissant, par occurrence)")
    w("")
    w("| # | carte | N | L | sol | air | escalade | eau | .nav zones | .bsp ici | source |")
    w("|--:|---|--:|--:|--:|--:|--:|--:|--:|:-:|---|")
    top = sorted(with_ain, key=lambda o: -o.ain["nodes"])[:40]
    for i, o in enumerate(top, 1):
        a = o.ain
        t = a.get("n_by_type", {})
        w("| %d | %s | %d | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            i, md_escape(o.map), a["nodes"], a.get("links", "?"), t.get(2, "?"), t.get(3, "?"),
            t.get(4, "?"), t.get(5, "?"), (o.nav or {}).get("nav_areas", "-"),
            "oui" if o.bsp else "non", md_escape(short_src(o))))
    w("")
    w("## Toutes les cartes avec .ain, triees par N decroissant (une ligne par occurrence)")
    w("")
    w("| carte | N | L | .nav zones | source |")
    w("|---|--:|--:|--:|---|")
    for o in sorted(with_ain, key=lambda o: (-o.ain["nodes"], o.map)):
        w("| %s | %d | %s | %s | %s |" % (md_escape(o.map), o.ain["nodes"], o.ain.get("links", "?"),
                                          (o.nav or {}).get("nav_areas", "-"), md_escape(short_src(o))))
    w("")
    # cap analysis
    w("## Ce que cela dit de la limite")
    w("")
    w("Refus sous differents plafonds (graphes reels, une valeur par nom de carte, "
      "la plus grande ; entre parentheses : par occurrence) :")
    w("")
    w("| plafond | cartes refusees (N > plafond) | occurrences refusees | cartes restantes |")
    w("|--:|--:|--:|--:|")
    for cap in (1500, 2000, 3000, 5000, 10000, 20000):
        rj = sum(1 for n in ns if n > cap)
        rjo = sum(1 for o in with_ain if o.ain["nodes"] > cap)
        w("| %d | %d | %d | %d |" % (cap, rj, rjo, len(ns) - rj))
    w("")
    if ns:
        srt = sorted(ns)
        def pct(p):
            return srt[min(len(srt) - 1, int(p * len(srt)))]
        w("Quantiles de N : 50 %% = %d, 90 %% = %d, 95 %% = %d, 99 %% = %d, max = %d."
          % (pct(.5), pct(.9), pct(.95), pct(.99), srt[-1]))
        w("")
    n_consistent = sum(1 for o in with_ain if "size_mismatch" not in o.ain and "expected_size" in o.ain)
    w("Coherence taille = formule : %d graphes sur %d (%d ecarts)." % (
        n_consistent, len(with_ain), len(with_ain) - n_consistent))
    w("")
    w(meta["verdict"](ns, with_ain, n_consistent, best))
    w("")
    w("## Limites de ce releve")
    w("")
    w("- Mesure : chaque N, L, type de noeud et nombre de zones .nav vient de la lecture du fichier "
      "(loose) ou de la tranche exacte dans l'archive GMA.")
    w("- Les `.ain` de `garrysmod/maps/graphs` sont le dossier que le moteur ecrit lui-meme quand il "
      "genere un graphe pour une carte qui n'en a pas : certains sont donc des graphes generes "
      "localement (par exemple des cartes de test) et pas des graphes distribues avec la carte. "
      "C'est une deduction (non verifiee fichier par fichier).")
    w("- Aucun VPK n'a ete ouvert ; les archives LZMA n'ont pas ete decompressees.")
    if stats["errors"]:
        w("- Erreurs d'acces ignorees : %d (premieres : %s)" % (
            len(stats["errors"]), "; ".join(stats["errors"][:3])))
    w("")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def verdict_text(ns, with_ain, n_consistent, best):
    if not ns:
        return "Pas de donnees."
    mx = max(ns)
    r1500 = sum(1 for n in ns if n > 1500)
    r3000 = sum(1 for n in ns if n > 3000)
    r5000 = sum(1 for n in ns if n > 5000)
    r10000 = sum(1 for n in ns if n > 10000)
    r20000 = sum(1 for n in ns if n > 20000)
    out = ["Sur ce parc, %d cartes distinctes sur %d depassent 1500 noeuds (%d > 3000, %d > 5000, "
           "%d > 10000, %d > 20000) ; le plus grand graphe a %d noeuds." % (
               r1500, len(ns), r3000, r5000, r10000, r20000, mx)]
    ranked = sorted(best.values(), key=lambda o: -o.ain["nodes"])
    core = [o for o in ranked if o.source_kind in ("jeu", "monte")]
    out.append("Les plus grands : " + ", ".join("%s (%d)" % (o.map, o.ain["nodes"]) for o in ranked[:6])
               + ". Parmi les graphes du dossier du jeu et des jeux montes (hors Workshop) : "
               + (", ".join("%s (%d)" % (o.map, o.ain["nodes"]) for o in core[:3]) if core else "aucun")
               + ".")
    if n_consistent == len(with_ain):
        out.append("Tous les graphes lus respectent exactement 16 + 65 N + 14 L : sur ces donnees, "
                   "la verification de coherence (taille du fichier = formule, N >= 0, L >= 0) "
                   "suffit a rejeter un fichier corrompu ou tronque, sans plafond arbitraire.")
    else:
        out.append("Des graphes ne respectent pas la formule (voir plus haut) : la coherence "
                   "de taille a donc un vrai pouvoir de rejet.")
    out.append("Deduction (non mesuree) : un plafond n'a de sens que comme garde-fou memoire/temps "
               "contre un fichier hostile ; la formule de taille borne deja N par la taille reelle "
               "du fichier (N <= taille / 65), donc un plafond de securite peut etre pose "
               "nettement au-dessus du maximum observe (par exemple 4 x le maximum, ou borne par "
               "la taille du fichier) sans jamais refuser une carte reelle de ce parc.")
    return "\n\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--steam-root", action="append", default=[],
                    help="Steam install root (repeatable); default: registry SteamPath")
    ap.add_argument("--gmod-dir", help="path of the garrysmod folder (default: auto-detect)")
    ap.add_argument("--extra-dir", action="append", default=[],
                    help="extra loose game/mod folder with maps/ and maps/graphs/ (repeatable)")
    ap.add_argument("--csv", help="write one row per map occurrence here")
    ap.add_argument("--md", help="write the markdown report here")
    args = ap.parse_args(argv)

    t0 = time.time()
    roots = args.steam_root or steam_roots_auto()
    libs = find_libraries(roots, args.gmod_dir)
    gmod = args.gmod_dir or find_gmod_dir(libs)
    if not gmod or not os.path.isdir(gmod):
        print("garrysmod folder not found (use --gmod-dir)", file=sys.stderr)
        return 2
    print("garrysmod: %s" % gmod, flush=True)
    print("libraries: %s" % ", ".join(libs), flush=True)

    stats = {"errors": [], "unread": [], "gma_read": 0, "gma_files": 0}
    occs = []
    src_desc = []
    vpk_bits = []

    def note_vpk(label, base):
        v = list_vpk_dirs(base)
        if v:
            vpk_bits.append("%s (%s)" % (label, ", ".join(v)))

    # 1. game folder itself
    occs.extend(scan_loose_root(gmod, "jeu", "jeu:garrysmod", stats))
    src_desc.append(("Jeu", "%s (maps/ et maps/graphs/ loose)" % gmod))
    note_vpk("garrysmod", gmod)
    note_vpk("garrysmod/..", os.path.dirname(gmod))
    # 2. addons, gamemode content, download
    addons = os.path.join(gmod, "addons")
    n_ad = 0
    try:
        for name in sorted(os.listdir(addons)):
            p = os.path.join(addons, name)
            if os.path.isdir(p):
                occs.extend(scan_loose_root(p, "addon", "addon:" + name, stats))
                n_ad += 1
            elif name.lower().endswith(".gma"):
                occs.extend(scan_gma(p, "gma", "gma:addons/" + name, "", stats))
    except OSError:
        pass
    src_desc.append(("Addons loose", "%d dossiers dans addons/" % n_ad))
    gmodes = os.path.join(gmod, "gamemodes")
    try:
        for name in sorted(os.listdir(gmodes)):
            c = os.path.join(gmodes, name, "content")
            if os.path.isdir(c):
                occs.extend(scan_loose_root(c, "gamemode", "gamemode:%s/content" % name, stats))
    except OSError:
        pass
    dl = os.path.join(gmod, "download")
    occs.extend(scan_loose_root(dl, "download", "download", stats))
    for dirpath, _dn, files in os.walk(dl):
        for fn in files:
            if fn.lower().endswith(".gma"):
                occs.extend(scan_gma(os.path.join(dirpath, fn), "gma", "gma:download/" + fn, "", stats))
    # 3. mounted games
    mounted = mounted_game_dirs(libs, gmod)
    for label, p in mounted:
        occs.extend(scan_loose_root(p, "monte", label, stats))
        note_vpk(label.split(":", 1)[1][:60], p)
    src_desc.append(("Jeux montes (loose)", "; ".join("%s -> %s" % (l, p) for l, p in mounted) or "aucun"))
    # 4. Workshop
    n_ws = 0
    for lib in libs:
        wd = os.path.join(lib, "steamapps", "workshop", "content", "4000")
        if os.path.isdir(wd):
            n_ws += 1
            before = stats["gma_read"], len(stats["unread"])
            occs.extend(scan_workshop_dir(wd, stats))
            src_desc.append(("Workshop", "%s : %d GMA lus, %d archives non lues" % (
                wd, stats["gma_read"] - before[0], len(stats["unread"]) - before[1])))
    # 5. cache
    cc = os.path.join(gmod, "cache", "workshop")
    b = stats["gma_read"]
    occs.extend(scan_cache_gmas(cc, stats))
    src_desc.append(("Cache Workshop", "%s : %d GMA lus (les autres fichiers sont des apercus)" % (cc, stats["gma_read"] - b)))
    # 6. extras
    for ex in args.extra_dir:
        occs.extend(scan_loose_root(ex, "extra", "extra:" + os.path.basename(ex.rstrip("\\/")), stats))
        src_desc.append(("Extra", ex))
    src_desc.append(("Archives GMA lues (en-tete + table)", "%d, %d entrees de table au total" % (
        stats["gma_read"], stats["gma_files"])))

    # drop empty occurrences (shouldn't happen) and compute duplicates / bsp elsewhere
    occs = [o for o in occs if o.bsp or o.ain or o.nav]
    by_name = {}
    for o in occs:
        by_name.setdefault(o.map.lower(), []).append(o)
    rows = {}
    for o in occs:
        grp = by_name[o.map.lower()]
        elsewhere = [short_src(x) for x in grp if x is not o and x.bsp]
        rows[id(o)] = occ_row(o, len(grp), elsewhere)
    order = sorted(occs, key=lambda o: (-((o.ain or {}).get("nodes", -1)), o.map.lower(), o.source))

    if args.csv:
        with open(args.csv, "w", encoding="utf-8", newline="") as f:
            wr = csv.DictWriter(f, fieldnames=CSV_FIELDS)
            wr.writeheader()
            for o in order:
                wr.writerow(rows[id(o)])
    elapsed = time.time() - t0
    meta = {"sources": src_desc, "verdict": verdict_text,
            "vpk_note": "; ".join(vpk_bits) or "aucun trouve"}
    if args.md:
        write_md(args.md, order, rows, stats, meta, elapsed)

    with_ain = [o for o in occs if o.ain and "nodes" in o.ain]
    best = {}
    for o in with_ain:
        k = o.map.lower()
        if k not in best or o.ain["nodes"] > best[k].ain["nodes"]:
            best[k] = o
    ns = [o.ain["nodes"] for o in best.values()]
    print("occurrences: %d ; distinct names: %d ; with .ain: %d ; > 1500: %d ; max: %s ; "
          "unread archives: %d ; errors: %d ; %.1f s" % (
              len(occs), len(by_name), len(best), sum(1 for n in ns if n > 1500),
              max(ns) if ns else None, len(stats["unread"]), len(stats["errors"]), elapsed), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
