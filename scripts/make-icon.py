#!/usr/bin/env python3
"""Generate the mewmew app icon.

A flat white cat head on the brand orange. Kept deliberately simple: the icon
has to stay readable at 60x60 on a home screen, so it carries silhouette only —
no gradients (house style), no thin strokes, no text.

Usage: python3 scripts/make-icon.py
Writes ios/Mewmew/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""

import pathlib

from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # supersample factor for smooth edges
ORANGE = (249, 115, 22, 255)  # #F97316, Theme.accent
WHITE = (255, 255, 255, 255)

OUT = (
    pathlib.Path(__file__).resolve().parent.parent
    / "ios/Mewmew/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
)


def draw_cat(d: ImageDraw.ImageDraw, s: int) -> None:
    """Draw a centered white cat head on a canvas of edge length s."""
    cx = s / 2
    # Head sits slightly low so the ears have room and the whole mark reads
    # centered once the ears are included.
    head_cy = s * 0.58
    head_rx = s * 0.30
    head_ry = s * 0.27

    # Ears: triangles whose base sits well inside the head ellipse, so the two
    # shapes fuse into one silhouette instead of floating apart.
    ear_dx = head_rx * 0.60
    ear_half_w = head_rx * 0.28
    ear_base_y = head_cy - head_ry * 0.30
    ear_apex_y = head_cy - head_ry - s * 0.13
    for sign in (-1, 1):
        base_cx = cx + sign * ear_dx
        d.polygon(
            [
                (base_cx - ear_half_w, ear_base_y),
                (base_cx + ear_half_w, ear_base_y),
                (base_cx + sign * ear_half_w * 0.55, ear_apex_y),
            ],
            fill=WHITE,
        )

    d.ellipse(
        [cx - head_rx, head_cy - head_ry, cx + head_rx, head_cy + head_ry],
        fill=WHITE,
    )

    # Eyes: closed, content arcs — the cat is a calm keeper of things, not a
    # startled one. Arcs read better than dots at small sizes.
    eye_dx = head_rx * 0.42
    eye_ry = head_ry * 0.20
    eye_rx = head_rx * 0.24
    eye_cy = head_cy - head_ry * 0.05
    lw = max(2, int(s * 0.018))
    for sign in (-1, 1):
        ex = cx + sign * eye_dx
        d.arc(
            [ex - eye_rx, eye_cy - eye_ry, ex + eye_rx, eye_cy + eye_ry],
            start=200,
            end=340,
            fill=ORANGE,
            width=lw,
        )

    # Nose: a small triangle, the only asymmetric-free detail that keeps the
    # face from reading as a blank blob.
    nose_w = head_rx * 0.13
    nose_y = head_cy + head_ry * 0.26
    d.polygon(
        [
            (cx - nose_w, nose_y - nose_w * 0.7),
            (cx + nose_w, nose_y - nose_w * 0.7),
            (cx, nose_y + nose_w * 0.8),
        ],
        fill=ORANGE,
    )


def main() -> None:
    s = SIZE * SS
    img = Image.new("RGBA", (s, s), ORANGE)
    draw_cat(ImageDraw.Draw(img), s)
    img = img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, "PNG")
    print(f"wrote {OUT} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
