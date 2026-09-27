#!/usr/bin/env python3
"""Render the Tama Melody app icons from docs/brand/tama-melody.svg.

Why a script instead of a design tool: every platform in this repo keeps its own
icon set at its own sizes, and the master artwork is a hand-written SVG. One
command regenerates all of them consistently.

    python3 docs/brand/generate_icons.py

Deps: cairosvg (SVG -> PNG) and Pillow (maskable safe-zone compositing).
    pip install cairosvg pillow

Three variants are derived from the master:
  * squircle  — the SVG as authored, rounded corners + transparent margin. Used
                where the OS applies its own mask or the rounding is the design
                (Android mipmap, web icons, macOS, Windows, favicon).
  * full-bleed — background extended to every pixel. Required for iOS, whose
                icons must be opaque (Xcode rejects alpha in AppIcon sets).
  * maskable  — full-bleed with the artwork scaled into the central 66% circle
                the Android/web manifest maskers cut out.
"""

import io
import subprocess
import sys
from pathlib import Path

import cairosvg
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
APP = REPO / "app"
MASTER = Path(__file__).resolve().parent / "tama-melody.svg"
BG = (0x7D, 0xD3, 0xFC, 255)  # tama blue, matching the SVG background rect.


def render(svg_text: str, size: int) -> Image.Image:
    png = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def full_bleed(svg_text: str, size: int) -> Image.Image:
    """Drop the squircle rounding, then backfill the corners with tama blue."""
    img = render(svg_text.replace('rx="120"', 'rx="0"'), size)
    base = Image.new("RGBA", img.size, BG)
    base.alpha_composite(img)
    return base


def maskable(svg_text: str, size: int) -> Image.Image:
    """Scale artwork into the central 80% so maskers never clip the pet."""
    inner = render(svg_text, int(size * 0.8))
    base = Image.new("RGBA", (size, size), BG)
    offset = (size - inner.width) // 2
    base.alpha_composite(inner, (offset, offset))
    return base


def save(img: Image.Image, path: Path, *, opaque: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    out = img.convert("RGB") if opaque else img
    out.save(path)
    try:
        label = path.relative_to(REPO)
    except ValueError:
        label = path
    print(f"  {label}  {img.width}x{img.height}")


def main() -> int:
    svg = MASTER.read_text()

    def squircle(px: int) -> Image.Image:
        return render(svg, px)

    print("android (mipmap ic_launcher):")
    for density, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        save(squircle(px), APP / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png")

    print("ios (opaque, no alpha):")
    ios = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    # Contents.json lists each filename once per idiom/scale pair; ipad 2x and
    # iphone 2x legitimately share a file, so dedupe on (name, pixels).
    wanted = {
        (f"Icon-App-{logical}x{logical}@{scale}x.png", round(logical * scale))
        for logical, scale in [
            (20, 1), (20, 2), (20, 3),
            (29, 1), (29, 2), (29, 3),
            (40, 1), (40, 2), (40, 3),
            (60, 2), (60, 3),
            (76, 1), (76, 2), (83.5, 2),
        ]
    } | {("Icon-App-1024x1024@1x.png", 1024)}
    for name, px in sorted(wanted, key=lambda w: (w[1], w[0])):
        save(full_bleed(svg, px), ios / name, opaque=True)

    print("macos:")
    mac = APP / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for px in (16, 32, 64, 128, 256, 512, 1024):
        save(squircle(px), mac / f"app_icon_{px}.png")

    print("web:")
    save(squircle(16), APP / "web/favicon.png")
    for px in (192, 512):
        save(squircle(px), APP / f"web/icons/Icon-{px}.png")
        save(maskable(svg, px), APP / f"web/icons/Icon-maskable-{px}.png")

    print("windows (multi-size .ico):")
    tmp = Path("/tmp/_tama_win_icon.png")
    save(squircle(256), tmp)
    ico = APP / "windows/runner/resources/app_icon.ico"
    ico.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["convert", str(tmp), "-define", "icon:auto-resize=16,32,48,256", str(ico)],
        check=True,
    )
    tmp.unlink()
    print(f"  {ico.relative_to(REPO)}")

    print("flutter-native splash (drawable):")
    save(squircle(192), APP / "android/app/src/main/res/drawable-nodpi/launch_image.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
