"""The photo as the phone sends it, for the evaluation.

ARPerception.swift encodes a Where-is snapshot as a JPEG whose long side is at most 1024 px at
quality 0.6. The evaluation must score the model on the same input, not on full-size venue photos.
"""
from __future__ import annotations
import io

from PIL import Image, ImageOps

MAX_LONG_SIDE = 1024   # ARPerception.swift: long side at most 1024 px
JPEG_QUALITY = 60      # ARPerception.swift: quality 0.6


def phone_jpeg(data: bytes, max_long_side: int = MAX_LONG_SIDE, quality: int = JPEG_QUALITY) -> bytes:
    """Re-encode one photo the way the phone does: shrunk (never enlarged) so its long side is at
    most `max_long_side`, as a JPEG at `quality`. The camera's orientation tag is applied to the
    pixels first, so the model sees the photo upright as the labeler did; a plain re-encode would
    drop the tag and send a portrait photo sideways."""
    with Image.open(io.BytesIO(data)) as source:
        image = ImageOps.exif_transpose(source)
        image.thumbnail((max_long_side, max_long_side), Image.Resampling.LANCZOS)
        if image.mode not in ('RGB', 'L'):
            image = image.convert('RGB')
        out = io.BytesIO()
        image.save(out, format='JPEG', quality=quality)
        return out.getvalue()
