#!/usr/bin/env python3
"""Generate the iOS colour sets from the web app's theme tokens.

The web theme (north-web-app/web/assets/css/input.css) defines every colour in
OKLCH under :root (light) and .dark. This script converts each token to
Display P3 and writes one colour set per token, with a light and a dark
appearance, into NorthKit's Theme.xcassets. Re-run it whenever the web theme
changes; the web file stays the single source of truth.

    python3 scripts/sync-theme.py [path/to/input.css]
"""

import json
import math
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CSS = ROOT.parent.parent / "north-web-app/web/assets/css/input.css"
OUT = ROOT / "NorthKit/Sources/NorthKit/Resources/Theme.xcassets"
# The app's global tint (buttons, links, toggles) follows the web's signal colour.
ACCENT = ROOT / "khepri/Assets.xcassets/AccentColor.colorset/Contents.json"
ACCENT_TOKEN = "north-signal"

# CSS token -> colour set name. Only tokens the native app uses; templUI's
# sidebar and popover variants have no iOS counterpart.
TOKENS = {
    "background": "Background",
    "foreground": "Foreground",
    "card": "Card",
    "card-foreground": "CardForeground",
    "primary": "Primary",
    "primary-foreground": "PrimaryForeground",
    "secondary": "Secondary",
    "secondary-foreground": "SecondaryForeground",
    "muted": "Muted",
    "muted-foreground": "MutedForeground",
    "destructive": "Destructive",
    "border": "Border",
    "ring": "Ring",
    "north-signal": "Signal",
    "north-agent": "Agent",
    "north-ember": "Ember",
    "north-surface": "Surface",
    "north-hairline": "Hairline",
    "north-sport-run": "SportRun",
    "north-sport-ride": "SportRide",
    "north-sport-swim": "SportSwim",
    "north-sport-walk": "SportWalk",
    "north-sport-strength": "SportStrength",
    "north-sport-other": "SportOther",
}

OKLCH = re.compile(r"oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*(?:/\s*([\d.]+)%)?\s*\)")
VAR = re.compile(r"var\(--([\w-]+)\)")


def block(css: str, selector: str) -> dict[str, str]:
    match = re.search(re.escape(selector) + r"\s*\{(.*?)\n\}", css, re.S)
    if not match:
        sys.exit(f"selector {selector!r} not found")
    return dict(re.findall(r"--([\w-]+):\s*([^;]+);", match.group(1)))


def resolve(name: str, tokens: dict[str, str]) -> str:
    value = tokens[name]
    ref = VAR.fullmatch(value.strip())
    return resolve(ref.group(1), tokens) if ref else value


def oklch_to_p3(value: str) -> tuple[float, float, float, float]:
    m = OKLCH.fullmatch(value.strip())
    if not m:
        sys.exit(f"not an oklch() value: {value}")
    l, c, h = float(m.group(1)), float(m.group(2)), math.radians(float(m.group(3)))
    alpha = float(m.group(4)) / 100 if m.group(4) else 1.0
    a, b = c * math.cos(h), c * math.sin(h)
    # OKLab -> LMS -> linear XYZ-D65 (Björn Ottosson's matrices)
    l_ = (l + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (l - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (l - 0.0894841775 * a - 1.2914855480 * b) ** 3
    x = 1.2270138511 * l_ - 0.5577999807 * m_ + 0.2812561490 * s_
    y = -0.0405801784 * l_ + 1.1122568696 * m_ - 0.0716766787 * s_
    z = -0.0763812845 * l_ - 0.4214819784 * m_ + 1.5861632204 * s_
    # XYZ-D65 -> linear Display P3
    r = 2.4934969119 * x - 0.9313836179 * y - 0.4027107845 * z
    g = -0.8294889696 * x + 1.7626640603 * y + 0.0236246858 * z
    bl = 0.0358458302 * x - 0.0761723893 * y + 0.9568845240 * z

    def encode(v: float) -> float:
        v = min(max(v, 0.0), 1.0)
        return 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055

    return encode(r), encode(g), encode(bl), alpha


def component(rgba) -> dict:
    r, g, b, a = rgba
    return {
        "color-space": "display-p3",
        "components": {"red": f"{r:.4f}", "green": f"{g:.4f}", "blue": f"{b:.4f}", "alpha": f"{a:.3f}"},
    }


def main() -> None:
    css_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSS
    css = css_path.read_text()
    light, dark = block(css, ":root"), block(css, ".dark")

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    (OUT / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))

    for token, name in TOKENS.items():
        colour_set = OUT / f"{name}.colorset"
        colour_set.mkdir()
        (colour_set / "Contents.json").write_text(json.dumps(colour_contents(token, light, dark), indent=2))

    ACCENT.write_text(json.dumps(colour_contents(ACCENT_TOKEN, light, dark), indent=2))
    print(f"wrote {len(TOKENS)} colour sets from {css_path} to {OUT.relative_to(ROOT)}, accent = {ACCENT_TOKEN}")


def colour_contents(token: str, light: dict[str, str], dark: dict[str, str]) -> dict:
    return {
        "colors": [
            {"idiom": "universal", "color": component(oklch_to_p3(resolve(token, light)))},
            {
                "idiom": "universal",
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "color": component(oklch_to_p3(resolve(token, dark))),
            },
        ],
        "info": {"author": "xcode", "version": 1},
    }


if __name__ == "__main__":
    main()
