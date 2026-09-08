#!/usr/bin/env python3
"""Build the README logo and localized hero images from checked-in UI assets."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
ICON_SOURCE = ROOT / "native/trial/Resources/PortToolsIcon.png"
SCREEN_SOURCE = ROOT / "design/native-build25-hierarchy-collapsed.png"

FONT_REGULAR = "/System/Library/Fonts/SFNS.ttf"
FONT_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"
FONT_MONO = "/System/Library/Fonts/SFNSMono.ttf"
FONT_CJK = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(size: int, *, weight: str = "regular", cjk: bool = False):
    if cjk:
        return ImageFont.truetype(FONT_CJK, size=size, index=0)
    if weight == "mono":
        return ImageFont.truetype(FONT_MONO, size=size)
    return ImageFont.truetype(FONT_ROUNDED if weight == "bold" else FONT_REGULAR, size=size)


def fit_text(draw, text, max_width, start_size, *, weight="bold", cjk=False, min_size=20):
    size = start_size
    while size > min_size:
        candidate = font(size, weight=weight, cjk=cjk)
        if draw.textbbox((0, 0), text, font=candidate)[2] <= max_width:
            return candidate
        size -= 1
    return font(min_size, weight=weight, cjk=cjk)


def rounded_image(image: Image.Image, radius: int) -> Image.Image:
    result = Image.new("RGBA", image.size)
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius=radius, fill=255)
    result.paste(image.convert("RGBA"), (0, 0), mask)
    return result


def build_logo() -> None:
    source = Image.open(ICON_SOURCE).convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
    logo = rounded_image(source, 112)
    logo.save(OUT / "port-tools-icon-rounded.png", optimize=True)


def draw_pill(draw, xy, label, *, fill, color, outline=None, icon_color=None, cjk=False):
    x, y, width, height = xy
    draw.rounded_rectangle((x, y, x + width, y + height), radius=height // 2, fill=fill, outline=outline, width=2)
    text_x = x + 22
    if icon_color:
        draw.ellipse((x + 20, y + height // 2 - 6, x + 32, y + height // 2 + 6), fill=icon_color)
        text_x = x + 44
    label_font = fit_text(draw, label, width - (text_x - x) - 18, 24, weight="bold", cjk=cjk, min_size=18)
    bbox = draw.textbbox((0, 0), label, font=label_font)
    draw.text((text_x, y + (height - (bbox[3] - bbox[1])) / 2 - bbox[1]), label, font=label_font, fill=color)


def build_hero(locale: str) -> None:
    cjk = locale == "zh"
    copy = {
        "en": {
            "kicker": "LOCAL DEV, WITH CONTEXT",
            "title": "Know what’s running\non localhost.",
            "subtitle": "Ports → projects · worktrees · apps · service types",
            "raw": "A port table gives you",
            "context": "Port Tools gives you",
            "project": "reply-copilot",
            "details": "repo · worktree · Web app · verified URL",
            "features": ["Native menu bar", "Local only", "Safe stop", "Stable .localhost URLs"],
            "shot": "REAL APP UI",
        },
        "zh": {
            "kicker": "本地开发，不只看端口",
            "title": "看见 localhost\n背后的项目。",
            "subtitle": "端口 → 项目 · worktree · 应用 · 服务类型",
            "raw": "端口工具只能告诉你",
            "context": "Port Tools 进一步识别",
            "project": "reply-copilot",
            "details": "仓库 · worktree · Web 应用 · 可用地址",
            "features": ["原生菜单栏", "仅在本机", "安全停止", "稳定 .localhost 地址"],
            "shot": "真实应用界面",
        },
    }[locale]

    width, height = 1800, 1000
    canvas = Image.new("RGB", (width, height), "#080d19")
    pixels = canvas.load()
    for y in range(height):
        for x in range(width):
            # Restrained navy gradient: enough depth for a product hero, no glow.
            t = x / width
            v = y / height
            pixels[x, y] = (
                int(8 + 4 * t),
                int(13 + 8 * (1 - v)),
                int(25 + 17 * t + 4 * (1 - v)),
            )

    draw = ImageDraw.Draw(canvas)
    # Quiet technical grid and a hard split keep the information dense but legible.
    for x in range(0, width, 80):
        draw.line((x, 0, x, height), fill="#10182a", width=1)
    for y in range(0, height, 80):
        draw.line((0, y, width, y), fill="#10182a", width=1)
    draw.rectangle((1070, 0, width, height), fill="#0b111f")
    draw.line((1069, 70, 1069, 930), fill="#20304a", width=2)

    icon = Image.open(OUT / "port-tools-icon-rounded.png").resize((78, 78), Image.Resampling.LANCZOS)
    canvas.paste(icon, (92, 72), icon)
    draw.text((192, 78), "PORT TOOLS", font=font(37, weight="bold"), fill="#f5f7fb")
    draw_pill(draw, (192, 124, 148, 38), "v1.0 · macOS", fill="#142337", color="#8ea4c2")

    kicker_font = font(24, weight="bold", cjk=cjk)
    draw.text((92, 205), copy["kicker"], font=kicker_font, fill="#22d3ee")
    title_font = font(76 if not cjk else 72, weight="bold", cjk=cjk)
    draw.multiline_text((88, 248), copy["title"], font=title_font, fill="#f7f9fc", spacing=4)
    draw.text((92, 435), copy["subtitle"], font=font(27, cjk=cjk), fill="#9daac0")

    # lsof -> product context comparison.
    card = (88, 505, 1002, 795)
    draw.rounded_rectangle(card, radius=28, fill="#101827", outline="#253550", width=2)
    draw.text((122, 538), copy["raw"], font=font(22, weight="bold", cjk=cjk), fill="#77859d")
    draw.rounded_rectangle((120, 577, 970, 640), radius=14, fill="#080d16")
    draw.text((145, 592), "$ lsof -i :4178", font=font(22, weight="mono"), fill="#8b98aa")
    draw.text((406, 592), "node  84321  TCP *:4178 (LISTEN)", font=font(22, weight="mono"), fill="#5e6b7d")
    draw.line((545, 650, 545, 678), fill="#22d3ee", width=3)
    draw.polygon(((538, 672), (552, 672), (545, 681)), fill="#22d3ee")
    draw.text((122, 690), copy["context"], font=font(22, weight="bold", cjk=cjk), fill="#22d3ee")
    draw.text((470, 681), copy["project"], font=font(34, weight="bold"), fill="#f4f7fb")
    detail_font = fit_text(draw, copy["details"], 475, 22, cjk=cjk, min_size=18)
    draw.text((470, 727), copy["details"], font=detail_font, fill="#39d98a")

    # High-signal capability row.
    pill_y = 835
    pill_widths = [205, 170, 170, 310] if not cjk else [190, 165, 165, 285]
    x = 88
    for label, pill_width in zip(copy["features"], pill_widths):
        draw_pill(
            draw,
            (x, pill_y, pill_width, 58),
            label,
            fill="#111b2b",
            color="#c9d3e2",
            outline="#243650",
            icon_color="#39d98a",
            cjk=cjk,
        )
        x += pill_width + 14

    # Real UI: crop the blank lower half, then frame it like a product shot.
    screenshot = Image.open(SCREEN_SOURCE).convert("RGB").crop((0, 0, 764, 890))
    shot_width = 630
    shot_height = round(screenshot.height * shot_width / screenshot.width)
    screenshot = screenshot.resize((shot_width, shot_height), Image.Resampling.LANCZOS)
    screenshot = rounded_image(screenshot, 34)
    shot_x, shot_y = 1115, 118
    shadow = Image.new("RGBA", canvas.size)
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (shot_x - 12, shot_y + 12, shot_x + shot_width + 12, shot_y + shot_height + 26),
        radius=44,
        fill=(0, 0, 0, 155),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)
    canvas.paste(screenshot, (shot_x, shot_y), screenshot)
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((shot_x, shot_y, shot_x + shot_width, shot_y + shot_height), radius=34, outline="#43536b", width=2)
    draw_pill(draw, (1500, 75, 220, 48), copy["shot"], fill="#102132", color="#39d98a", outline="#24425a", cjk=cjk)

    canvas.convert("RGB").save(OUT / f"github-hero-{locale}.png", optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    build_logo()
    build_hero("en")
    build_hero("zh")


if __name__ == "__main__":
    main()
