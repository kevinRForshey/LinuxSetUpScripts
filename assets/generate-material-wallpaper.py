#!/usr/bin/env python3
"""Generate a deterministic Material You mesh-gradient wallpaper.

Renders a dark abstract wallpaper seeded from the Material 3 baseline
primary color (#6750A4) so that running `matugen image <output>` produces
the exact same tonal palette every time. Used by material-you-gnome-rice.sh.
"""

import argparse
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# Vivid violet/indigo/pink family around the Material 3 baseline seed
# (#6750A4). matugen re-derives its own tonal palette from whichever hue
# dominates the rendered image, so these are intentionally more saturated
# than the muted M3 UI tokens - they need to read as glowing blobs against
# a near-black surface, not as flat UI chrome.
BACKGROUND = "#0c0a12"
BLOB_COLORS = [
    "#8A5CF6",  # vivid violet (seed family)
    "#5B3FD9",  # deep indigo / blue-violet
    "#B48CFF",  # lavender glow
    "#E754A8",  # magenta/pink counter-accent
    "#3C1F5E",  # deep plum
]

RENDER_SIZE = (1920, 1080)
PEAK_ALPHA = 255  # vivid glow at blob core
PATCH_PADDING = 1.7  # blob patch canvas = diameter * this, avoids blur-edge seams
SEED = 6750164  # derived from the palette seed, keeps output reproducible

# Jittered anchor points (fractions of canvas size) so color pools cover the
# whole frame instead of leaving large empty stretches of bare background.
ANCHORS = [
    (0.15, 0.20), (0.55, 0.10), (0.90, 0.30),
    (0.30, 0.55), (0.75, 0.65), (0.10, 0.85), (0.60, 0.90),
]


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def make_blob(canvas_size: tuple[int, int], center: tuple[int, int], radius: int,
              color: tuple[int, int, int], peak_alpha: int) -> Image.Image:
    """A soft radial-gradient blob, as a full-canvas RGBA layer ready to alpha_composite."""
    patch_size = int(radius * 2 * PATCH_PADDING)
    mid = patch_size // 2
    core_radius = int(radius * 0.85)

    mask = Image.new("L", (patch_size, patch_size), 0)
    ImageDraw.Draw(mask).ellipse(
        (mid - core_radius, mid - core_radius, mid + core_radius, mid + core_radius),
        fill=peak_alpha,
    )
    mask = mask.filter(ImageFilter.GaussianBlur(radius * 0.35))

    patch = Image.new("RGBA", (patch_size, patch_size), color + (0,))
    patch.putalpha(mask)

    layer = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    layer.paste(patch, (center[0] - mid, center[1] - mid), patch)
    return layer


def generate(output_path: Path, width: int, height: int) -> None:
    rng = random.Random(SEED)

    render_w, render_h = RENDER_SIZE
    result = Image.new("RGBA", (render_w, render_h), hex_to_rgb(BACKGROUND) + (255,))

    colors = list(BLOB_COLORS)
    rng.shuffle(colors)
    for i, (ax, ay) in enumerate(ANCHORS):
        color = hex_to_rgb(colors[i % len(colors)])
        radius = rng.randint(int(render_w * 0.24), int(render_w * 0.34))
        jitter_x = rng.randint(int(-render_w * 0.05), int(render_w * 0.05))
        jitter_y = rng.randint(int(-render_h * 0.05), int(render_h * 0.05))
        cx = int(render_w * ax) + jitter_x
        cy = int(render_h * ay) + jitter_y

        blob = make_blob((render_w, render_h), (cx, cy), radius, color, PEAK_ALPHA)
        result = Image.alpha_composite(result, blob)

    # Gentle vignette so the far corners settle back toward the surface color.
    vignette = Image.new("L", (render_w, render_h), 0)
    vdraw = ImageDraw.Draw(vignette)
    vdraw.ellipse((-render_w * 0.45, -render_h * 0.45, render_w * 1.45, render_h * 1.45), fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(180))
    dark = Image.new("RGBA", (render_w, render_h), hex_to_rgb(BACKGROUND) + (255,))
    result = Image.composite(result, dark, vignette)

    result = result.convert("RGB").resize((width, height), Image.LANCZOS)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    result.save(output_path, "PNG")
    print(f"Wrote {output_path} ({width}x{height})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Output PNG path")
    parser.add_argument("--width", type=int, default=3840)
    parser.add_argument("--height", type=int, default=2160)
    args = parser.parse_args()
    generate(args.output, args.width, args.height)


if __name__ == "__main__":
    main()
