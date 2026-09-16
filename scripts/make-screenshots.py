#!/usr/bin/env python3
"""Turn raw ClaudeDeck card snapshots into README images and a GitHub social preview.

Usage:
  python3 scripts/make-screenshots.py <snapshot dir> [--out docs/images] [--scale auto|1|2]

The snapshot directory holds PNGs written by the app's debug `snapshot` action (see CONTRIBUTING.md):

  main.png      the card with the session list    -> hero.png (+ social-preview.png)
  details.png   a row expanded to show details    -> details.png (and next to main.png in hero.png)
  recent.png    the Recent tab                    -> recent.png
  settings.png  the settings screen               -> settings.png

Each card (rounded corners, transparent outside) is composited onto a soft macOS-style gradient
"desktop" with a large drop shadow. Missing inputs are skipped. Requires Pillow.
"""
import argparse
import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:  # pragma: no cover
    sys.exit("make-screenshots.py needs Pillow: python3 -m pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON = os.path.join(ROOT, "Resources", "AppIcon-1024.png")
SOCIAL_SIZE = (1280, 640)

# Base diagonal gradient (top-left -> bottom-right) plus soft color blobs: (x, y, radius, rgb, strength),
# with positions and radius relative to the canvas.
BASE = ((34, 26, 52), (214, 128, 92))
BLOBS = [
    (0.10, 0.95, 0.75, (70, 72, 150), 0.85),   # blue-violet, bottom left
    (0.55, 0.05, 0.60, (176, 92, 132), 0.70),  # dusty pink, top
    (0.95, 0.55, 0.65, (242, 170, 122), 0.80), # peach, right
    (0.00, 0.00, 0.55, (22, 18, 38), 0.90),    # deep plum, top left corner
]

FONT_CANDIDATES = [
    ("/System/Library/Fonts/SFNS.ttf", 0),
    ("/System/Library/Fonts/Helvetica.ttc", 0),
    ("/Library/Fonts/Arial.ttf", 0),
]


def lerp(a, b, t):
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def gradient(size):
    """Smooth multi-color gradient, computed at low resolution and scaled up (fast without numpy)."""
    width, height = size
    step = 8
    small_w, small_h = max(2, math.ceil(width / step)), max(2, math.ceil(height / step))
    small = Image.new("RGB", (small_w, small_h))
    pixels = small.load()
    aspect = width / height
    for j in range(small_h):
        v = j / (small_h - 1)
        for i in range(small_w):
            u = i / (small_w - 1)
            color = lerp(BASE[0], BASE[1], min(1.0, max(0.0, (u * aspect + v) / (aspect + 1))))
            for bx, by, radius, rgb, strength in BLOBS:
                distance = math.hypot((u - bx) * aspect, v - by) / (radius * max(1.0, aspect))
                weight = strength * max(0.0, 1.0 - distance) ** 2
                color = lerp(color, rgb, min(1.0, weight))
            pixels[i, j] = color
    blur = max(width, height) / 60
    return small.resize(size, Image.BICUBIC).filter(ImageFilter.GaussianBlur(blur)).convert("RGBA")


def load_card(path, scale):
    card = Image.open(path).convert("RGBA")
    factor = scale
    if scale == "auto":
        # Snapshots from a Retina screen are already 2x (a 380 pt card is ~760 px wide).
        factor = 2 if card.width < 600 else 1
    factor = int(factor)
    if factor != 1:
        card = card.resize((card.width * factor, card.height * factor), Image.LANCZOS)
    return card


def shadow_for(card, blur, opacity, spread=0):
    """A black silhouette of the card's alpha, softened; returned with `blur * 3` padding on each side."""
    pad = int(blur * 3)
    alpha = card.getchannel("A")
    if spread:
        alpha = alpha.filter(ImageFilter.MaxFilter(spread * 2 + 1))
    canvas = Image.new("L", (card.width + pad * 2, card.height + pad * 2), 0)
    canvas.paste(alpha.point(lambda a: int(a * opacity)), (pad, pad))
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur))
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow.putalpha(canvas)
    return shadow, pad


def composite(background, overlay, x, y):
    """alpha_composite that tolerates overlays hanging off any edge (Pillow rejects negative offsets)."""
    x, y = int(round(x)), int(round(y))
    left, top = max(0, -x), max(0, -y)
    if left >= overlay.width or top >= overlay.height:
        return
    background.alpha_composite(overlay, (x + left, y + top), (left, top))


def place_card(background, card, x, y):
    """Composites `card` at (x, y) with a large ambient shadow and a tighter contact shadow."""
    unit = max(card.width, card.height) / 1000
    for blur, opacity, offset in ((60 * unit, 0.55, 40 * unit), (14 * unit, 0.35, 10 * unit)):
        shadow, pad = shadow_for(card, blur, opacity)
        composite(background, shadow, x - pad, y - pad + offset)
    composite(background, card, x, y)


def compose_single(card, padding=None):
    padding = padding or max(96, int(max(card.width, card.height) * 0.12))
    size = (card.width + padding * 2, card.height + padding * 2)
    background = gradient(size)
    place_card(background, card, padding, int(padding * 0.85))
    return background


