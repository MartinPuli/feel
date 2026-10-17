"""Where-is contract: the prompt, the request body and the answer parser.

The phone (FeelCore/WhereIs.swift) and the evaluation must use the same prompt
and parse answers the same way. tests/test_where_is.py checks both against
protocol/where-is-prompt.txt and protocol/where-is-cases.json.
"""
from __future__ import annotations
from dataclasses import dataclass
import json
import math

# Kept identical to protocol/where-is-prompt.txt. Embedded so it ships with
# this package when Chalk runs the evaluation task remotely.
PROMPT = """You help a blind person find things using one photo from a chest-mounted phone camera.
The user asks where something is. Look only at this photo.
If the thing is clearly visible, give its bounding box.
If it is not visible, or you are not sure, say it is not found. Never guess.
Reply with one JSON object and nothing else, in exactly one of these two forms:
{"found": true, "label": "<short name of what you found>", "box": [x_min, y_min, x_max, y_max], "confidence": <number from 0 to 1>}
{"found": false, "label": "", "box": null, "confidence": 0}
Box values are fractions of the image width and height, from 0 to 1, with (0, 0) at the top-left corner."""


class AnswerError(ValueError):
    """The model's reply cannot be used as guidance. Treat it as not found."""


@dataclass(frozen=True)
class Answer:
    found: bool
    label: str
    box: tuple[float, float, float, float] | None  # x_min, y_min, x_max, y_max; top-left origin
    confidence: float

    def center(self) -> tuple[float, float] | None:
        if self.box is None:
            return None
        x0, y0, x1, y1 = self.box
        return ((x0 + x1) / 2, (y0 + y1) / 2)


def _number(value, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise AnswerError(f'{field} must be a finite number')
    try:
        number = float(value)
    except (OverflowError, ValueError):
        raise AnswerError(f'{field} must be a finite number') from None
    if not math.isfinite(number):
        raise AnswerError(f'{field} must be a finite number')
    return number


def parse(text: str) -> Answer:
    """Strictly parse one model reply. Anything malformed raises AnswerError."""
    body = text.strip()
    if body.startswith('```'):
        body = body.strip('`').strip()
        if body.startswith('json'):
            body = body[4:]
    try:
        # JSONDecoder rejects non-JSON constants even in otherwise unused fields.
        def reject_constant(value: str):
            raise AnswerError(f'reply contains a non-JSON number: {value}')
        data = json.loads(body, parse_constant=reject_constant)
    except json.JSONDecodeError as error:
        raise AnswerError(f'reply is not JSON: {error}') from None
    if not isinstance(data, dict):
        raise AnswerError('reply must be a JSON object')
    found = data.get('found')
    if not isinstance(found, bool):
        raise AnswerError('found must be true or false')
    # Match Swift's optional Decodable fields: missing and null use defaults,
    # but a supplied field of the wrong type is invalid even when found is false.
    label = data.get('label')
    if label is None:
        label = ''
    if not isinstance(label, str):
        raise AnswerError('label must be text')
    raw_confidence = data.get('confidence')
    confidence = _number(0 if raw_confidence is None else raw_confidence, 'confidence')
    if not 0 <= confidence <= 1:
        raise AnswerError('confidence must be between 0 and 1')
    box = data.get('box')
    if box is not None:
        if not isinstance(box, list):
            raise AnswerError('box must be an array of numbers or null')
        box = tuple(_number(v, 'box') for v in box)
    if not found:
        return Answer(False, label, None, confidence)
    if box is None or len(box) != 4:
        raise AnswerError('a found answer needs a box of four numbers')
    x0, y0, x1, y1 = box
    if not (0 <= x0 < x1 <= 1 and 0 <= y0 < y1 <= 1):
        raise AnswerError('box must lie inside the image with positive width and height')
    return Answer(True, label, (x0, y0, x1, y1), confidence)


def request_body(model: str, question: str, jpeg_base64: str) -> dict:
    """OpenAI-compatible chat completion request, as sent through Chalk's Model Gateway."""
    # No temperature: current Anthropic models reject sampling parameters.
    return {
        'model': model,
        'messages': [
            {'role': 'system', 'content': PROMPT},
            {'role': 'user', 'content': [
                {'type': 'text', 'text': question},
                {'type': 'image_url', 'image_url': {'url': f'data:image/jpeg;base64,{jpeg_base64}'}},
            ]},
        ],
    }


def points_at(answer: Answer, expected_box: tuple[float, float, float, float] | None) -> bool:
    """Evaluation rule: correct when the answer's centre lands inside the labeled box,
    or when nothing was labeled and the answer says not found."""
    if expected_box is None:
        return not answer.found
    center = answer.center()
    if center is None:
        return False
    x0, y0, x1, y1 = expected_box
    return x0 <= center[0] <= x1 and y0 <= center[1] <= y1
