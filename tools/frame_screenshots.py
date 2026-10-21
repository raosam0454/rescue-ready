"""Turns raw Simulator screenshots into App Store marketing screenshots.

Usage:
    pip3 install pillow
    python3 tools/frame_screenshots.py raw/ marketing/

Put raw screenshots in `raw/` named 1.png, 2.png, ... (taken on the iPhone 16 Pro Max
Simulator with Cmd+S). Each output is 1320 x 2868 px: a branded background, a short
headline, and the screenshot inside a rounded device frame.

Edit HEADLINES below to change the text. Add "dark" to use the dark background.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

WIDTH, HEIGHT = 1320, 2868

HEADLINES = {
    "1": ("Every batch, on the clock", "See what needs checking first", "light"),
    "2": ("Log a pickup in seconds", "Food, weight and allergens", "light"),
    "3": ("Unsafe food can't slip through", "Temperature and time checks", "light"),
    "4": ("Hand over with confidence", "A record for every delivery", "light"),
    "5": ("See the meals you've saved", "Your group's impact at a glance", "dark"),
}

THEMES = {
    "light": {"top": (232, 245, 237), "bottom": (198, 230, 211), "title": (20, 70, 45), "subtitle": (50, 100, 72)},
    "dark": {"top": (18, 38, 28), "bottom": (6, 16, 11), "title": (236, 248, 241), "subtitle": (160, 205, 180)},
}

FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def load_font(size):
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)


def gradient(theme):
    image = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        colour = tuple(int(theme["top"][i] + (theme["bottom"][i] - theme["top"][i]) * t) for i in range(3))
        draw.line([(0, y), (WIDTH, y)], fill=colour)
    return image


def centred_text(draw, text, y, font, fill):
    left, _, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(((WIDTH - (right - left)) / 2, y), text, font=font, fill=fill)
    return y + bottom


def frame(raw_path, out_path, title, subtitle, mode):
    theme = THEMES[mode]
    canvas = gradient(theme)
    draw = ImageDraw.Draw(canvas)

    y = centred_text(draw, title, 170, load_font(84), theme["title"])
    centred_text(draw, subtitle, y + 30, load_font(52), theme["subtitle"])

    # Screenshot scaled to fit below the text, inside a dark rounded bezel.
    shot = Image.open(raw_path).convert("RGB")
    screen_height = 2240
    screen_width = int(shot.width * screen_height / shot.height)
    shot = shot.resize((screen_width, screen_height), Image.LANCZOS)

    bezel = 22
    radius = 110
    left = (WIDTH - screen_width) // 2
    top = HEIGHT - screen_height - 120

    shadow = Image.new("L", (WIDTH, HEIGHT), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        [left - bezel, top - bezel + 20, left + screen_width + bezel, top + screen_height + bezel + 20],
        radius=radius + bezel, fill=120)
    canvas.paste((0, 0, 0), mask=shadow.filter(ImageFilter.GaussianBlur(40)))

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle([left - bezel, top - bezel, left + screen_width + bezel, top + screen_height + bezel],
                           radius=radius + bezel, fill=(28, 28, 30))

    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, screen_width, screen_height], radius=radius, fill=255)
    canvas.paste(shot, (left, top), mask)

    canvas.save(out_path, "PNG")
    print(f"Saved {out_path} ({WIDTH}x{HEIGHT})")


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    raw_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    for raw in sorted(raw_dir.glob("*.png")):
        title, subtitle, mode = HEADLINES.get(raw.stem, ("Rescue food safely", "", "light"))
        frame(raw, out_dir / f"appstore-{raw.stem}.png", title, subtitle, mode)


if __name__ == "__main__":
    main()
