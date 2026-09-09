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
    canvas = Image.new("RGBA", (width, height), "#252a34")

    paste_panel(canvas, OUT / "interface-light.png", 176)
    paste_panel(canvas, OUT / "interface-dark.png", 890)
    canvas.convert("RGB").save(OUT / "github-hero-unified.png", optimize=True)


def build_dmg_background() -> None:
    """Build a Retina Finder background for the 600 x 400 point DMG window."""
    width, height = 1200, 800
    top = (248, 250, 254)
    bottom = (236, 242, 250)
    canvas = Image.new("RGB", (width, height))
    pixels = canvas.load()
    for y in range(height):
        mix = y / (height - 1)
        color = tuple(round(a + (b - a) * mix) for a, b in zip(top, bottom))
        for x in range(width):
            pixels[x, y] = color

    glow = Image.new("RGBA", canvas.size)
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((95, 140, 585, 630), fill=(0, 168, 255, 34))
    glow_draw.ellipse((650, 135, 1140, 625), fill=(35, 214, 107, 28))
    glow = glow.filter(ImageFilter.GaussianBlur(95))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), glow)

    draw = ImageDraw.Draw(canvas)
    title_font = "/System/Library/Fonts/SFNS.ttf"
    try:
        from PIL import ImageFont

        title = ImageFont.truetype(title_font, 44)
        subtitle = ImageFont.truetype(title_font, 25)
    except OSError:
        title = None
        subtitle = None

    heading = "Install Port Tools"
    guidance = "Drag Port Tools to Applications"
    title_box = draw.textbbox((0, 0), heading, font=title)
    subtitle_box = draw.textbbox((0, 0), guidance, font=subtitle)
    draw.text(
        ((width - (title_box[2] - title_box[0])) / 2, 64),
        heading,
        font=title,
        fill=(20, 27, 42, 245),
    )
    draw.text(
        ((width - (subtitle_box[2] - subtitle_box[0])) / 2, 124),
        guidance,
        font=subtitle,
        fill=(91, 102, 124, 235),
    )
    draw.rounded_rectangle(
        (125, 280, 555, 650),
        radius=44,
        fill=(255, 255, 255, 245),
        outline=(21, 168, 235, 90),
        width=2,
    )
    draw.rounded_rectangle(
        (645, 280, 1075, 650),
        radius=44,
        fill=(255, 255, 255, 245),
        outline=(34, 197, 94, 85),
        width=2,
    )
    canvas.convert("RGB").save(
        OUT / "dmg-background@2x.png",
        optimize=True,
        dpi=(144, 144),
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    build_logo()
    build_hero()
    build_dmg_background()


if __name__ == "__main__":
    main()
