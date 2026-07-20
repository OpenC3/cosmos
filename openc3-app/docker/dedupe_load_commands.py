#!/usr/bin/env python3
"""Remove duplicate dylib load commands from a Mach-O binary (with ordinal fixup).

Cross-linking the macOS targets with zig/LLD (via cargo-zigbuild) emits a
separate LC_LOAD_DYLIB for every crate that requests `-lobjc` (objc-sys plus
several objc2 versions), producing two identical `/usr/lib/libobjc.A.dylib`
load commands. Apple's native ld64 de-duplicates these; LLD does not. Older
dyld tolerated the duplicate, but macOS 26 (Tahoe) hard-aborts at launch:

    dyld: duplicate linked dylib '/usr/lib/libobjc.A.dylib'

Simply deleting the redundant load command is NOT enough: two-level-namespace
binaries reference dylibs by *ordinal* (their 1-based position in the ordered
list of LC_*_DYLIB commands). Dropping one command renumbers every later dylib,
so all references above it must be decremented or they resolve against the wrong
library (e.g. an AppKit symbol suddenly "expected in ApplicationServices").

This tool therefore:
  1. removes byte-identical duplicate *_DYLIB load commands, and
  2. remaps every dylib ordinal that references them, in
       - the LC_DYLD_INFO(_ONLY) bind / weak-bind / lazy-bind opcode streams, and
       - the LC_SYMTAB nlist n_desc library-ordinal field of undefined symbols.

It never changes the file size or any section/LINKEDIT file offset: the load
command area is rewritten in place and zero-filled after the (shorter) command
list, and every ordinal here is < 128 so ULEB references stay one byte. The edit
invalidates any code signature, so re-sign afterwards.
"""

import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

LC_REQ_DYLD = 0x80000000
LC_SYMTAB = 0x02
LC_DYLD_INFO = 0x22
LC_DYLD_INFO_ONLY = 0x22 | LC_REQ_DYLD

# Commands that add a dylib to the ordinal list, in load order.
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x18 | LC_REQ_DYLD
LC_REEXPORT_DYLIB = 0x1F
LC_LOAD_UPWARD_DYLIB = 0x23 | LC_REQ_DYLD
DYLIB_LOAD_COMMANDS = (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_LOAD_UPWARD_DYLIB)

# Bind opcode encoding (mach-o/loader.h).
BIND_OPCODE_MASK = 0xF0
BIND_IMMEDIATE_MASK = 0x0F
BIND_OPCODE_DONE = 0x00
BIND_OPCODE_SET_DYLIB_ORDINAL_IMM = 0x10
BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB = 0x20
BIND_OPCODE_SET_DYLIB_SPECIAL_IMM = 0x30
BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM = 0x40
BIND_OPCODE_SET_TYPE_IMM = 0x50
BIND_OPCODE_SET_ADDEND_SLEB = 0x60
BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB = 0x70
BIND_OPCODE_ADD_ADDR_ULEB = 0x80
BIND_OPCODE_DO_BIND = 0x90
BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB = 0xA0
BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED = 0xB0
BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB = 0xC0
BIND_OPCODE_THREADED = 0xD0

# nlist n_type flags and special library ordinals.
N_STAB = 0xE0
N_TYPE = 0x0E
N_EXT = 0x01
N_UNDF = 0x00
MAX_LIBRARY_ORDINAL = 0xFD  # ordinals at/above this are special, not real dylibs.


def _read_uleb(buf, off):
    """Return (value, new_off) for a ULEB128 at off."""
    result = 0
    shift = 0
    while True:
        b = buf[off]
        off += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            break
        shift += 7
    return result, off


def _skip_sleb(buf, off):
    while buf[off] & 0x80:
        off += 1
    return off + 1


def _remap_bind_stream(buf, start, size, remap):
    """Remap dylib ordinals in one bind opcode stream, in place. Byte-stable."""
    off = start
    end = start + size
    while off < end:
        byte = buf[off]
        opcode = byte & BIND_OPCODE_MASK
        imm = byte & BIND_IMMEDIATE_MASK
        cur = off
        off += 1
        if opcode == BIND_OPCODE_SET_DYLIB_ORDINAL_IMM:
            new = remap.get(imm, imm)
            buf[cur] = BIND_OPCODE_SET_DYLIB_ORDINAL_IMM | (new & BIND_IMMEDIATE_MASK)
        elif opcode == BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB:
            val, nxt = _read_uleb(buf, off)
            new = remap.get(val, val)
            # Every ordinal here is < 128, so the ULEB is a single byte and the
            # remapped value re-encodes to the same one byte.
            assert nxt - off == 1 and new < 0x80, "ordinal ULEB not byte-stable"
            buf[off] = new & 0x7F
            off = nxt
        elif opcode == BIND_OPCODE_SET_DYLIB_SPECIAL_IMM:
            pass  # negative/special ordinal encoded in imm; not a real dylib.
        elif opcode == BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM:
            while buf[off] != 0:  # symbol name, null-terminated.
                off += 1
            off += 1
        elif opcode == BIND_OPCODE_SET_ADDEND_SLEB:
            off = _skip_sleb(buf, off)
        elif opcode in (
            BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB,
            BIND_OPCODE_ADD_ADDR_ULEB,
            BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB,
        ):
            _, off = _read_uleb(buf, off)
        elif opcode == BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB:
            _, off = _read_uleb(buf, off)
            _, off = _read_uleb(buf, off)
        # Remaining opcodes (DONE, SET_TYPE_IMM, DO_BIND, *_IMM_SCALED, THREADED)
        # carry no trailing operand bytes we need to skip.


