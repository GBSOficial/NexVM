#!/usr/bin/env python3
"""Builds the macOS AppIcon.appiconset images from assets/brand/source/NexVM_Icon_1024.png.

The brand-kit master is a full-bleed 1024 px RGB image (itself upscaled from ~257 px).
macOS expects ~100 px of transparent margin and rounded corners baked into the artwork,
so this masks the master to a 824 px squircle-like rounded rect on a transparent 1024 canvas.
Requires Pillow (dev-time only; the generated PNGs are committed).
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

root = Path(__file__).resolve().parent.parent
src = Image.open(root / "assets/brand/source/NexVM_Icon_1024.png").convert("RGBA")
out_dir = root / "Sources/NexVMApp/Resources/Assets.xcassets/AppIcon.appiconset"

S = 1024 * 4  # supersample for clean edges
body = 824 * 4
margin = (S - body) // 2
radius = int(body * 0.2237)

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([margin, margin, margin + body, margin + body], radius, fill=255)

art = src.crop((16, 16, 1008, 1008)).resize((body, body), Image.LANCZOS)  # drop the master's dark corner pixels
canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
shadow_mask = mask.filter(ImageFilter.GaussianBlur(S * 0.012))
shadow.paste((0, 0, 0, 90), (0, int(S * 0.012)), shadow_mask)
canvas = Image.alpha_composite(canvas, shadow)

layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
layer.paste(art, (margin, margin))
layer.putalpha(mask)
canvas = Image.alpha_composite(canvas, layer)
master = canvas.resize((1024, 1024), Image.LANCZOS)

sizes = {"16x16": 16, "32x32": 32, "128x128": 128, "256x256": 256, "512x512": 512}
for name, base in sizes.items():
    for scale in (1, 2):
        px = base * scale
        master.resize((px, px), Image.LANCZOS).save(out_dir / f"icon_{name}@{scale}x.png")
print("wrote", out_dir)
