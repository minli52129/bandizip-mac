#!/usr/bin/env python3
"""生成 App 图标（.iconset），不依赖任何第三方库。

用法: python3 Tools/gen_icon.py [输出目录]

思路：用 SDF（有符号距离场）+ 覆盖率抗锯齿，逐个像素画：
  圆角矩形渐变底 + 白色「压缩包」卡片 + 拉链牙齿 + 拉头。
"""

import math
import os
import struct
import sys
import zlib

# 图标尺寸 -> iconset 文件名
ICONSET = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

TOP_COLOR = (0.372, 0.545, 0.965)
BOTTOM_COLOR = (0.145, 0.224, 0.752)
ACCENT = (0.176, 0.302, 0.855)
CARD = (1.0, 1.0, 1.0)


def clamp(value, low=0.0, high=1.0):
    if value < low:
        return low
    if value > high:
        return high
    return value


def sd_round_box(px, py, cx, cy, hw, hh, radius):
    """圆角矩形有符号距离（负值在内部）"""
    qx = abs(px - cx) - (hw - radius)
    qy = abs(py - cy) - (hh - radius)
    ax = qx if qx > 0 else 0.0
    ay = qy if qy > 0 else 0.0
    return math.hypot(ax, ay) + min(max(qx, qy), 0.0) - radius


def coverage(distance_px):
    """把像素单位的距离转成 0..1 覆盖率（1 像素宽的抗锯齿带）"""
    return clamp(0.5 - distance_px)


def blend(dst, sr, sg, sb, sa):
    if sa <= 0.0:
        return dst
    da = dst[3]
    out_a = sa + da * (1.0 - sa)
    if out_a <= 0.0:
        dst[0] = dst[1] = dst[2] = dst[3] = 0.0
        return dst
    dst[0] = (sr * sa + dst[0] * da * (1.0 - sa)) / out_a
    dst[1] = (sg * sa + dst[1] * da * (1.0 - sa)) / out_a
    dst[2] = (sb * sa + dst[2] * da * (1.0 - sa)) / out_a
    dst[3] = out_a
    return dst


