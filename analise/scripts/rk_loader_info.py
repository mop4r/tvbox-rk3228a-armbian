"""Lê o cabeçalho de um loader Rockchip (formato BOOT, o mesmo do boot_merger do rkdeveloptool).

Uso: python -I rk_loader_info.py <loader.bin> [...]

Estruturas (packed, little-endian) tiradas de rkdeveloptool/boot_merger.h:
  rk_boot_header: tag 'BOOT', size u16, version u32, mergerVersion u32, rk_time(7 bytes),
                  chipType u32, code471 (num u8, offset u32, size u8), code472 (idem),
                  loader (idem), signFlag u8, rc4Flag u8
  rk_boot_entry : size u8, type u32, name u16[20], dataOffset u32, dataSize u32, dataDelay u32
Entradas 471 = DDR init (vai para a SRAM), 472 = usbplug (vai para a DRAM),
entradas "loader" = FlashData/FlashBoot (gravadas no IDB do eMMC).
"""
import struct
import sys
import zlib

HDR = struct.Struct("<4sHII HBBBBB I BIB BIB BIB BB")
ENT = struct.Struct("<BI40sIII")


def chip(v):
    b = struct.pack("<I", v)
    txt = b[::-1].decode("latin-1")
    return txt if txt.isprintable() else hex(v)


def ler(caminho):
    dados = open(caminho, "rb").read()
    h = HDR.unpack_from(dados, 0)
    (tag, size, version, merger, ano, mes, dia, hora, mi, seg, chiptype,
     n471, o471, s471, n472, o472, s472, nl, ol, sl, sign, rc4) = h
    print(f"== {caminho}")
    if tag != b"BOOT" and tag != b"LDR ":
        print(f"   tag inesperada {tag!r}: não é loader BOOT")
        return
    print(f"   tag={tag.decode()} versão={version >> 8:x}.{version & 0xff:02x} merger=0x{merger:x} "
          f"data={ano:04d}-{mes:02d}-{dia:02d} {hora:02d}:{mi:02d} chip={chip(chiptype)} "
          f"sign={sign} rc4={'NÃO' if rc4 else 'sim'} ({rc4})")
    for nome, n, off, sz in (("471 (DDR/SRAM)", n471, o471, s471),
                             ("472 (usbplug/DRAM)", n472, o472, s472),
                             ("loader (IDB)", nl, ol, sl)):
        for i in range(n):
            e = ENT.unpack_from(dados, off + i * sz)
            esize, etype, ename, doff, dsize, ddelay = e
            nm = ename.decode("utf-16le").split("\0")[0]
            crc = zlib.crc32(dados[doff:doff + dsize]) & 0xffffffff
            print(f"   {nome:20s} #{i}: {nm:12s} offset=0x{doff:06x} tamanho={dsize:7d} "
                  f"atraso={ddelay}ms crc32={crc:08x}")
    print(f"   arquivo={len(dados)} bytes (os últimos 4 são o CRC32 do loader)")


if __name__ == "__main__":
    for c in sys.argv[1:]:
        ler(c)
