"""Draws the printed FEEL room tag, ios/Lantern/Resources/feel-tag-01.png (python3 ios/scripts/make_room_tag.py).

Print it 20 cm wide and hang it flat at about chest height. ARPerception tells ARKit that width, and every
remembered target is placed relative to the tag, so a tag printed at another size puts them at the wrong
distance. The pattern is asymmetric and non-repeating on purpose: ARKit image detection needs distinct
corners and refuses images that are too plain or symmetric.
"""
from __future__ import annotations
from pathlib import Path
import random

from PIL import Image, ImageDraw, ImageFont

SIZE = 1200
OUT = Path(__file__).resolve().parents[1] / 'Lantern' / 'Resources' / 'feel-tag-01.png'


def draw() -> Image.Image:
    image = Image.new('L', (SIZE, SIZE), 255)
    d = ImageDraw.Draw(image)
    d.rectangle([0, 0, SIZE - 1, SIZE - 1], outline=0, width=36)
    d.rectangle([60, 60, SIZE - 61, SIZE - 61], outline=0, width=6)
    big, small = ImageFont.load_default(size=150), ImageFont.load_default(size=34)
    d.text((100, 80), 'FEEL', fill=0, font=big)
    d.rectangle([640, 120, 1090, 230], fill=0)
    d.text((665, 140), 'room tag 01', fill=255, font=ImageFont.load_default(size=60))
    rng = random.Random(20261017)                       # fixed seed: the same picture every run
    columns_, rows_, x0, y0 = 8, 6, 100, 300
    cell = (SIZE - 200) // columns_
    for row in range(rows_):
        for column in range(columns_):
            if rng.random() < 0.42:
                continue
            x, y = x0 + column * cell, y0 + row * cell
            pad = rng.randint(6, 36)
            box = [x + pad, y + pad, x + cell - pad, y + cell - pad]
            shape = rng.choice(['rect', 'rect', 'ellipse', 'triangle', 'bar'])
            if shape == 'rect':
                d.rectangle(box, fill=0)
            elif shape == 'ellipse':
                d.ellipse(box, fill=0)
            elif shape == 'triangle':
                d.polygon([(box[0], box[3]), (box[2], box[3]), (rng.choice([box[0], box[2]]), box[1])], fill=0)
            else:
                d.rectangle([box[0], y + cell // 2 - 10, box[2], y + cell // 2 + 10], fill=0)
    d.text((100, 1066), 'feel-tag-01  ·  print 20 cm wide  ·  hang flat at chest height', fill=0, font=small)
    return image


if __name__ == '__main__':
    OUT.parent.mkdir(parents=True, exist_ok=True)
    draw().save(OUT, optimize=True)
    print(OUT)
