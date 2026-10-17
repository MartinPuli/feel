"""Local-only validation and identity of the exact inputs sent to an evaluation."""
from __future__ import annotations

import base64
import hashlib
import json
import math
from pathlib import Path


class DatasetError(ValueError):
    pass


def _finite_number(value) -> bool:
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def prepare(labels: Path) -> tuple[list[dict], dict]:
    """Validate the complete label file before decoding photos or using any SDK."""
    try:
        lines = labels.read_text(encoding='utf-8').splitlines()
    except (OSError, UnicodeError) as error:
        raise DatasetError('Cannot read the label file.') from error
    items = []
    root = labels.resolve().parent
    for number, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except ValueError as error:
            raise DatasetError(f'Row {number}: invalid JSON.') from error
        if not isinstance(item, dict) or set(item) != {'image', 'question', 'box'}:
            raise DatasetError(f'Row {number}: requires exactly image, question and box.')
        if not isinstance(item['question'], str) or not item['question'].strip():
            raise DatasetError(f'Row {number}: question must be non-empty text.')
        name = item['image']
        if not isinstance(name, str) or not name or Path(name).is_absolute():
            raise DatasetError(f'Row {number}: image must be a relative file path.')
        path = (root / name).resolve()
        if root not in path.parents or not path.is_file():
            raise DatasetError(f'Row {number}: image must exist inside the label directory.')
        box = item['box']
        if box is not None and not (
            isinstance(box, list) and len(box) == 4
            and all(_finite_number(value) for value in box)
            and 0 <= box[0] < box[2] <= 1 and 0 <= box[1] < box[3] <= 1
        ):
            raise DatasetError(f'Row {number}: invalid normalized box.')
        items.append((number, path, item))
    if not items:
        raise DatasetError('No labeled rows; an empty evaluation cannot pass.')
    absent = sum(item['box'] is None for _, _, item in items)
    if absent * 3 < len(items):
        raise DatasetError('At least one third of rows must label the object absent.')

    # Import Pillow only after label validation; this module has no cloud dependencies.
    from feel_chalk import images
    rows = []
    for number, path, item in items:
        try:
            jpeg = images.phone_jpeg(path.read_bytes())
        except Exception as error:
            raise DatasetError(f'Row {number}: image cannot be decoded and normalized.') from error
        rows.append({'question': item['question'], 'image_b64': base64.b64encode(jpeg).decode('ascii'),
                     'expected_box': json.dumps(item['box'], separators=(',', ':'), allow_nan=False)})
    encoded = json.dumps(rows, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    return rows, {'dataset_sha256': hashlib.sha256(encoded).hexdigest(), 'row_count': len(rows),
                  'absent_count': absent, 'present_count': len(rows) - absent,
                  'image_encoding': {'max_long_side': images.MAX_LONG_SIDE, 'jpeg_quality': images.JPEG_QUALITY},
                  'hash_scope': 'ordered questions, normalized JPEG bytes and expected boxes'}
