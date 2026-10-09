"""Draw the Gael optic reticles used by both Project Viewpoint mod versions.

Requires Pillow. White pixels are tinted by the ADS overlay at runtime.
The patterns are clean game assets based on the user's ADS screenshots and
the available OKP-7 and Kobra mark diagrams, not copies of source images.
"""

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "Contents/mods/ViewpointGaelCompat"
SCALE = 4
WHITE = (255, 255, 255, 255)


def make(name, painter):
    image = Image.new("RGBA", (256 * SCALE, 256 * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    def line(points, width=5):
        draw.line([(round(x * SCALE), round(y * SCALE)) for x, y in points],
                  fill=WHITE, width=width * SCALE, joint="curve")

    def ring(radius, width=5):
        c, r = 128 * SCALE, radius * SCALE
        draw.ellipse((c - r, c - r, c + r, c + r), outline=WHITE,
                     width=width * SCALE)

    def dot(x=128, y=128, radius=7):
        x, y, r = x * SCALE, y * SCALE, radius * SCALE
        draw.ellipse((x - r, y - r, x + r, y + r), fill=WHITE)

    painter(line, ring, dot)
    output = image.resize((256, 256), Image.Resampling.LANCZOS)
    for version in ("42", "42.20"):
        directory = ROOT / version / "media/textures/PVADS"
        directory.mkdir(parents=True, exist_ok=True)
        output.save(directory / f"ret_{name}.png")


# OKP-7 arrow and separate short stem, following the supplied red/green
# reference. The mark is one shape; the overlay's tint chooses its colour.
make("okp7", lambda line, ring, dot: (
    line([(61, 109), (105, 109)]),
    line([(151, 109), (195, 109)]),
    line([(112, 127), (128, 109), (144, 127)]),
    line([(128, 139), (128, 162)]),
))

# Other OKP-7 marks described in its maker's reticle catalogue.
make("okp7_ring", lambda line, ring, dot: (ring(58), dot(radius=7)))
make("okp7_rings", lambda line, ring, dot: (
    ring(78), ring(34), dot(radius=7),
))

# Kobra's four documented patterns are T, dot + chevron, chevron, and dot.
# PVADS already provides a plain dot asset. The dotted T reproduces the
# individual LED spots visible in the user's close-up of that same T mark.
make("kobra_open", lambda line, ring, dot: (
    line([(65, 111), (106, 111)]),
    line([(150, 111), (191, 111)]),
    line([(128, 148), (128, 171)]),
))
make("kobra_dotted", lambda line, ring, dot: (
    *(dot(x, 111, 6) for x in (69, 83, 97, 159, 173, 187)),
    dot(128, 149, 6), dot(128, 166, 6),
))
make("kobra_combo", lambda line, ring, dot: (
    dot(128, 104, 7),
    line([(105, 149), (128, 124), (151, 149)]),
))
make("kobra_chevron", lambda line, ring, dot: (
    line([(105, 149), (128, 124), (151, 149)]),
))