def _remap_symtab(buf, symoff, nsyms, remap):
    """Remap library ordinals in undefined-symbol nlist entries, in place."""
    for i in range(nsyms):
        e = symoff + i * 16
        n_type = buf[e + 4]
        if n_type & N_STAB:
            continue
        if (n_type & N_TYPE) != N_UNDF or not (n_type & N_EXT):
            continue
        n_desc = struct.unpack_from("<H", buf, e + 6)[0]
        ordinal = (n_desc >> 8) & 0xFF
        if 1 <= ordinal < MAX_LIBRARY_ORDINAL and ordinal in remap:
            new_desc = (n_desc & 0x00FF) | ((remap[ordinal] & 0xFF) << 8)
            struct.pack_into("<H", buf, e + 6, new_desc)


def dedupe_thin(buf, slice_off):
    """Dedupe one thin 64-bit Mach-O slice at slice_off. Returns removed count."""
    magic = struct.unpack_from("<I", buf, slice_off)[0]
    if magic != MH_MAGIC_64:
        return 0

    ncmds, sizeofcmds = struct.unpack_from("<II", buf, slice_off + 16)
    cmds_start = slice_off + 32
    cmds_end = cmds_start + sizeofcmds

    # First pass: assign ordinals, detect duplicates, gather LINKEDIT offsets.
    first_ordinal = {}  # name -> new (post-dedup) ordinal of first occurrence.
    remap = {}  # old 1-based ordinal -> new 1-based ordinal.
    old_ordinal = 0
    new_ordinal = 0
    dyld_info = None
    symtab = None
    off = cmds_start
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, off)
        if cmd in DYLIB_LOAD_COMMANDS:
            old_ordinal += 1
            name_off = struct.unpack_from("<I", buf, off + 8)[0]
            name = bytes(buf[off + name_off : off + cmdsize]).split(b"\x00", 1)[0]
            if name in first_ordinal:
                remap[old_ordinal] = first_ordinal[name]  # duplicate -> the kept one.
            else:
                new_ordinal += 1
                first_ordinal[name] = new_ordinal
                remap[old_ordinal] = new_ordinal
        elif cmd in (LC_DYLD_INFO, LC_DYLD_INFO_ONLY):
            # dyld_info_command: cmd, cmdsize, rebase(off,size), bind(off,size),
            # weak_bind(off,size), lazy_bind(off,size), export(off,size).
            vals = struct.unpack_from("<10I", buf, off + 8)
            dyld_info = {
                "bind": (vals[2], vals[3]),
                "weak_bind": (vals[4], vals[5]),
                "lazy_bind": (vals[6], vals[7]),
            }
        elif cmd == LC_SYMTAB:
            symoff, nsyms = struct.unpack_from("<II", buf, off + 8)
            symtab = (symoff, nsyms)
        off += cmdsize

    removed = old_ordinal - new_ordinal
    if removed == 0:
        return 0

    # Only decrements/collapses (never a no-op that we skip). Apply ordinal
    # fixups to LINKEDIT before rewriting the (disjoint) load command region.
    if dyld_info:
        for boff, bsize in dyld_info.values():
            if bsize:
                _remap_bind_stream(buf, boff, bsize, remap)
    if symtab:
        _remap_symtab(buf, symtab[0], symtab[1], remap)

    # Second pass: rebuild the load command area, dropping duplicate dylibs.
    seen = set()
    kept = bytearray()
    off = cmds_start
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, off)
        drop = False
        if cmd in DYLIB_LOAD_COMMANDS:
            name_off = struct.unpack_from("<I", buf, off + 8)[0]
            name = bytes(buf[off + name_off : off + cmdsize]).split(b"\x00", 1)[0]
            if name in seen:
                drop = True
            seen.add(name)
        if not drop:
            kept.extend(buf[off : off + cmdsize])
        off += cmdsize

    buf[cmds_start:cmds_end] = kept + b"\x00" * (sizeofcmds - len(kept))
    struct.pack_into("<II", buf, slice_off + 16, ncmds - removed, len(kept))
    return removed


def dedupe_file(path):
    with open(path, "rb") as f:
        buf = bytearray(f.read())

    magic = struct.unpack_from(">I", buf, 0)[0]
    total = 0
    if magic in (FAT_MAGIC, FAT_MAGIC_64):
        nfat = struct.unpack_from(">I", buf, 4)[0]
        wide = magic == FAT_MAGIC_64
        entry_size = 32 if wide else 20
        off = 8
        for _ in range(nfat):
            slice_off = struct.unpack_from(">Q" if wide else ">I", buf, off + 8)[0]
            total += dedupe_thin(buf, slice_off)
            off += entry_size
    else:
        total += dedupe_thin(buf, 0)

    if total:
        with open(path, "wb") as f:
            f.write(buf)
    return total


def main(argv):
    if len(argv) != 2:
        print(f"usage: {argv[0]} <mach-o-binary>", file=sys.stderr)
        return 2
    removed = dedupe_file(argv[1])
    if removed:
        print(f"Removed {removed} duplicate dylib load command(s) from {argv[1]}")
    else:
        print(f"No duplicate dylib load commands in {argv[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
