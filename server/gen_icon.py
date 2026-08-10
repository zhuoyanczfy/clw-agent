# -*- coding: utf-8 -*-
"""生成 APP 图标：粉色渐变底 + 白色爱心 + 一碗面，输出各 mipmap 尺寸"""
import math
import os

from PIL import Image, ImageDraw

SIZE = 1024
OUT_DIR = r"D:\code\clw_agent\app\android\app\src\main\res"


def lerp(a, b, t):
    return int(a + (b - a) * t)


def gradient_bg(draw, size):
    """粉白到暖粉的垂直渐变"""
    top = (255, 214, 221)   # 浅粉
    bottom = (255, 140, 158)  # 主题粉
    for y in range(size):
        t = y / size
        color = (lerp(top[0], bottom[0], t),
                 lerp(top[1], bottom[1], t),
                 lerp(top[2], bottom[2], t))
        draw.line([(0, y), (size, y)], fill=color)


def heart_points(cx, cy, scale, samples=200):
    """心形参数方程采样点"""
    pts = []
    for i in range(samples):
        t = 2 * math.pi * i / samples
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * scale, cy - y * scale))
    return pts


def draw_bowl(draw, cx, cy, r):
    """在爱心中画一碗面（白色描边）"""
    white = (255, 255, 255)
    # 碗身（半圆）
    draw.pieslice([cx - r, cy - r, cx + r, cy + r], 0, 180, fill=white)
    # 碗口椭圆
    draw.ellipse([cx - r, cy - r * 0.45, cx + r, cy + r * 0.15], outline=white, width=int(r * 0.12))
    # 热气曲线
    for dx in (-r * 0.45, 0, r * 0.45):
        x = cx + dx
        pts = [(x, cy - r * 1.35), (x + r * 0.15, cy - r * 1.55), (x, cy - r * 1.75)]
        draw.line(pts, fill=white, width=int(r * 0.1), joint="curve")


def generate(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 渐变背景（带圆角）
    bg = Image.new("RGBA", (size, size))
    bg_draw = ImageDraw.Draw(bg)
    gradient_bg(bg_draw, size)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size, size], radius=int(size * 0.22), fill=255)
    img.paste(bg, (0, 0), mask)

    draw = ImageDraw.Draw(img)
    s = size / 1024
    # 白色爱心
    heart = heart_points(size * 0.5, size * 0.46, size * 0.23)
    draw.polygon(heart, fill=(255, 255, 255, 255))
    # 碗（用主题粉在爱心中绘制）
    draw_bowl(draw, size * 0.5, size * 0.52, size * 0.14)
    return img


def main():
    master = generate(SIZE)
    targets = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in targets.items():
        path = os.path.join(OUT_DIR, folder, "ic_launcher.png")
        master.resize((size, size), Image.LANCZOS).save(path)
        print("生成", path, size, "x", size)
    # 同时生成一份高清原图供预览
    master.save(r"D:\code\clw_agent\app\icon_preview.png")


if __name__ == "__main__":
    main()
