#!/usr/bin/env python3
"""Composes the App Store screenshots from raw simulator captures.

The layout follows the aso-appstore-screenshots skill's compose.py (brand
background, two-part headline, device frame bleeding off the bottom edge,
bottom fade), with two differences: the drop shadow is drawn beneath the
screen rather than over it, which in compose.py greys the screenshot out, and
headline lines are set by hand so no word is left alone on a line. Headlines
use the app's own Geist at its Black weight.

  scripts/compose-store-screenshots.py <raw-dir>

<raw-dir> holds iphone-<screen>.png and ipad-<screen>.png from
ScreenshotUITests. Writes fastlane/screenshots/en-US/, which deliver sorts by
pixel size: 1320x2868 is the 6.9" iPhone slot, 2064x2752 the 13" iPad slot.
Needs Pillow.
"""
import os
import sys
from dataclasses import dataclass

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEIST = os.path.join(ROOT, "NorthKit/Sources/NorthKit/Resources/Fonts/Geist-Variable.ttf")
PHONE_FRAME = os.path.expanduser("~/.claude/skills/aso-appstore-screenshots/assets/device_frame.png")
BRAND = (0x64, 0x4D, 0xC6)  # NorthColor.agent, light

# Swipe order: the first screenshot carries the download decision.
SHOTS = [
    ("coach", "COACH", ["THAT REMEMBERS YOU"], ["THAT", "REMEMBERS YOU"]),
    ("training-day", "TRAIN", ["WITH A PLAN", "BUILT FOR YOU"], ["WITH A PLAN", "BUILT FOR YOU"]),
    ("today", "KEEP", ["YOUR STREAK GOING"], ["YOUR STREAK", "GOING"]),
    ("progress", "SEE", ["HOW YOUR LIFE IS GOING"], ["HOW YOUR LIFE", "IS GOING"]),
    ("goal-detail", "REACH", ["YOUR GOALS STEP BY STEP"], ["YOUR GOALS", "STEP BY STEP"]),
]


@dataclass
class Layout:
    width: int
    height: int
    device_w: int
    bezel: int
    screen_radius: int
    device_y: int
    text_top: int
    verb_size: int
    desc_size: int
    frame: Image.Image


def font(size):
    f = ImageFont.truetype(GEIST, size)
    f.set_variation_by_axes([900])
    return f


def ipad_frame(width, height, bezel, radius):
    """A plain dark bezel with a transparent screen: the phone template's look
    without a Dynamic Island."""
    frame = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)
    draw.rounded_rectangle([0, 0, width - 1, height + radius], radius=radius + bezel, fill=(28, 28, 30, 255))
    draw.rounded_rectangle([bezel, bezel, width - 1 - bezel, height + radius], radius=radius, fill=(0, 0, 0, 0))
    return frame


PHONE = Layout(1290, 2796, 1030, 15, 62, 720, 150, 250, 116, Image.open(PHONE_FRAME).convert("RGBA"))
PAD = Layout(2064, 2752, 1640, 28, 44, 700, 130, 250, 124, ipad_frame(1640, 2152, 28, 44))


def compose(layout, verb, lines, shot_path, out_path):
    L = layout
    canvas = Image.new("RGBA", (L.width, L.height), (*BRAND, 255))
    draw = ImageDraw.Draw(canvas)

    # Headline: the verb, then the descriptor lines, centred.
    y = L.text_top
    for text, f, gap in [(verb, font(L.verb_size), 18)] + [(line, font(L.desc_size), 16) for line in lines]:
        top, bottom = draw.textbbox((0, 0), text, font=f)[1::2]
        draw.text((L.width // 2, y - top), text, fill="white", font=f, anchor="mt")
        y += bottom - top + gap

    device_x = (L.width - L.device_w) // 2
    screen_x, screen_y = device_x + L.bezel, L.device_y + L.bezel
    screen_w = L.device_w - 2 * L.bezel
    screen_box = [screen_x, screen_y, screen_x + screen_w, L.height + 500]

    # Shadow first, so it falls on the background and not on the screen.
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [device_x + 20, L.device_y + 30, device_x + L.device_w - 20, L.height + 200], radius=77, fill=(0, 0, 0, 140))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(50)))

    shot = Image.open(shot_path).convert("RGBA")
    shot = shot.resize((screen_w, round(shot.height * screen_w / shot.width)), Image.LANCZOS)
    screen = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(screen).rounded_rectangle(screen_box, radius=L.screen_radius, fill=(0, 0, 0, 255))
    screen.paste(shot, (screen_x, screen_y))
    mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(screen_box, radius=L.screen_radius, fill=255)
    screen.putalpha(mask)
    canvas = Image.alpha_composite(canvas, screen)

    frame = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    frame.paste(L.frame, (device_x, L.device_y))
    canvas = Image.alpha_composite(canvas, frame)

    # The device dissolves into the background at the bottom edge.
    fade_h = 320
    fade = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    fd = ImageDraw.Draw(fade)
    for row in range(fade_h):
        fd.line([(0, L.height - fade_h + row), (L.width, L.height - fade_h + row)],
                fill=(*BRAND, int(255 * (row / fade_h) ** 1.5)))
    canvas = Image.alpha_composite(canvas, fade)
    canvas.convert("RGB").save(out_path, "PNG")


def fit(path, width, height):
    """Scale to the target height and trim the sides equally: the 6.9" slot
    is a hair narrower than the 6.7" canvas the phone frame was drawn for."""
    im = Image.open(path)
    scaled = im.resize((round(im.width * height / im.height), height), Image.LANCZOS)
    left = (scaled.width - width) // 2
    scaled.crop((left, 0, left + width, height)).save(path)


def main():
    raw = sys.argv[1]
    out = os.path.join(ROOT, "fastlane/screenshots/en-US")
    os.makedirs(out, exist_ok=True)
    for i, (screen, verb, pad_lines, phone_lines) in enumerate(SHOTS, 1):
        phone = os.path.join(out, f"{i}_iphone69_{screen}.png")
        compose(PHONE, verb, phone_lines, os.path.join(raw, f"iphone-{screen}.png"), phone)
        fit(phone, 1320, 2868)
        compose(PAD, verb, pad_lines, os.path.join(raw, f"ipad-{screen}.png"),
                os.path.join(out, f"{i}_ipad13_{screen}.png"))
        print(f"{i} {verb}")


if __name__ == "__main__":
    main()
