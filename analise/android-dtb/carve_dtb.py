"""Recorta todos os device trees (FDT, magic d00dfeed) de uma imagem de firmware.

Uso: python -I carve_dtb.py <imagem> <pasta_saida>
So le a imagem; nada dela e executado. Cada FDT valido vira dtb-<offset>.dtb.
"""
import mmap
import struct
import sys
from pathlib import Path

MAGIC = b"\xd0\x0d\xfe\xed"


def main(img: str, out: str) -> None:
    dst = Path(out)
    dst.mkdir(parents=True, exist_ok=True)
    with open(img, "rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
        pos, n = 0, 0
        while True:
            pos = m.find(MAGIC, pos)
            if pos < 0:
                break
            hdr = m[pos:pos + 40]
            if len(hdr) == 40:
                total, off_struct, off_strings, _, version = struct.unpack(">IIIII", hdr[4:24])
                # filtros de sanidade de um FDT real
                if 0x100 < total < 4 * 1024 * 1024 and off_struct < total and off_strings < total and 16 <= version <= 17:
                    blob = m[pos:pos + total]
                    name = dst / f"dtb-{pos:010x}.dtb"
                    name.write_bytes(blob)
                    n += 1
                    print(f"FDT em 0x{pos:x} tamanho {total} versao {version} -> {name.name}")
            pos += 4
    print(f"{n} device trees recortados")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