def compose_hero(main, details=None):
    padding = max(110, int(main.height * 0.11))
    if details is None:
        return compose_single(main, padding)
    gap = int(padding * 0.55)
    drop = int(padding * 0.45)  # the second card sits a little lower, like two windows on a desk
    width = padding * 2 + main.width + gap + details.width
    height = padding * 2 + max(main.height, details.height + drop)
    background = gradient((width, height))
    top = int(padding * 0.85)
    place_card(background, main, padding, top)
    place_card(background, details, padding + main.width + gap, top + drop)
    return background


def load_font(size, weight):
    for path, index in FONT_CANDIDATES:
        if not os.path.exists(path):
            continue
        try:
            font = ImageFont.truetype(path, size, index=index)
        except OSError:
            continue
        try:
            axes = font.get_variation_axes()
            values = []
            for axis in axes:
                name = axis["name"].decode() if isinstance(axis["name"], bytes) else axis["name"]
                if name == "Weight":
                    values.append(weight)
                elif name == "Optical Size":
                    values.append(min(axis["maximum"], max(axis["minimum"], size)))
                else:
                    values.append(axis["default"])
            font.set_variation_by_axes(values)
        except (OSError, AttributeError):
            pass  # not a variable font
        return font
    try:
        return ImageFont.load_default(size)
    except TypeError:  # Pillow < 10.1
        return ImageFont.load_default()


def wrap(draw, text, font, max_width):
    lines, line = [], ""
    for word in text.split():
        candidate = f"{line} {word}".strip()
        if draw.textlength(candidate, font=font) <= max_width or not line:
            line = candidate
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def compose_social(main):
    width, height = SOCIAL_SIZE
    background = gradient(SOCIAL_SIZE)
    draw = ImageDraw.Draw(background)

    # Card on the right, bleeding off the bottom edge.
    card_width = 470
    card = main.resize((card_width, round(main.height * card_width / main.width)), Image.LANCZOS)
    card_x, card_y = width - card_width - 72, 64
    place_card(background, card, card_x, card_y)

    # Icon, name and tagline on the left, centered vertically as one block.
    left, max_text = 76, card_x - 76 - 56
    blocks = []  # (kind, payload, height, gap after)
    if os.path.exists(ICON):
        icon = Image.open(ICON).convert("RGBA").resize((132, 132), Image.LANCZOS)
        blocks.append(("image", icon, 132, 18))
    title_font, tagline_font, detail_font = load_font(80, 700), load_font(31, 500), load_font(22, 450)
    blocks.append(("text", ("ClaudeDeck", title_font, 255), 80, 30))
    # Break the tagline at the dash when both halves fit; otherwise wrap by width.
    halves = ["Every Claude Code session on your Mac —", "in one floating card."]
    if not all(draw.textlength(h, font=tagline_font) <= max_text for h in halves):
        halves = wrap(draw, " ".join(halves), tagline_font, max_text)
    for i, line in enumerate(halves):
        blocks.append(("text", (line, tagline_font, 230), 42, 18 if i == len(halves) - 1 else 0))
    detail = "Memory & CPU per session · sleep idle ones · resume where they left off"
    for line in wrap(draw, detail, detail_font, max_text):
        blocks.append(("text", (line, detail_font, 175), 32, 0))

    y = (height - sum(h + gap for _, _, h, gap in blocks)) / 2
    for kind, payload, block_height, gap in blocks:
        if kind == "image":
            composite(background, payload, left - 12, y)  # the icon artwork has a transparent margin
        else:
            text, font, alpha = payload
            draw.text((left, y), text, font=font, fill=(255, 255, 255, alpha))
        y += block_height + gap
    return background


def save(image, out_dir, name):
    path = os.path.join(out_dir, name)
    image.convert("RGB").save(path, optimize=True)
    shown = os.path.relpath(path, ROOT) if os.path.abspath(path).startswith(ROOT + os.sep) else path
    print(f"wrote {shown} ({image.width}×{image.height})")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("snapshots", help="directory with main.png, details.png, recent.png, settings.png")
    parser.add_argument("--out", default=os.path.join(ROOT, "docs", "images"), help="output directory (default: docs/images)")
    parser.add_argument("--scale", choices=["auto", "1", "2"], default="auto",
                        help="upscale snapshots; auto doubles 1x snapshots (narrower than 600 px)")
    args = parser.parse_args()

    def card(name):
        path = os.path.join(args.snapshots, name)
        if os.path.exists(path):
            return load_card(path, args.scale)
        print(f"skipping {name}: not found in {args.snapshots}")
        return None

    if not os.path.isdir(args.snapshots):
        sys.exit(f"not a directory: {args.snapshots}")
    os.makedirs(args.out, exist_ok=True)

    main_card, details, recent, settings = (card(n) for n in ("main.png", "details.png", "recent.png", "settings.png"))
    if main_card is not None:
        save(compose_hero(main_card, details), args.out, "hero.png")
        save(compose_social(main_card), args.out, "social-preview.png")
    for name, image in (("details.png", details), ("recent.png", recent), ("settings.png", settings)):
        if image is not None:
            save(compose_single(image), args.out, name)


if __name__ == "__main__":
    main()
