"""Dependency-free PNG compare helpers for LocationStudio's screenshot regression tool."""
from __future__ import annotations

import struct
import zlib
from pathlib import Path


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else b if pb <= pc else c


def read_png(path: str | Path) -> tuple[int, int, list[tuple[int, int, int, int]]]:
    """Decode non-interlaced 8-bit PNGs (the format emitted by grim)."""
    raw = Path(path).read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG image: {path}")
    offset = 8
    width = height = bit_depth = color_type = interlace = None
    palette = b""
    transparency = b""
    compressed = bytearray()
    while offset + 12 <= len(raw):
        length = struct.unpack_from(">I", raw, offset)[0]
        kind = raw[offset + 4:offset + 8]
        data = raw[offset + 8:offset + 8 + length]
        if len(data) != length:
            raise ValueError("truncated PNG chunk")
        if kind == b"IHDR":
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", data)
            if compression or filtering or bit_depth != 8 or interlace:
                raise ValueError("only non-interlaced 8-bit PNG screenshots are supported")
        elif kind == b"PLTE":
            palette = data
        elif kind == b"tRNS":
            transparency = data
        elif kind == b"IDAT":
            compressed.extend(data)
        elif kind == b"IEND":
            break
        offset += length + 12
    if not width or not height or color_type not in (0, 2, 3, 4, 6):
        raise ValueError("unsupported or missing PNG image header")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    bpp = channels
    stride = width * channels
    packed = zlib.decompress(compressed)
    if len(packed) != height * (stride + 1):
        raise ValueError("PNG pixel data has an unexpected size")
    rows: list[bytes] = []
    pos = 0
    for _ in range(height):
        filt = packed[pos]
        scan = bytearray(packed[pos + 1:pos + 1 + stride])
        pos += stride + 1
        prev = rows[-1] if rows else bytes(stride)
        for i in range(stride):
            left = scan[i - bpp] if i >= bpp else 0
            up = prev[i]
            upper_left = prev[i - bpp] if i >= bpp else 0
            if filt == 1:
                scan[i] = (scan[i] + left) & 255
            elif filt == 2:
                scan[i] = (scan[i] + up) & 255
            elif filt == 3:
                scan[i] = (scan[i] + ((left + up) // 2)) & 255
            elif filt == 4:
                scan[i] = (scan[i] + _paeth(left, up, upper_left)) & 255
            elif filt != 0:
                raise ValueError(f"unsupported PNG filter {filt}")
        rows.append(bytes(scan))
    pixels: list[tuple[int, int, int, int]] = []
    if color_type == 3 and not palette:
        raise ValueError("indexed PNG has no palette")
    for row in rows:
        for x in range(width):
            i = x * channels
            if color_type == 6:
                px = tuple(row[i:i + 4])
            elif color_type == 2:
                px = (*row[i:i + 3], 255)
            elif color_type == 0:
                g = row[i]
                px = (g, g, g, 255)
            elif color_type == 4:
                g, a = row[i:i + 2]
                px = (g, g, g, a)
            else:
                index = row[i]
                j = index * 3
                if j + 2 >= len(palette):
                    raise ValueError("PNG palette index out of range")
                px = (palette[j], palette[j + 1], palette[j + 2], transparency[index] if index < len(transparency) else 255)
            pixels.append(px)
    return width, height, pixels


def write_rgba_png(path: str | Path, width: int, height: int, pixels: list[tuple[int, int, int, int]]) -> None:
    if len(pixels) != width * height:
        raise ValueError("pixel count does not match image dimensions")
    scanlines = bytearray()
    for y in range(height):
        scanlines.append(0)
        for r, g, b, a in pixels[y * width:(y + 1) * width]:
            scanlines.extend((r, g, b, a))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    encoded = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(scanlines, 6)) + chunk(b"IEND", b"")
    Path(path).write_bytes(encoded)


def compare_pngs(baseline: str | Path, current: str | Path, diff_path: str | Path,
                 pixel_threshold: int = 24) -> dict:
    """Compare RGB pixel changes; output a red-on-dark heatmap and normalized metrics."""
    bw, bh, base = read_png(baseline)
    cw, ch, now = read_png(current)
    if (bw, bh) != (cw, ch):
        return {"compatible": False, "baseline_size": [bw, bh], "current_size": [cw, ch],
                "changed_fraction": 1.0, "mean_absolute_error": None}
    changed = 0
    total_delta = 0
    heat: list[tuple[int, int, int, int]] = []
    for a, b in zip(base, now):
        delta = max(abs(a[i] - b[i]) for i in range(3))
        total_delta += sum(abs(a[i] - b[i]) for i in range(3))
        if delta > pixel_threshold:
            changed += 1
            heat.append((255, max(0, 64 - delta // 4), 0, 255))
        else:
            shade = (a[0] + a[1] + a[2]) // 18
            heat.append((shade, shade, shade, 255))
    write_rgba_png(diff_path, bw, bh, heat)
    count = bw * bh
    return {"compatible": True, "size": [bw, bh], "changed_pixels": changed,
            "changed_fraction": changed / count,
            "mean_absolute_error": total_delta / (count * 3 * 255),
            "pixel_threshold": pixel_threshold, "diff_image": str(diff_path)}
