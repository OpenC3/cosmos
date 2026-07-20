import math
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

UPM = 1000
GEAR_CP = 0xE900
CLOSE_CP = 0xE901


def _ccw(pts):
    """Return pts ordered counter-clockwise (positive signed area) so every
    contour has the same winding and nonzero fill unions overlaps solidly."""
    area = sum(
        pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
        for i in range(len(pts))
    )
    return pts if area >= 0 else pts[::-1]


def build_close():
    """An X (close) icon: two crossed diagonal bars."""
    pen = TTGlyphPen(None)
    cx, cy = 500, 440
    h = 300  # half-length of each diagonal
    t = 140  # bar thickness
    def bar(x1, y1, x2, y2):
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy)
        px, py = -dy / length * (t / 2), dx / length * (t / 2)
        pts = [(x1 + px, y1 + py), (x2 + px, y2 + py), (x2 - px, y2 - py), (x1 - px, y1 - py)]
        pts = _ccw([(round(a), round(b)) for a, b in pts])
        pen.moveTo(pts[0])
        for p in pts[1:]:
            pen.lineTo(p)
        pen.closePath()
    bar(cx - h, cy - h, cx + h, cy + h)
    bar(cx - h, cy + h, cx + h, cy - h)
    return pen.glyph()


def build_gear():
    pen = TTGlyphPen(None)
    cx, cy = 500, 440
    r_out, r_in, r_hole = 440, 300, 160
    teeth = 8
    step = 2 * math.pi / teeth
    P = lambda a, r: (round(cx + r * math.cos(a)), round(cy + r * math.sin(a)))
    # Outer cog: counter-clockwise (increasing angle, y-up).
    started = False
    for i in range(teeth):
        a0 = i * step; a1 = a0 + step * 0.5; a2 = a0 + step
        for p in (P(a0, r_in), P(a0, r_out), P(a1, r_out), P(a1, r_in), P(a2, r_in)):
            if not started:
                pen.moveTo(p); started = True
            else:
                pen.lineTo(p)
    pen.closePath()
    # Center hole: clockwise (decreasing angle) so nonzero winding cuts it out.
    n = 32; started = False
    for i in range(n):
        p = P(-2 * math.pi * i / n, r_hole)
        if not started:
            pen.moveTo(p); started = True
        else:
            pen.lineTo(p)
    pen.closePath()
    return pen.glyph()

fb = FontBuilder(UPM, isTTF=True)
fb.setupGlyphOrder([".notdef", "gear", "close"])
fb.setupCharacterMap({GEAR_CP: "gear", CLOSE_CP: "close"})
fb.setupGlyf(
    {".notdef": TTGlyphPen(None).glyph(), "gear": build_gear(), "close": build_close()}
)
fb.setupHorizontalMetrics({".notdef": (600, 0), "gear": (1000, 60), "close": (1000, 100)})
fb.setupHorizontalHeader(ascent=900, descent=-100)
fb.setupNameTable(
    {
        "familyName": "openc3-icons",
        "styleName": "Regular",
        "fullName": "openc3-icons Regular",
        "psName": "openc3-icons-Regular",
        "uniqueFontIdentifier": "openc3-icons-Regular-1.0",
        "version": "Version 1.0",
    }
)
fb.setupOS2(sTypoAscender=900, sTypoDescender=-100, usWinAscent=900, usWinDescent=100, sCapHeight=880)
fb.setupPost()
fb.save("assets/openc3-icons.ttf")

# Verify round-trip.
from fontTools.ttLib import TTFont
f = TTFont("assets/openc3-icons.ttf")
cmap = f.getBestCmap()
print(
    "saved. family:", f["name"].getDebugName(1),
    "| gear U+E900:", GEAR_CP in cmap,
    "| close U+E901:", CLOSE_CP in cmap,
)
