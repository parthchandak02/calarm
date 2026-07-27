#!/usr/bin/env python3
"""Process CALarm voxel logo into App Store–ready icon set."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def load_rgb(path: Path) -> Image.Image:
    return Image.open(path).convert("RGB")


def remove_corner_watermark(img: Image.Image, corner: int = 140) -> Image.Image:
    """Paint AI sparkle / watermark marks in the bottom-right corner to background black."""
    pixels = img.load()
    w, h = img.size
    cx, cy = w - 1, h - 1
    for y in range(h - corner, h):
        for x in range(w - corner, w):
            r, g, b = pixels[x, y]
            # Distance from bottom-right — watermark sits in the outer corner only.
            dist = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if dist > corner * 0.55:
                pixels[x, y] = (0, 0, 0)
                continue
            if max(r, g, b) > 55 and dist > corner * 0.35:
                pixels[x, y] = (0, 0, 0)
    return img


def normalize_background(img: Image.Image, bg_cutoff: int = 18) -> Image.Image:
    """Flatten near-black JPEG noise to pure #000000."""
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b = pixels[x, y]
            if r <= bg_cutoff and g <= bg_cutoff and b <= bg_cutoff:
                pixels[x, y] = (0, 0, 0)
    return img


def foreground_mask(img: Image.Image, bg_cutoff: int = 18) -> list[list[bool]]:
    w, h = img.size
    px = img.load()
    return [
        [not (px[x, y][0] <= bg_cutoff and px[x, y][1] <= bg_cutoff and px[x, y][2] <= bg_cutoff) for x in range(w)]
        for y in range(h)
    ]


def compose_on_background(img: Image.Image, mask: list[list[bool]], bg: tuple[int, int, int]) -> Image.Image:
    w, h = img.size
    out = Image.new("RGB", (w, h), bg)
    src = img.load()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if mask[y][x]:
                dst[x, y] = src[x, y]
    return out


def invert_foreground(img: Image.Image, mask: list[list[bool]], bg: tuple[int, int, int]) -> Image.Image:
    w, h = img.size
    out = Image.new("RGB", (w, h), bg)
    src = img.load()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if mask[y][x]:
                r, g, b = src[x, y]
                dst[x, y] = (255 - r, 255 - g, 255 - b)
    return out


def tinted_variant(img: Image.Image, mask: list[list[bool]]) -> Image.Image:
    """High-contrast monochrome for iOS tinted appearance slot."""
    w, h = img.size
    out = Image.new("RGB", (w, h), (0, 0, 0))
    src = img.load()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if not mask[y][x]:
                continue
            r, g, b = src[x, y]
            lum = int(0.299 * r + 0.587 * g + 0.114 * b)
            v = 255 if lum > 90 else max(40, lum + 40)
            dst[x, y] = (v, v, v)
    return out


def ensure_opaque(img: Image.Image) -> Image.Image:
    if img.mode == "RGBA":
        bg = Image.new("RGB", img.size, (0, 0, 0))
        bg.paste(img, mask=img.split()[3])
        return bg
    return img.convert("RGB")


def write_icons(source: Path, out_dir: Path) -> None:
    base = normalize_background(remove_corner_watermark(load_rgb(source)))
    mask = foreground_mask(base)

    dark = ensure_opaque(compose_on_background(base, mask, (0, 0, 0)))
    light = ensure_opaque(invert_foreground(base, mask, (255, 255, 255)))
    tinted = ensure_opaque(tinted_variant(base, mask))

    out_dir.mkdir(parents=True, exist_ok=True)
    dark.save(out_dir / "calarm.png", format="PNG", optimize=True)
    light.save(out_dir / "calarm-light.png", format="PNG", optimize=True)
    tinted.save(out_dir / "calarm-tinted.png", format="PNG", optimize=True)

    contents = """{
  "images" : [
    {
      "filename" : "calarm.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "calarm.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "calarm-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
    (out_dir / "Contents.json").write_text(contents)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        default="/Users/parthchandak/Downloads/calarm-final.jpeg",
        help="Source logo image",
    )
    parser.add_argument(
        "--out",
        default=str(Path(__file__).resolve().parents[1] / "Calarm/Assets.xcassets/AppIcon.appiconset"),
    )
    args = parser.parse_args()
    write_icons(Path(args.source), Path(args.out))
    print(f"Wrote icons to {args.out}")


if __name__ == "__main__":
    main()
