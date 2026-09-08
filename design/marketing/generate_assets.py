#!/usr/bin/env python3
"""Build the rounded logo and dual-appearance README product hero."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
ICON_SOURCE = ROOT / "native/trial/Resources/PortToolsIcon.png"


def rounded_image(image: Image.Image, radius: int) -> Image.Image:
    result = Image.new("RGBA", image.size)
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, image.width - 1, image.height - 1),
        radius=radius,
        fill=255,
    )
    result.paste(image.convert("RGBA"), (0, 0), mask)
    return result


def build_logo() -> None:
    source = Image.open(ICON_SOURCE).convert("RGB").resize(
        (512, 512),
        Image.Resampling.LANCZOS,
    )
    rounded_image(source, 112).save(
        OUT / "port-tools-icon-rounded.png",
        optimize=True,
    )


def paste_panel(canvas: Image.Image, source_path: Path, x: int) -> None:
    source = Image.open(source_path).convert("RGB").crop((0, 0, 764, 1125))
    panel_height = 850
    panel_width = round(source.width * panel_height / source.height)
    panel = source.resize((panel_width, panel_height), Image.Resampling.LANCZOS)
    panel = rounded_image(panel, 28)
    y = 25

    shadow = Image.new("RGBA", canvas.size)
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (x - 12, y + 12, x + panel_width + 12, y + panel_height + 24),
        radius=38,
        fill=(0, 0, 0, 105),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    canvas.alpha_composite(shadow)
    canvas.paste(panel, (x, y), panel)
    ImageDraw.Draw(canvas).rounded_rectangle(
        (x, y, x + panel_width, y + panel_height),
        radius=28,
        outline=(132, 146, 168, 90),
        width=2,
    )


def build_hero() -> None:
    width, height = 1600, 900
    canvas = Image.new("RGBA", (width, height), "#eef1f6")
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((800, 0, width, height), fill="#0b0f17")
    draw.line((799, 0, 799, height), fill="#273143", width=2)

    paste_panel(canvas, OUT / "interface-light.png", 176)
    paste_panel(canvas, OUT / "interface-dark.png", 890)
    canvas.convert("RGB").save(OUT / "github-hero.png", optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    build_logo()
    build_hero()


if __name__ == "__main__":
    main()