def render(size):
    inv = 1.0 / size
    pixels = bytearray()

    # 拉链牙齿参数：小尺寸减少数量，避免糊成一团
    if size <= 32:
        tooth_count = 6
        tooth_y0, tooth_y1 = 0.310, 0.600
    elif size <= 64:
        tooth_count = 9
        tooth_y0, tooth_y1 = 0.300, 0.610
    else:
        tooth_count = 14
        tooth_y0, tooth_y1 = 0.292, 0.616

    teeth = []
    for index in range(tooth_count):
        t = index / max(1, tooth_count - 1)
        cy = tooth_y0 + (tooth_y1 - tooth_y0) * t
        cx = 0.5 + (0.015 if index % 2 == 0 else -0.015)
        teeth.append((cx, cy, 0.036, 0.0095, 0.009))

    for y in range(size):
        py = (y + 0.5) * inv
        for x in range(size):
            px = (x + 0.5) * inv
            dst = [0.0, 0.0, 0.0, 0.0]

            # 1. 圆角矩形底 + 垂直渐变
            d_bg = sd_round_box(px, py, 0.5, 0.5, 0.424, 0.424, 0.188) / inv
            cov = coverage(d_bg)
            if cov > 0.0:
                t = clamp(0.35 * px + 0.75 * py)
                sr = TOP_COLOR[0] + (BOTTOM_COLOR[0] - TOP_COLOR[0]) * t
                sg = TOP_COLOR[1] + (BOTTOM_COLOR[1] - TOP_COLOR[1]) * t
                sb = TOP_COLOR[2] + (BOTTOM_COLOR[2] - TOP_COLOR[2]) * t
                blend(dst, sr, sg, sb, cov)

                # 左上角柔和高光
                dist = math.hypot(px - 0.26, py - 0.16)
                highlight = max(0.0, 1.0 - dist / 0.62)
                if highlight > 0.0:
                    blend(dst, 1.0, 1.0, 1.0, cov * 0.20 * highlight * highlight)

            # 2. 卡片投影
            d_shadow = sd_round_box(px, py - 0.016, 0.5, 0.522, 0.232, 0.262, 0.052) / inv
            if d_shadow > -4.0:
                blur = 0.030 * size
                factor = clamp(1.0 - d_shadow / blur)
                if factor > 0.0:
                    blend(dst, 0.05, 0.08, 0.22, 0.22 * factor * factor * dst[3])

            # 3. 白色卡片
            d_card = sd_round_box(px, py, 0.5, 0.522, 0.232, 0.262, 0.052) / inv
            card_cov = coverage(d_card)
            if card_cov > 0.0:
                shade = 0.94 + 0.06 * clamp((0.79 - py) / 0.52)
                blend(dst, CARD[0] * shade, CARD[1] * shade, CARD[2] * shade, card_cov)
                if 0.0 <= d_card <= 1.4:
                    blend(dst, 0.10, 0.16, 0.34, 0.07 * card_cov)

            # 4. 拉链布带
            d_tape = sd_round_box(px, py, 0.5, 0.468, 0.0235, 0.190, 0.016) / inv
            tape_cov = coverage(d_tape)
            if tape_cov > 0.0:
                blend(dst, 0.815, 0.860, 0.945, tape_cov * 0.95)

            # 5. 拉链牙齿
            for (cx, cy, hw, hh, radius) in teeth:
                if px < cx - hw - inv or px > cx + hw + inv or py < cy - hh - inv or py > cy + hh + inv:
                    continue
                d_tooth = sd_round_box(px, py, cx, cy, hw, hh, radius) / inv
                tooth_cov = coverage(d_tooth)
                if tooth_cov > 0.0:
                    blend(dst, ACCENT[0], ACCENT[1], ACCENT[2], tooth_cov)

            # 6. 拉头（连接杆 + 拉片 + 孔）
            d_stem = sd_round_box(px, py, 0.5, 0.634, 0.017, 0.026, 0.008) / inv
            stem_cov = coverage(d_stem)
            if stem_cov > 0.0:
                blend(dst, ACCENT[0], ACCENT[1], ACCENT[2], stem_cov)

            d_pull = sd_round_box(px, py, 0.5, 0.688, 0.049, 0.057, 0.040) / inv
            pull_cov = coverage(d_pull)
            if pull_cov > 0.0:
                blend(dst, ACCENT[0], ACCENT[1], ACCENT[2], pull_cov)

            d_hole = (math.hypot(px - 0.5, py - 0.702) - 0.0165) / inv
            hole_cov = coverage(d_hole)
            if hole_cov > 0.0:
                blend(dst, 0.94, 0.96, 1.0, hole_cov * 0.95)

            pixels += bytes((
                int(clamp(dst[0]) * 255 + 0.5),
                int(clamp(dst[1]) * 255 + 0.5),
                int(clamp(dst[2]) * 255 + 0.5),
                int(clamp(dst[3]) * 255 + 0.5),
            ))

    return pixels


def write_png(path, size, pixels):
    raw = bytearray()
    stride = size * 4
    for y in range(size):
        raw.append(0)
        raw += pixels[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" +
           chunk(b"IHDR", header) +
           chunk(b"IDAT", zlib.compress(bytes(raw), 9)) +
           chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(png)


def main():
    output = sys.argv[1] if len(sys.argv) > 1 else "build/AppIcon.iconset"
    os.makedirs(output, exist_ok=True)

    cache = {}
    for size, name in ICONSET:
        if size not in cache:
            cache[size] = render(size)
        path = os.path.join(output, name)
        write_png(path, size, cache[size])
        print("generated", path)


if __name__ == "__main__":
    main()
