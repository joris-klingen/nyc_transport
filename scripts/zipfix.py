"""Read a zip archive whose local-header offsets wrapped at 4 GB (no Zip64 records).

The Donovan and Work FOIL archives (raw/taxi/foil_2010_2013/FOILyyyy.zip, 6.7-8 GB) were written by a
tool that stored the central directory's offset and the local-header offsets of the members beyond
4 GB modulo 2^32, so bsdtar reports a damaged archive and Python's zipfile shifts every offset and
fails on the early members. The central directory itself is intact.

    python3 -I scripts/zipfix.py list OUTER
    python3 -I scripts/zipfix.py extract OUTER MEMBER OUT     (verifies size and CRC-32)

The end-of-central-directory record gives the central directory's size; its offset is taken from
the file end. Entries are walked in central-directory order and each stored offset is raised by
multiples of 2^32 until it lies past the previous entry and a local header with the member's name
is found there. Used by scripts/07_foil_donovan_parquet.R.
"""
import struct, sys, zlib

WRAP = 1 << 32


def entries(path):
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(size - 22)
        eocd = f.read(22)
        if eocd[:4] != b"PK\x05\x06":
            raise SystemExit("no end-of-central-directory record at the file end (comment?)")
        n_cd, size_cd = struct.unpack("<HI", eocd[10:16])
        f.seek(size - 22 - size_cd)
        cd = f.read(size_cd)
        out, pos, prev = [], 0, -1
        for _ in range(n_cd):
            if cd[pos:pos + 4] != b"PK\x01\x02":
                raise SystemExit("bad central-directory signature")
            (flags, method, crc, csize, usize, fnlen, exlen, cmlen, off) = struct.unpack("<HH4xIIIHHH8xI", cd[pos + 8:pos + 46])
            name = cd[pos + 46:pos + 46 + fnlen].decode("utf-8", "replace")
            pos += 46 + fnlen + exlen + cmlen
            true = off
            while True:
                if true > prev:
                    f.seek(true)
                    lh = f.read(30)
                    if lh[:4] == b"PK\x03\x04":
                        lfn, lex = struct.unpack("<HH", lh[26:30])
                        if f.read(lfn).decode("utf-8", "replace") == name:
                            data = true + 30 + lfn + lex
                            break
                true += WRAP
                if true > size:
                    raise SystemExit(f"no local header found for {name}")
            prev = true
            out.append(dict(name=name, method=method, crc=crc, csize=csize, usize=usize, data=data, wrapped=true != off))
        return out


def extract(path, member, out):
    e = next((e for e in entries(path) if e["name"] == member), None)
    if e is None:
        raise SystemExit(f"{member} not in archive")
    crc, n = 0, 0
    with open(path, "rb") as f, open(out, "wb") as dst:
        f.seek(e["data"])
        left = e["csize"]
        inflate = zlib.decompressobj(-15) if e["method"] == 8 else None
        while left > 0:
            chunk = f.read(min(16 << 20, left))
            if not chunk:
                raise SystemExit("unexpected end of file")
            left -= len(chunk)
            if inflate is not None:
                chunk = inflate.decompress(chunk)
            dst.write(chunk)
            crc = zlib.crc32(chunk, crc)
            n += len(chunk)
        if inflate is not None:
            tail = inflate.flush()
            dst.write(tail)
            crc = zlib.crc32(tail, crc)
            n += len(tail)
    ok = n == e["usize"] and crc == e["crc"]
    print(f"{member}: {n} bytes, crc {'ok' if ok else 'MISMATCH'}, offset {'corrected' if e['wrapped'] else 'as stored'} -> {out}")
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "list" and len(sys.argv) == 3:
        for e in entries(sys.argv[2]):
            print(f"{e['name']}\t{e['usize']}\t{e['method']}\t{'wrapped' if e['wrapped'] else ''}")
    elif cmd == "extract" and len(sys.argv) == 5:
        extract(*sys.argv[2:5])
    else:
        raise SystemExit(__doc__)
