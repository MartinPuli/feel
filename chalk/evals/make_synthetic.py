"""Render a small synthetic Where-is dataset: plain walls with an EXIT sign or a door drawn at a
known place, or deliberately absent. No consent is needed, so the whole evaluation pipeline can be
exercised today; the numbers say how the pipeline behaves, not how a model does on real venues.

python evals/make_synthetic.py data/synthetic --rows 12 --seed 7
python -m feel_chalk.where_is_eval data/synthetic/labels.jsonl --preflight --output data/synthetic/preflight.json
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import random

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1280, 960
QUESTIONS = {'exit': 'Where is the exit sign?', 'door': 'Where is the door?'}


def wall(rng: random.Random) -> Image.Image:
    tone = rng.randint(150, 205)
    image = Image.new('RGB', (WIDTH, HEIGHT), (tone, tone, tone - rng.randint(0, 12)))
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, HEIGHT - rng.randint(60, 120), WIDTH, HEIGHT], fill=(tone - 45, tone - 45, tone - 50))
    for _ in range(rng.randint(1, 3)):  # posters and pipes that are not the target
        x, y = rng.randint(0, WIDTH - 200), rng.randint(60, HEIGHT - 400)
        draw.rectangle([x, y, x + rng.randint(60, 180), y + rng.randint(80, 240)], fill=(tone - 25, tone - 20, tone - 15))
    for _ in range(600):
        x, y = rng.randint(0, WIDTH - 1), rng.randint(0, HEIGHT - 1)
        draw.point((x, y), fill=(tone - 8, tone - 8, tone - 8))
    return image


def exit_sign(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=(20, 140, 60), outline=(240, 240, 240), width=4)
    font = ImageFont.load_default(size=int((y1 - y0) * 0.62))
    draw.text(((x0 + x1) / 2, (y0 + y1) / 2), 'EXIT', fill='white', font=font, anchor='mm')


def door(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=(110, 72, 40), outline=(70, 45, 25), width=8)
    draw.rectangle([x0 + 24, y0 + 24, x1 - 24, (y0 + y1) / 2 - 12], outline=(80, 52, 28), width=4)
    draw.rectangle([x0 + 24, (y0 + y1) / 2 + 12, x1 - 24, y1 - 24], outline=(80, 52, 28), width=4)
    handle = (x1 - 40, (y0 + y1) / 2)
    draw.ellipse([handle[0] - 10, handle[1] - 10, handle[0] + 10, handle[1] + 10], fill=(220, 200, 90))


def place(rng: random.Random, kind: str) -> tuple[int, int, int, int]:
    if kind == 'exit':
        width = rng.randint(150, 330)
        height = int(width / 2.4)
        y0 = rng.randint(40, 320)
    else:
        height = rng.randint(420, 620)
        width = int(height / 2.1)
        y0 = HEIGHT - 110 - height
    x0 = rng.randint(30, WIDTH - width - 30)
    return x0, y0, x0 + width, y0 + height


def build(directory: Path, rows: int, seed: int) -> list[dict]:
    rng = random.Random(seed)
    photos = directory / 'photos'
    photos.mkdir(parents=True, exist_ok=True)
    labels = []
    for index in range(rows):
        kind = 'exit' if index % 2 == 0 else 'door'
        present = index % 3 != 2  # one third absent, as the dataset rules require
        image = wall(rng)
        draw = ImageDraw.Draw(image)
        box = None
        if present:
            pixels = place(rng, kind)
            (exit_sign if kind == 'exit' else door)(draw, pixels)
            box = [round(pixels[0] / WIDTH, 4), round(pixels[1] / HEIGHT, 4), round(pixels[2] / WIDTH, 4), round(pixels[3] / HEIGHT, 4)]
        name = f'photos/synthetic-{index + 1:02d}.jpg'
        image.save(directory / name, format='JPEG', quality=85)
        labels.append({'image': name, 'question': QUESTIONS[kind], 'box': box})
    (directory / 'labels.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in labels), encoding='utf-8')
    return labels


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('directory', type=Path, help='Output directory (git-ignored chalk/data/... is the place)')
    parser.add_argument('--rows', type=int, default=12)
    parser.add_argument('--seed', type=int, default=7)
    args = parser.parse_args(argv)
    if args.rows < 3:
        print('At least 3 rows, so that one third can be absent.')
        return 2
    labels = build(args.directory, args.rows, args.seed)
    absent = sum(row['box'] is None for row in labels)
    print(f'Wrote {len(labels)} rows to {args.directory / "labels.jsonl"} ({absent} absent).')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
