#!/usr/bin/env python3
"""build/ecs.py -- regenerate the Ess.Ecs class table from data/ecs_registry.tsv.

Ess.Ecs (src/08_ecs.lua) ships the engine's ECS component-class registry as a Lua-queryable vocabulary:
the ~232 reflection classes an entity is assembled from, each with its family and its component HASH.
The hash is `pandemic_hash_m2(name)` -- the value the engine's component resolver keys on -- verified
against the reversed docs (Health=0x06BE1ABF, RuntimeHealth=0xF9B9B2A5, RuntimeNodeHealth=0x76927BF5,
ParticleEmitter=0xE595AB2F, RedEffectComponent=0x60A13E3E, all confirmed).

The registry (`data/ecs_registry.tsv`, columns: family, name, registrar-global, descriptor-vtable) comes
from the Mercs2 EXE reflection RE (docs/mercs2-ecs). This prints the `local CLASSES = { … }` block that
src/08_ecs.lua carries inline -- run it and paste the output over that block when the registry changes.
The registrar/vtable RVAs are dev cross-reference only and are dropped here; the Lua side wants name,
family and hash.

Usage: python build/ecs.py        (prints the Lua table block to stdout)
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TSV = ROOT / "data" / "ecs_registry.tsv"

FNV1A_OFFSET_BASIS = 0x811C9DC5
FNV1A_PRIME = 0x01000193


def pandemic_hash_m2(text):
    """The engine's asset/name hash: FNV-1a, case-folded via |0x20, then salted with 0x2A."""
    h = FNV1A_OFFSET_BASIS
    for b in text.encode("ascii"):
        h = ((h ^ ((b | 0x20) & 0xFF)) * FNV1A_PRIME) & 0xFFFFFFFF
    h ^= 0x2A
    return (h * FNV1A_PRIME) & 0xFFFFFFFF


def main():
    rows = []
    for line in TSV.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        family, name = line.split("\t")[:2]
        rows.append((name, family, pandemic_hash_m2(name)))
    rows.sort(key=lambda r: (r[1], r[0]))   # by family, then name -- stable, reviewable order
    print("local CLASSES = {")
    for name, family, h in rows:
        print('  { n = "%s", f = "%s", h = "0x%08X" },' % (name, family, h))
    print("}")
    print("-- %d classes across %d families" % (len(rows), len({r[1] for r in rows})))


if __name__ == "__main__":
    main()
