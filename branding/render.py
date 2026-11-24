"""Renders branding/*.svg to every icon the project needs.

Usage (from the project root):  python branding/render.py
Requires: Google Chrome (headless SVG rendering) and Pillow.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "branding"
CHROME = shutil.which("chrome") or r"C:\Program Files\Google\Chrome\Application\chrome.exe"


def render(svg: Path, size: int) -> Image.Image:
    """SVG → transparent RGBA image of size×size using headless Chrome."""
    with tempfile.TemporaryDirectory() as tmp:
        html = Path(tmp) / "page.html"
        html.write_text(
            f"<html><body style='margin:0;background:transparent'>"
            f"<img src='{svg.as_uri()}' style='width:{size}px;height:{size}px;display:block'>"
            f"</body></html>",
            encoding="utf-8",
        )
        out = Path(tmp) / "shot.png"
        subprocess.run(
            [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
             "--default-background-color=00000000", f"--window-size={size},{size}",
             f"--screenshot={out}", html.as_uri()],
            check=True, capture_output=True,
        )
        return Image.open(out).convert("RGBA").crop((0, 0, size, size))


def save(img: Image.Image, path: Path, size: int, rgb_bg=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    im = img.resize((size, size), Image.LANCZOS)
    if rgb_bg:
        bg = Image.new("RGBA", im.size, rgb_bg)
        bg.alpha_composite(im)
        im = bg.convert("RGB")
    im.save(path, optimize=True)


def main():
    master = render(BRAND / "logo.svg", 1024)
    fg = render(BRAND / "logo-foreground.svg", 1024)
    out = BRAND / "out"
    out.mkdir(exist_ok=True)
    master.save(out / "logo-1024.png")

    # Google Play listing icon (512×512, no transparency needed but allowed).
    save(master, out / "play-store-icon-512.png", 512)

    # Android launcher: legacy + round PNGs, and adaptive foreground layers.
    res = ROOT / "android/app/src/main/res"
    dens = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for d, px in dens.items():
        save(master, res / f"mipmap-{d}/ic_launcher.png", px)
        save(master, res / f"mipmap-{d}/ic_launcher_round.png", px)
        save(fg, res / f"mipmap-{d}/ic_launcher_foreground.png", int(px * 108 / 48))
    save(fg, res / "drawable/launch_logo.png", 288)

    # Flutter in-app logo + web icons.
    save(master, ROOT / "assets/images/logo.png", 512)
    web = ROOT / "web"
    if web.exists():
        save(master, web / "favicon.png", 64)
        for s in (192, 512):
            save(master, web / f"icons/Icon-{s}.png", s)
            save(master, web / f"icons/Icon-maskable-{s}.png", s, rgb_bg=(0, 168, 132, 255))

    # Landing site + Chrome extension.
    pub = ROOT / "landing/public"
    if pub.exists():
        shutil.copy(BRAND / "logo.svg", pub / "logo.svg")
        save(master, pub / "favicon.png", 64)
        save(master, pub / "apple-touch-icon.png", 180)
        save(master, pub / "logo-512.png", 512)
    ext = ROOT / "extension/icons"
    ext.mkdir(parents=True, exist_ok=True)
    for s in (16, 32, 48, 128):
        save(master, ext / f"icon-{s}.png", s)
    print("Icons written.")


if __name__ == "__main__":
    main()
