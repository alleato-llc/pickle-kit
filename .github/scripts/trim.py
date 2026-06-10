#!/usr/bin/env python3
"""Trim each PNG in <src> to its content bounding box (+ a small margin) and
write it to <dst>. Background is taken from the top-left pixel, so it works for
any page colour. Usage: trim.py <src-dir> <dst-dir>"""
import sys
from pathlib import Path
from PIL import Image, ImageChops

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
dst.mkdir(parents=True, exist_ok=True)

for png in sorted(src.glob("*.png")):
    im = Image.open(png).convert("RGB")
    background = Image.new("RGB", im.size, im.getpixel((0, 0)))
    bbox = ImageChops.difference(im, background).getbbox()
    if bbox:
        margin = 40
        left, top, right, bottom = bbox
        im = im.crop((max(0, left - margin), max(0, top - margin),
                      min(im.width, right + margin), min(im.height, bottom + margin)))
    im.save(dst / png.name)
    print(f"{png.name} -> {im.size[0]}x{im.size[1]}")
