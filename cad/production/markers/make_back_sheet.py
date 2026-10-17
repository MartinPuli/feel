#!/usr/bin/env python3
"""Printable back sheet for point-to-describe: one piece cut to the chassis bottom outline.

Three QR codes in the wrist third tell the phone where the puck is and which way up it is;
a faint grid shows the 7 x 4 pin cells as seen from the back. Every number here mirrors
PuckBackLayout in ios/Shared/FeelCore/Sources/FeelCore/Pointing.swift: change both together.

Sheet coordinates (mm), seen from the back with the finger end up:
u = -x_puck (column 0, the user's left, is on the RIGHT), v = y_puck (CAD.md frame).

    pip install segno==1.6.6
    python3 cad/production/markers/make_back_sheet.py      # writes puck-back.svg
"""
from pathlib import Path

import segno

# --- PuckBackLayout (keep in sync) -----------------------------------------------------------
SHEET_U = (-41.25, 41.25)          # chassis bottom flat, x +-41.25
SHEET_V = (-21.0, 59.0)            # flat runs -27.5..59; the wrist strip with the zip-tie slots is left bare
CORNER_R = 6.0                     # flat's corner radius (finger-end corners only; the wrist edge is a cut)
COLUMN_PITCH, ROW_PITCH, FIRST_ROW_V = 12.0, 13.0, 14.5
CODE_SIZE, CODE_CENTER_V = 21.0, -6.0
CODES = [('FEEL:WL', 25.0), ('FEEL:WC', 0.0), ('FEEL:WR', -25.0)]
GRID_U = (-41.0, 41.0)
GRID_V = (8.0, 58.5)
# ---------------------------------------------------------------------------------------------

PAGE_W, PAGE_H = 215.9, 279.4
GRID_GREY = '#c8c8c8'               # light enough that the phone never mistakes it for tape
FONT = 'Helvetica, Arial, sans-serif'


def sheet(ox: float, oy: float, k: int) -> str:
    """One sheet with its top-left page corner at (ox, oy)."""
    u0, u1 = SHEET_U
    v0, v1 = SHEET_V

    def px(u):
        return ox + (u - u0)

    def py(v):
        return oy + (v1 - v)

    w, h, r = u1 - u0, v1 - v0, CORNER_R
    # Outline: rounded finger-end corners, square wrist edge. Dashed = cut line.
    outline = (f'M{px(u0):.3f},{py(v0):.3f} L{px(u0):.3f},{py(v1) + r:.3f} '
               f'A{r},{r} 0 0 1 {px(u0) + r:.3f},{py(v1):.3f} L{px(u1) - r:.3f},{py(v1):.3f} '
               f'A{r},{r} 0 0 1 {px(u1):.3f},{py(v1) + r:.3f} L{px(u1):.3f},{py(v0):.3f} Z')
    parts = [f'<clipPath id="sheet{k}"><path d="{outline}"/></clipPath>',
             f'<path d="{outline}" fill="#fff" stroke="#999" stroke-width="0.25" stroke-dasharray="1.2 1"/>',
             f'<g clip-path="url(#sheet{k})">']
    for c in range(8):
        u = min(max((3.5 - c) * COLUMN_PITCH, GRID_U[0]), GRID_U[1])
        parts.append(f'<line x1="{px(u):.3f}" y1="{py(GRID_V[0]):.3f}" x2="{px(u):.3f}" y2="{py(GRID_V[1]):.3f}" '
                     f'stroke="{GRID_GREY}" stroke-width="0.3"/>')
    for row in range(5):
        v = min(GRID_V[0] + row * ROW_PITCH, GRID_V[1])
        parts.append(f'<line x1="{px(GRID_U[0]):.3f}" y1="{py(v):.3f}" x2="{px(GRID_U[1]):.3f}" y2="{py(v):.3f}" '
                     f'stroke="{GRID_GREY}" stroke-width="0.3"/>')
    for c in range(7):
        for band in range(1, 5):
            u = -(c - 3) * COLUMN_PITCH
            v = FIRST_ROW_V + (band - 1) * ROW_PITCH
            parts.append(f'<text x="{px(u):.3f}" y="{py(v - 5.4):.3f}" font-size="1.8" text-anchor="middle" '
                         f'fill="{GRID_GREY}" font-family="{FONT}">C{c} B{band}</text>')
    parts.append('</g>')
    for payload, cu in CODES:
        qr = segno.make_qr(payload, error='h', version=1)
        n = len(qr.matrix)
        m = CODE_SIZE / n
        x0, y0 = px(cu - CODE_SIZE / 2), py(CODE_CENTER_V + CODE_SIZE / 2)   # QR top = finger end
        for i, row in enumerate(qr.matrix):
            for j, dark in enumerate(row):
                if dark:
                    parts.append(f'<rect x="{x0 + j * m:.3f}" y="{y0 + i * m:.3f}" width="{m + 0.01:.3f}" height="{m + 0.01:.3f}"/>')
    return '\n'.join(parts)


def main() -> None:
    w = SHEET_U[1] - SHEET_U[0]
    h = SHEET_V[1] - SHEET_V[0]
    gap = 12.0
    x0 = (PAGE_W - 2 * w - gap) / 2
    body = [
        f'<text x="{x0}" y="14" font-size="4.6" font-family="{FONT}">FEEL puck back sheet: print at 100% (Actual size); the bar must measure 50 mm</text>',
        f'<rect x="{x0}" y="18" width="50" height="2"/><text x="{x0 + 53}" y="20.3" font-size="3" font-family="{FONT}">50 mm</text>',
        f'<text x="{x0}" y="27" font-size="3" font-family="{FONT}">Cut on the dashed line. Codes go at the WRIST end (cable slot); the rounded corners go at the FINGER end.</text>',
        f'<text x="{x0}" y="31.5" font-size="3" font-family="{FONT}">Printed side out. Matches the production chassis in CAD.md only. Two spares.</text>',
    ]
    for k in range(4):
        body.append(sheet(x0 + (k % 2) * (w + gap), 38 + (k // 2) * (h + gap), k))
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{PAGE_W}mm" height="{PAGE_H}mm" viewBox="0 0 {PAGE_W} {PAGE_H}">\n'
           f'<rect width="100%" height="100%" fill="#fff"/>\n' + '\n'.join(body) + '\n</svg>\n')
    out = Path(__file__).with_name('puck-back.svg')
    out.write_text(svg)
    print(out)


if __name__ == '__main__':
    main()
