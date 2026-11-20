#!/usr/bin/env python3
"""Render the macOS visual design boards as SVG.

The boards are deliberately static design references. Production interactions
remain in Flutter and are mapped in design-draft.md.
"""

from html import escape
from base64 import b64encode
from pathlib import Path

OUT = Path(__file__).resolve().parent
W, H = 1360, 900


def t(x, y, value, size=14, color="#292932", weight=400, anchor="start"):
    return (
        f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-family="-apple-system,'
        f'BlinkMacSystemFont,PingFang SC,sans-serif" font-size="{size}" '
        f'font-weight="{weight}" fill="{color}">{escape(str(value))}</text>'
    )


def r(x, y, w, h, fill="url(#glass)", radius=12, stroke="#ffffff", opacity=1):
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" '
        f'fill="{fill}" fill-opacity="{opacity}" stroke="{stroke}" '
        f'stroke-opacity=".75" stroke-width="1"/>'
    )


def line(x1, y1, x2, y2, color="#c9c9d2", opacity=".7", width=1):
    return (
        f'<path d="M{x1} {y1}H{x2}" fill="none" stroke="{color}" '
        f'stroke-opacity="{opacity}" stroke-width="{width}"/>'
    )


def dots(*rows):
    return [(row, col) for row, bits in enumerate(rows) for col, bit in enumerate(bits) if bit == "1"]


GLYPHS = {
    # Keep the study boards on the same 9 × 9 dot language used by the app.
    "play": dots(
        "001000000", "001100000", "001110000", "001111000", "001111100",
        "001111000", "001110000", "001100000", "001000000",
    ),
    "pause": dots(*(["011000110"] * 9)),
    "search": dots(
        "001111000", "010000100", "100000010", "100000010", "100000010",
        "010000100", "001111100", "000000010", "000000001",
    ),
    "refresh": dots(
        "001111000", "010000100", "100000010", "100000111", "100000000",
        "111000001", "010000001", "001000010", "000111100",
    ),
    "plus": dots(
        "000010000", "000010000", "000010000", "000010000", "111111111",
        "000010000", "000010000", "000010000", "000010000",
    ),
    "music": dots(
        "000011110", "000010010", "000010010", "000010010", "000010010",
        "001110110", "011101110", "011001100", "000000000",
    ),
    "settings": dots(
        "000111000", "010101010", "001111100", "111000111", "101010101",
        "111000111", "001111100", "010101010", "000111000",
    ),
    "check": dots(
        "000000001", "000000010", "000000100", "000001000", "100010000",
        "010100000", "001000000", "000000000", "000000000",
    ),
    "folder": dots(
        "111100000", "100110000", "100011111", "100000001", "100000001",
        "100000001", "100000001", "111111111", "000000000",
    ),
    "terminal": dots(
        "000000000", "010000000", "001000000", "000100000", "001000000",
        "010000000", "000011110", "000000000", "000000000",
    ),
    "arrow_up": dots(
        "000010000", "000111000", "001010100", "010010010", "000010000",
        "000010000", "000010000", "000000000", "000000000",
    ),
    "arrow_down": dots(
        "000010000", "000010000", "000010000", "010010010", "001010100",
        "000111000", "000010000", "000000000", "000000000",
    ),
    "history": dots(
        "000000000", "000010000", "000111000", "001101100", "111000111",
        "000000000", "000000000", "000000000", "000000000",
    ),
    "open": dots(
        "110000011", "110000011", "000000000", "000000000", "000000000",
        "000000000", "110000011", "110000011", "000000000",
    ),
    "link": dots(
        "001110000", "010001000", "100010000", "100110000", "011011110",
        "000110001", "000010001", "000100010", "000011100",
    ),
    "close": dots(
        "100000001", "010000010", "001000100", "000101000", "000010000",
        "000101000", "001000100", "010000010", "100000001",
    ),
    "stop": dots(
        "000000000", "011111110", "011111110", "011111110", "011111110",
        "011111110", "011111110", "011111110", "000000000",
    ),
    "trash": dots(
        "000111000", "011111110", "000000000", "010101010", "010101010",
        "010101010", "010101010", "010000010", "001111100",
    ),
    "lock": dots(
        "000010000", "011101110", "010000010", "010010010", "010111010",
        "010010010", "001000100", "000101000", "000010000",
    ),
    "back": dots(
        "000010000", "000100000", "001000000", "111111110", "001000000",
        "000100000", "000010000", "000000000", "000000000",
    ),
    "next": dots(
        "010000010", "011000010", "011100010", "011110010", "011111010",
        "011110010", "011100010", "011000010", "010000010",
    ),
    "previous": dots(
        "010000010", "010000110", "010001110", "010011110", "010111110",
        "010011110", "010001110", "010000110", "010000010",
    ),
    "star": dots(
        "000010000", "000010000", "001111100", "111101111", "011111110",
        "001111100", "001101100", "010000010", "100000001",
    ),
    "document": dots(
        "011111100", "010000100", "010110100", "010110100", "010000100",
        "010110100", "010110100", "010000100", "011111100",
    ),
    "data": dots(
        "011000110", "001001100", "000111000", "000010000", "000111000",
        "001001100", "011000110", "000000000", "000000000",
    ),
    "chat": dots(
        "001111100", "010000010", "100000001", "100000001", "100000001",
        "010000010", "001111100", "000100000", "001000000",
    ),
}


def glyph(x, y, kind="play", size=20, color="#6f695d"):
    scale = size / 32
    return "".join(
        f'<circle cx="{x + (4 + col * 2.7) * scale:.2f}" '
        f'cy="{y + (4 + row * 2.7) * scale:.2f}" '
        f'r="{1.075 * scale:.2f}" fill="{color}" fill-opacity=".94"/>'
        for row, col in GLYPHS.get(kind, GLYPHS["play"])
    )


def button(x, y, w, label, icon=None, primary=False, selected=False, quiet=False, h=42, danger=False):
    edge = "#d88982" if danger else "#efad49" if primary or selected else "#ffffff"
    glow = (
        f'<rect x="{x-6}" y="{y-5}" width="{w+12}" height="{h+10}" rx="17" '
        f'fill="url(#warmGlow)" opacity=".55"/>'
        if primary or selected
        else ""
    )
    fill = "url(#quiet)" if quiet or danger else "url(#glass)"
    icon_size = 24 if primary else 22
    icon_color = "#a54b45" if danger else "#6f695d"
    icon_part = glyph(x + 15, y + (h - icon_size) / 2, icon, size=icon_size, color=icon_color) if icon else ""
    text_x = x + (39 if icon else 16)
    label_color = "#a54b45" if danger else "#413b30" if primary else "#303039"
    shadow = f'<rect x="{x+1}" y="{y+4}" width="{w-2}" height="{h}" rx="13" fill="#706d78" fill-opacity=".11"/>'
    face = r(x, y, w, h, fill, 12, edge)
    top_edge = f'<path d="M{x+14} {y+1}H{x+w-14}" stroke="#ffffff" stroke-opacity=".95" stroke-width="1.4"/>'
    return (
        shadow
        + glow
        + face
        + top_edge
        + icon_part
        + t(text_x, y + h / 2 + 5, label, 14, label_color, 580)
    )


def icon_button(x, y, icon, label, primary=False, size=46, enabled=True, icon_size=24):
    glow = (
        f'<rect x="{x-5}" y="{y-4}" width="{size+10}" height="{size+8}" rx="16" '
        f'fill="url(#warmGlow)" opacity=".54"/>'
        if primary and enabled
        else ""
    )
    shadow = f'<rect x="{x+1}" y="{y+4}" width="{size-2}" height="{size}" rx="13" fill="#706d78" fill-opacity=".12"/>'
    face = r(
        x, y, size, size,
        "url(#glass)" if enabled else "url(#quiet)",
        12, "#ffffff" if enabled else "#dedee5", .96 if enabled else .55,
    )
    return (
        shadow
        + glow
        + face
        + f'<path d="M{x+12} {y+1}H{x+size-12}" stroke="#ffffff" stroke-opacity=".95" stroke-width="1.4"/>'
        + glyph(
            x + (size - icon_size) / 2, y + (size - icon_size) / 2, icon, size=icon_size,
            color="#6f695d" if enabled else "#a6a6af",
        )
        + f'<title>{escape(label)}</title>'
    )


def field(x, y, w, label, value, h=42, hint=None):
    result = t(x, y - 8, label, 12, "#696975", 520)
    result += f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" fill="#d9d9e1" fill-opacity=".56" stroke="#ffffff" stroke-opacity=".8"/>'
    result += t(x + 13, y + h / 2 + 5, value, 14, "#45454f", 420)
    if hint:
        result += t(x, y + h + 17, hint, 11, "#747480", 400)
    return result


def pill(x, y, label, selected=False, width=None):
    width = width or max(64, len(label) * 15 + 22)
    color = "#efad49" if selected else "#ffffff"
    return (
        r(x, y, width, 32, "url(#glass)" if selected else "url(#quiet)", 10, color)
        + t(x + width / 2, y + 21, label, 12, "#3f3f49", 570 if selected else 430, "middle")
    )


def badge(x, y, label, kind="neutral"):
    color = {"good": "#39765d", "warn": "#9c6527", "danger": "#a54b45"}.get(kind, "#666672")
    return (
        f'<circle cx="{x+5}" cy="{y-4}" r="3.5" fill="{color}"/>'
        + t(x + 15, y, label, 12, color, 540)
    )


def section_title(x, y, title, detail=None):
    out = t(x, y, title, 17, "#2b2b34", 640)
    if detail:
        out += t(x, y + 21, detail, 12, "#6d6d79", 400)
    return out


def embedded_image(filename, x, y, width, height):
    encoded = b64encode((OUT / filename).read_bytes()).decode("ascii")
    return (
        f'<image href="data:image/png;base64,{encoded}" x="{x}" y="{y}" '
        f'width="{width}" height="{height}" preserveAspectRatio="xMidYMid meet" mask="url(#switchReferenceMask)"/>'
    )


def shell(
    page_title,
    active="全部功能",
    global_search=True,
    subtitle=None,
    mini_player=False,
    switch_reference_mask=False,
):
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="1360" height="900" viewBox="0 0 1360 900">']
    out.append("""
      <defs>
        <linearGradient id="scene" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#eeeeF2"/>
          <stop offset=".56" stop-color="#e5e5eb"/>
          <stop offset="1" stop-color="#d9d9df"/>
        </linearGradient>
        <radialGradient id="sceneWarm" cx=".73" cy=".28" r=".62">
          <stop offset="0" stop-color="#fff4dc" stop-opacity=".58"/>
          <stop offset=".52" stop-color="#fff0d8" stop-opacity=".14"/>
          <stop offset="1" stop-color="#fff0d8" stop-opacity="0"/>
        </radialGradient>
        <linearGradient id="glass" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#ffffff" stop-opacity=".96"/>
          <stop offset=".48" stop-color="#fafafd" stop-opacity=".90"/>
          <stop offset="1" stop-color="#e9e9ee" stop-opacity=".94"/>
        </linearGradient>
        <linearGradient id="quiet" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#ffffff" stop-opacity=".40"/>
          <stop offset="1" stop-color="#dcdce4" stop-opacity=".28"/>
        </linearGradient>
        <radialGradient id="warmGlow" cx=".83" cy=".12" r=".9">
          <stop offset="0" stop-color="#ffe8a5" stop-opacity=".95"/>
          <stop offset=".47" stop-color="#ffbd50" stop-opacity=".45"/>
          <stop offset="1" stop-color="#ffc65c" stop-opacity="0"/>
        </radialGradient>
        <linearGradient id="inset" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#d1d1da" stop-opacity=".76"/>
          <stop offset="1" stop-color="#e2e2e8" stop-opacity=".55"/>
        </linearGradient>
        <linearGradient id="album" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#edc584"/><stop offset=".55" stop-color="#d48761"/><stop offset="1" stop-color="#806d87"/>
        </linearGradient>
        <clipPath id="switchRefClip"><rect x="710" y="376" width="380" height="190" rx="14"/></clipPath>
      </defs>
    """.strip())
    if switch_reference_mask:
        out.append(
            '<defs><mask id="switchReferenceMask" maskUnits="objectBoundingBox" '
            'maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="black"/>'
        '<rect x=".16" y=".16" width=".68" height=".68" rx=".15" ry=".30" '
            'fill="white"/></mask></defs>'
        )
    out.append('<rect width="1360" height="900" fill="#16161a"/>')
    out.append('<rect x="16" y="16" width="1328" height="868" rx="18" fill="url(#scene)" stroke="#ffffff" stroke-opacity=".75"/>')
    out.append('<rect x="16" y="16" width="1328" height="868" rx="18" fill="url(#sceneWarm)"/>')
    out.append('<rect x="16" y="16" width="1328" height="42" rx="18" fill="#ededf1" fill-opacity=".80"/>')
    out.append('<path d="M16 58H1344" stroke="#cdccd3" stroke-opacity=".72"/>')
    for x, color in [(31, "#ee655a"), (56, "#efbe42"), (81, "#41b86b")]:
        out.append(f'<circle cx="{x}" cy="37" r="7" fill="{color}"/>')
    out.append(t(100, 42, "Aggregate", 15, "#555560", 620))
    out.append('<path d="M240 58V884" stroke="#c9c9d2" stroke-opacity=".72"/>')
    out.append(t(42, 103, "▦  Aggregate", 21, "#282832", 680))
    out.append(t(42, 152, "我的连接", 12, "#666671", 580))
    out.append(icon_button(188, 132, "plus", "添加连接", size=36, icon_size=16))
    for idx, (label, icon, status) in enumerate([
        ("示例 Git CLI", "terminal", "good"),
        ("示例 MCP", "link", "good"),
        ("示例网易云音乐", "music", "good"),
    ]):
        yy = 169 + idx * 49
        selected = active == label
        if selected:
            out.append(r(32, yy, 192, 40, "url(#glass)", 11, "#efb24f"))
        else:
            out.append(r(32, yy, 192, 40, "url(#quiet)", 11, "#ffffff", .75))
        out.append(glyph(45, yy + 12, icon, size=16))
        out.append(t(65, yy + 25, label, 13, "#42424c", 520))
        out.append(f'<circle cx="215" cy="{yy+20}" r="3" fill="#3a8064"/>')
    out.append('<path d="M32 334H224" stroke="#c6c6cf" stroke-opacity=".8"/>')
    navs = [("所有功能", "search"), ("管理连接", "link"), ("活动", "history")]
    for idx, (label, icon) in enumerate(navs):
        yy = 356 + idx * 47
        selected = active == label
        if selected:
            out.append(r(32, yy, 192, 38, "url(#glass)", 11, "#efb24f"))
            out.append('<rect x="39" y="%s" width="2" height="24" rx="1" fill="#e3a13e"/>' % (yy + 7))
        else:
            out.append(r(32, yy, 192, 38, "url(#quiet)", 11, "#ffffff", .6))
        out.append(glyph(46, yy + 11, icon, size=16))
        out.append(t(66, yy + 24, label, 13, "#42424c", 550 if selected else 450))
    yy = 710 if mini_player else 820
    selected = active == "设置"
    if selected:
        out.append(r(32, yy, 192, 38, "url(#glass)", 11, "#efb24f"))
    else:
        out.append(r(32, yy, 192, 38, "url(#quiet)", 11, "#ffffff", .6))
    out.append(glyph(46, yy + 11, "settings", size=16))
    out.append(t(66, yy + 24, "设置", 13, "#42424c", 550 if selected else 450))
    out.append(badge(43, 769 if mini_player else 879, "本机工作空间", "good"))
    if global_search:
        out.append(r(965, 69, 345, 38, "url(#glass)", 12, "#ffffff"))
        out.append(glyph(981, 81, "search", size=16))
        out.append(t(1002, 93, "搜索功能…", 12, "#62626d", 420))
        out.append(t(1292, 93, "⌘ K", 11, "#6a6a75", 500, "end"))
    out.append(t(298, 126, page_title, 25, "#282832", 680))
    if subtitle:
        out.append(t(299, 151, subtitle, 12, "#686873", 420))
    return out


def save(name, page):
    page.append("</svg>")
    (OUT / f"{name}.svg").write_text("\n".join(page), encoding="utf-8")


def board_workspace():
    p = shell("所有功能", "所有功能", global_search=False, subtitle="搜索并运行当前连接提供的功能")
    p.append(r(298, 174, 600, 42, "url(#inset)", 10, "#ffffff"))
    p.append(glyph(316, 185, "search", size=16))
    p.append(t(339, 201, "搜索名称、说明或来源", 13, "#777782", 420))
    p.append(t(878, 201, "⌘ K", 11, "#787883", 500, "end"))
    x = 298
    for label, selected, width in [("全部", True, 72), ("CLI", False, 62), ("MCP 工具", False, 98), ("资源", False, 68), ("提示", False, 68)]:
        p.append(pill(x, 229, label, selected, width))
        x += width + 10
    p.append(section_title(298, 292, "功能目录", "最近使用 · 收藏 · 全部"))
    p.append(t(643, 292, "12 项", 11, "#777782", 420, "end"))
    p.append(line(642, 276, 642, 842))
    rows = [
        ("查看 Git 状态", "CLI · 示例 Git CLI", False, "terminal"),
        ("读取项目说明", "资源 · 示例 MCP", False, "folder"),
        ("两个整数相加", "MCP 工具 · 示例 MCP", True, "play"),
        ("搜索歌曲", "CLI · 示例网易云音乐", False, "music"),
        ("继续播放", "CLI · 示例网易云音乐", False, "play"),
        ("播放状态", "CLI · 示例网易云音乐", False, "refresh"),
        ("生成摘要提示", "提示 · 示例 MCP", False, "search"),
        ("暂停播放", "CLI · 示例网易云音乐", False, "pause"),
    ]
    for i, (title, source, selected, icon) in enumerate(rows):
        y = 317 + i * 65
        if selected:
            p.append(r(298, y, 344, 56, "url(#glass)", 12, "#efb24f"))
        else:
            p.append(r(298, y, 344, 56, "url(#quiet)", 12, "#ffffff", .55))
        p.append(glyph(310, y + 16, icon, size=22))
        p.append(t(333, y + 23, title, 13, "#30303a", 590))
        p.append(t(333, y + 43, source, 10, "#777782", 420))
        p.append(icon_button(595, y + 5, "star", "收藏功能", size=46))
    p.append(t(716, 292, "两个整数相加", 21, "#2a2a34", 660))
    p.append(t(716, 318, "以预览结果演示 MCP 工具与结构化输出。", 13, "#6c6c77", 420))
    p.append(badge(716, 351, "示例 MCP · 只读", "good"))
    p.append(t(716, 369, "调用参数", 13, "#51515c", 560))
    p.append(field(716, 402, 290, "第一个整数", "输入整数"))
    p.append(field(1022, 402, 287, "第二个整数", "输入整数"))
    p.append(t(716, 494, "参数会交给示例 MCP 执行端。", 12, "#72727d", 420))
    p.append(button(1102, 468, 207, "运行", "play", True, h=48))
    p.append(t(1300, 494, "⌘ ↵", 11, "#71717c", 500, "end"))
    p.append(line(689, 529, 1309, 529))
    p.append(section_title(689, 566, "运行结果", "最近一次调用 · 预览数据"))
    p.append(badge(1260, 564, "尚未运行", "neutral"))
    p.append(r(689, 588, 620, 166, "url(#inset)", 12, "#ffffff", .65))
    p.append(t(712, 626, "结果会显示在这里", 13, "#686873", 440))
    p.append(t(712, 654, "运行状态、结构化输出、复制与文件操作将按结果类型出现。", 12, "#777782", 400))
    save("01-workspace", p)


def board_music():
    p = shell("示例网易云音乐", "示例网易云音乐", global_search=False, subtitle="音乐播放器")
    p.append(t(299, 191, "播放器", 14, "#676773", 540))
    p.append(badge(570, 191, "播放中", "good"))
    p.append(r(299, 211, 394, 430, "url(#glass)", 16, "#ffffff", .78))
    p.append('<rect x="421" y="239" width="150" height="150" rx="20" fill="url(#inset)" stroke="#ffffff" stroke-opacity=".85"/>')
    p.append(glyph(468, 286, "music", size=56))
    p.append(t(496, 427, "示例歌曲", 22, "#2c2c35", 650, "middle"))
    p.append(t(496, 455, "示例歌手", 13, "#686873", 460, "middle"))
    p.append(t(496, 481, "0:12 / 3:20", 12, "#72727d", 440, "middle"))
    p.append(icon_button(396, 510, "previous", "上一首", enabled=False))
    p.append(icon_button(446, 507, "pause", "暂停播放", True, size=48))
    p.append(icon_button(504, 510, "next", "下一首", enabled=False))
    p.append(icon_button(554, 510, "refresh", "刷新播放状态"))
    p.append(button(446, 566, 100, "停止播放", "stop", False, h=40))
    p.append(section_title(717, 191, "找音乐"))
    p.append(r(717, 211, 592, 46, "url(#inset)", 10, "#ffffff"))
    p.append(t(733, 239, "歌曲或歌手", 13, "#777782", 420))
    p.append(icon_button(1259, 213, "search", "搜索歌曲", True, size=42))
    p.append(t(717, 292, "歌曲 · 2 首", 15, "#34343e", 620))
    p.append(t(1308, 292, "由当前连接提供", 11, "#777782", 420, "end"))
    for i, (title, artist, playable) in enumerate([
        ("示例歌曲", "示例歌手", True),
        ("暂不可播放的歌曲", "示例歌手", False),
    ]):
        y = 314 + i * 87
        p.append(glyph(721, y + 8, "music", size=16))
        p.append(line(717, y + 66, 1308, y + 66))
        p.append(t(747, y + 24, title, 14, "#30303a", 590))
        p.append(t(747, y + 45, artist, 11, "#73737e", 420))
        if playable:
            p.append(icon_button(1250, y + 8, "play", f"播放 {title}", primary=True, size=42))
        else:
            p.append(t(1288, y + 33, "不可播放", 11, "#777782", 430, "end"))
    save("02-music", p)


def board_connections():
    p = shell("管理连接", "管理连接", global_search=True, subtitle="查看连接状态、诊断与可执行的管理操作")
    p.append(button(1140, 111, 169, "添加连接", "plus", True, h=42))
    p.append(section_title(299, 191, "连接列表", "选择连接查看详情 · 使用操作调整顺序"))
    for i, (name, kind, loc, selected) in enumerate([
        ("示例 Git CLI", "CLI", "本机 · 预览", True),
        ("示例 MCP", "HTTP MCP", "mcp://preview · 预览", False),
        ("示例网易云音乐", "CLI", "ncm-cli · 预览", False),
    ]):
        y = 221 + i * 67
        if selected:
            p.append(r(299, y, 267, 57, "url(#glass)", 12, "#efb24f"))
        else:
            p.append(r(299, y, 267, 57, "url(#quiet)", 12, "#ffffff", .55))
        p.append(badge(316, y + 21, name, "good"))
        p.append(t(331, y + 42, f"{kind} · {loc}", 10, "#777782", 420))
    p.append(line(584, 184, 584, 836))
    p.append(t(616, 204, "示例 Git CLI", 22, "#2b2b34", 660))
    p.append(badge(616, 232, "就绪", "good"))
    p.append(t(704, 232, "本机执行", 12, "#6c6c77", 420))
    p.append(button(1179, 190, 130, "测试连接", "check", False, h=42))
    p.append(section_title(616, 290, "连接信息"))
    p.append(t(616, 322, "执行程序", 12, "#777782", 440))
    p.append(t(777, 322, "git · 预览", 13, "#33333d", 520))
    p.append(line(616, 339, 1308, 339))
    p.append(section_title(616, 382, "可用功能", "1 项 · 选择后打开参数与结果"))
    p.append(button(616, 420, 692, "查看 Git 状态", "terminal", False, h=48))
    p.append(section_title(616, 500, "检查结果", "最近一次连接检测"))
    p.append(r(616, 540, 692, 58, "url(#quiet)", 11, "#ffffff", .62))
    p.append(badge(638, 574, "检查通过", "good"))
    p.append(t(753, 574, "能力目录已更新", 12, "#5e5e69", 440))
    p.append(section_title(616, 620, "动作", "排序、刷新和动作配置"))
    p.append(icon_button(616, 660, "arrow_up", "连接上移", size=46))
    p.append(icon_button(672, 660, "arrow_down", "连接下移", size=46))
    p.append(button(732, 660, 183, "刷新能力", "refresh", False, h=42))
    p.append(button(927, 660, 183, "编辑动作", "settings", False, h=42))
    p.append(line(616, 730, 1308, 730))
    p.append(t(616, 770, "危险操作", 13, "#9e5550", 580))
    p.append(t(616, 792, "删除仅移除此连接配置；执行前保留现有二次确认。", 11, "#797983", 420))
    p.append(button(616, 812, 126, "删除连接", "trash", False, quiet=True, h=40, danger=True))
    save("03-connections", p)


def board_activity():
    p = shell("活动", "活动", global_search=True, subtitle="查看最近调用状态；参数和结果正文不写入历史")
    p.append(section_title(299, 194, "运行记录", "最近 100 条"))
    p.append(icon_button(1267, 171, "refresh", "刷新活动", size=42))
    x = 299
    for label, selected, width in [("全部", True, 72), ("成功", False, 70), ("失败", False, 70), ("取消", False, 70), ("超时", False, 70), ("运行中", False, 82), ("结果待确认", False, 112)]:
        p.append(pill(x, 214, label, selected, width))
        x += width + 9
    p.append(line(695, 269, 695, 843))
    runs = [
        ("查看 Git 状态", "示例 Git CLI", "今天 16:42", "成功", "good"),
        ("两个整数相加", "示例 MCP", "今天 16:37", "成功", "good"),
        ("播放状态", "示例网易云音乐", "今天 15:58", "运行中", "warn"),
        ("读取项目说明", "示例 MCP", "今天 15:20", "失败", "danger"),
        ("搜索歌曲", "示例网易云音乐", "今天 14:54", "已取消", "neutral"),
    ]
    for i, (name, source, time, state, color) in enumerate(runs):
        y = 273 + i * 83
        if i == 0:
            p.append(f'<g>{r(299, y, 361, 72, "url(#glass)", 12, "#efb24f")}</g>')
        else:
            p.append(r(299, y, 361, 72, "url(#quiet)", 12, "#ffffff", .45))
        p.append(t(318, y + 25, name, 14, "#30303a", 600))
        p.append(t(318, y + 48, time, 11, "#757580", 420))
        p.append(badge(557, y + 49, state, color))
    p.append(t(727, 297, "查看 Git 状态", 21, "#2b2b34", 650))
    p.append(badge(727, 324, "成功", "good"))
    p.append(t(828, 324, "今天 16:42 · 示例 Git CLI", 11, "#767680", 420))
    p.append(line(727, 348, 1309, 348))
    p.append(section_title(727, 389, "运行信息", "活动只保留状态元数据"))
    for i, (label, value) in enumerate([
        ("功能", "查看 Git 状态"),
        ("来源", "示例 Git CLI"),
        ("状态", "成功"),
        ("时间", "今天 16:42"),
        ("运行 ID", "run-preview-001"),
    ]):
        y = 429 + i * 38
        p.append(t(727, y, label, 11, "#777782", 440))
        p.append(t(828, y, value, 12, "#363640", 500))
    p.append(line(727, 621, 1309, 621))
    p.append(t(727, 655, "参数和结果正文未写入活动记录。", 11, "#777782", 420))
    p.append(button(727, 710, 158, "重新打开功能", "folder", True, h=44))
    p.append(button(898, 710, 130, "复制诊断", "check", False, h=44))
    save("04-activity", p)


def board_settings():
    p = shell(
        "设置",
        "设置",
        global_search=True,
        subtitle="让材质、光线和工作方式保持一致",
        switch_reference_mask=True,
    )
    p.append(line(489, 184, 489, 843))
    for i, label in enumerate(["外观", "Mac Host", "快捷键", "本机数据"]):
        y = 198 + i * 49
        if i == 0:
            p.append(r(299, y, 176, 40, "url(#glass)", 11, "#efb24f"))
        else:
            p.append(r(299, y, 176, 40, "url(#quiet)", 11, "#ffffff", .5))
        p.append(glyph(314, y + 10, ["settings", "link", "terminal", "history"][i], size=16))
        p.append(t(337, y + 26, label, 13, "#383842", 550 if i == 0 else 440))
    p.append(section_title(513, 204, "外观", "拖动玻璃控件，在浅色和深色之间切换。"))
    p.append(t(513, 274, "当前模式", 12, "#73737e", 440))
    p.append(t(584, 274, "浅色", 13, "#3c3c45", 560))
    # The crop shows the production switch in its shared scene. Runtime uses
    # GlassThemeSwitch directly; this static image is documentation only.
    p.append(embedded_image("theme-switch-light.png", 655, 312, 490, 245))
    p.append(button(817, 565, 166, "跟随 macOS 系统", "settings", False, h=40))
    save("05-settings-appearance", p)


def board_host():
    p = shell("设置", "设置", global_search=True, subtitle="管理配对 Mac 与访问权限")
    p.append(line(489, 184, 489, 843))
    for i, label in enumerate(["外观", "Mac Host", "快捷键", "本机数据"]):
        y = 198 + i * 49
        selected = i == 1
        p.append(r(299, y, 176, 40, "url(#glass)" if selected else "url(#quiet)", 11, "#efb24f" if selected else "#ffffff"))
        p.append(glyph(314, y + 10, ["settings", "link", "terminal", "history"][i], size=16))
        p.append(t(337, y + 26, label, 13, "#383842", 550 if selected else 440))
    p.append(section_title(526, 204, "Mac Host", "让已配对设备安全连接到这台 Mac。"))
    p.append(badge(526, 252, "运行中", "good"))
    p.append(button(1189, 218, 120, "停止 Host", "stop", False, h=40, danger=True))
    p.append(t(526, 291, "轮换身份会撤销全部配对授权并停止 Host。", 11, "#777782", 420))
    p.append(button(1129, 270, 180, "轮换 Mac Host 身份", "lock", False, quiet=True, h=40, danger=True))
    p.append(line(526, 326, 1309, 326))
    p.append(section_title(526, 360, "配对邀请", "二维码只包含短时邀请和 Host 地址，不含长期设备密钥。"))
    p.append(button(1168, 336, 141, "生成新邀请", "plus", True, h=40))
    p.append(r(526, 382, 783, 200, "url(#quiet)", 13, "#ffffff", .62))
    p.append('<rect x="548" y="394" width="176" height="176" rx="10" fill="#fbfbfc" stroke="#d6d6de"/>')
    for row in range(13):
        for col in range(13):
            if (row * 3 + col * 5 + row * col) % 4 != 0:
                p.append(f'<rect x="{570+col*9}" y="{416+row*9}" width="5" height="5" rx="1" fill="#595965"/>')
    p.append(t(748, 416, "邀请已生成 · 有效期 09:42", 14, "#33333d", 570))
    p.append(t(748, 441, "1 个本机网络地址", 11, "#70707b", 430))
    p.append(button(748, 462, 138, "复制配对信息", "link", False, quiet=True, h=38))
    p.append(line(526, 607, 1309, 607))
    p.append(section_title(526, 640, "待处理设备", "核对设备与确认码后再审批"))
    p.append(icon_button(1263, 616, "refresh", "刷新配对设备", size=42))
    p.append(r(526, 662, 783, 68, "url(#quiet)", 11, "#ffffff", .62))
    p.append(t(540, 689, "Pixel 9", 13, "#33333d", 580))
    p.append(t(540, 710, "Android · 确认码 482 193", 10, "#777782", 420))
    p.append(button(748, 676, 84, "拒绝", "close", False, quiet=True, h=40, danger=True))
    p.append(button(840, 676, 107, "批准只读", "check", False, h=40))
    p.append(button(955, 676, 143, "允许连接向导", "link", True, h=40))
    p.append(button(1106, 676, 125, "自定义权限", "settings", False, h=40))
    p.append(section_title(526, 765, "已配对设备", "权限可随时编辑或撤销"))
    p.append(r(526, 785, 783, 64, "url(#quiet)", 11, "#ffffff", .62))
    p.append(t(540, 812, "LGE AN10", 13, "#33333d", 560))
    p.append(t(540, 833, "读取连接", 10, "#777782", 420))
    p.append(button(1080, 797, 112, "修改权限", "settings", False, h=40))
    p.append(button(1198, 797, 111, "撤销", "close", False, quiet=True, h=40, danger=True))
    save("06-settings-host", p)


def board_setup():
    p = shell("管理连接", "管理连接", global_search=True, subtitle="按步骤配置本机 CLI 或 MCP 服务")
    p.append('<rect x="263" y="58" width="1081" height="826" fill="#18181d" fill-opacity=".17"/>')
    p.append('<rect x="470" y="115" width="642" height="724" rx="18" fill="#686570" fill-opacity=".12"/>')
    p.append('<rect x="473" y="112" width="642" height="724" rx="18" fill="url(#glass)" stroke="#ffffff" stroke-width="1.5"/>')
    p.append(t(509, 157, "添加连接", 21, "#2b2b34", 660))
    p.append(t(509, 182, "连接本机 CLI 或 MCP 服务。", 12, "#70707b", 420))
    p.append(line(509, 199, 1078, 199))
    p.append(pill(509, 217, "1  类型", False, 94))
    p.append(pill(613, 217, "2  目标", False, 94))
    p.append(pill(717, 217, "3  配置", True, 94))
    p.append(pill(821, 217, "4  检查", False, 94))
    p.append(section_title(509, 294, "本机 CLI", "先选运行方式；后续步骤会保留当前填写。"))
    p.append(pill(509, 327, "CLI", True, 70))
    p.append(pill(589, 327, "MCP stdio", False, 114))
    p.append(pill(713, 327, "MCP HTTP", False, 116))
    p.append(field(509, 394, 568, "连接名称", "Git 工作区"))
    p.append(field(509, 462, 568, "程序路径", "/usr/bin/git"))
    p.append(button(949, 479, 128, "选择程序", "folder", False, h=38))
    p.append(field(509, 530, 568, "默认参数", "status --short --branch", hint="运行时会与动作配置合并。"))
    p.append(section_title(509, 618, "执行目标", "可选本机或已配对 Mac Host。"))
    p.append(pill(509, 642, "本机", True, 82))
    p.append(pill(601, 642, "已配对 Mac", False, 118))
    p.append(line(509, 697, 1078, 697))
    p.append(button(509, 725, 113, "取消", "close", False, quiet=True, h=44))
    p.append(button(633, 725, 123, "上一步", "back", False, h=44))
    p.append(button(925, 725, 153, "检查连接", "check", True, h=46))
    p.append(t(509, 792, "所有字段校验、测试、保存条件和确认流程按原逻辑执行。", 11, "#777782", 420))
    save("07-connection-setup", p)


def board_run_terminal():
    p = shell("查看 Git 状态", "示例 Git CLI", global_search=True, subtitle="只读 · 本机工作空间")
    p.append(t(299, 189, "查看 Git 状态", 22, "#2b2b34", 650))
    p.append(t(299, 217, "读取当前工作区分支、暂存区与文件变更。", 12, "#6f6f7a", 420))
    p.append(badge(299, 250, "运行中", "warn"))
    p.append(t(393, 250, "已运行 00:04", 11, "#777782", 420))
    p.append(button(1172, 225, 137, "取消运行", "settings", False, h=42))
    p.append(line(299, 277, 1309, 277))
    p.append(section_title(299, 316, "终端", "真实会话 · 输出流继续由原执行端提供"))
    p.append(r(299, 338, 1010, 362, "#22232a", 13, "#ffffff", 1))
    terminal = [
        ("$ git status --short --branch", "#e4e4ea"),
        ("Resolving dependencies...", "#c3c3cf"),
        ("## main...origin/main", "#c3c3cf"),
        (" M app/lib/features/catalog/workspace_page.dart", "#c3c3cf"),
        ("", "#c3c3cf"),
        ("Waiting for command output…", "#f2c579"),
    ]
    for i, (content, color) in enumerate(terminal):
        p.append(t(322, 375 + i * 31, content, 12, color, 420))
    p.append(line(299, 728, 1309, 728))
    p.append(section_title(299, 770, "运行输出", "任务完成后显示摘要、复制、文件预览和访达操作。"))
    p.append(badge(1240, 770, "等待完成", "neutral"))
    save("08-terminal-running", p)


def board_permission():
    p = shell("查看 Git 状态", "示例 Git CLI", global_search=True, subtitle="权限确认只展示将要交付的输入与实际执行目标")
    p.append(t(299, 189, "查看 Git 状态", 22, "#2b2b34", 650))
    p.append(t(299, 217, "本次操作尚未执行。", 12, "#6f6f7a", 420))
    p.append(r(299, 256, 1010, 472, "url(#quiet)", 14, "#ffffff", .45))
    p.append('<rect x="263" y="58" width="1081" height="826" fill="#25252b" fill-opacity=".22"/>')
    p.append('<rect x="425" y="284" width="622" height="328" rx="18" fill="#686570" fill-opacity=".13"/>')
    p.append('<rect x="422" y="280" width="622" height="328" rx="18" fill="url(#glass)" stroke="#ffffff" stroke-width="1.5"/>')
    p.append(glyph(461, 322, "lock", size=20))
    p.append(t(491, 338, "允许执行查看 Git 状态？", 19, "#2b2b34", 650))
    p.append(t(461, 384, "连接", 11, "#777782", 480))
    p.append(t(568, 384, "示例 Git CLI · 本机工作空间", 13, "#383842", 530))
    p.append(t(461, 416, "操作", 11, "#777782", 480))
    p.append(t(568, 416, "读取当前分支和工作区变更", 13, "#383842", 530))
    p.append(t(461, 448, "输入", 11, "#777782", 480))
    p.append(t(568, 448, "无额外参数", 13, "#383842", 530))
    p.append(line(461, 477, 1005, 477))
    p.append(t(461, 512, "只有确认后，命令才会发送到对应执行端。", 12, "#6c6c77", 430))
    p.append(button(693, 540, 117, "取消", "close", False, quiet=True, h=42))
    p.append(button(821, 540, 184, "允许并运行", "play", True, h=42))
    save("09-permission-confirmation", p)


def board_states():
    p = shell("所有功能", "所有功能", global_search=False, subtitle="相同结构下呈现真实的加载、空结果与错误状态")
    cards = [
        (299, 193, "加载中", "正在读取连接能力…", "圆点静止，避免用装饰动画暗示完成", "无操作"),
        (642, 193, "空连接", "还没有可运行的功能。", "检查连接配置，或添加一个 CLI / MCP 连接。", "添加连接"),
        (985, 193, "搜索无匹配", "没有找到匹配结果。", "更换关键词或清除筛选条件。", "清除筛选"),
        (299, 500, "连接失败", "无法读取连接能力。", "保留已填写内容，展示诊断信息和原重试入口。", "重试"),
        (642, 500, "结果待确认", "执行结果暂时无法确认。", "先检查运行状态，不自动重复运行命令。", "检查状态"),
        (985, 500, "权限被拒绝", "操作没有执行。", "说明拒绝范围，并提供回到功能页的路径。", "返回功能"),
    ]
    for x, y, title, message, detail, action in cards:
        p.append(r(x, y, 318, 256, "url(#quiet)", 15, "#ffffff", .6))
        p.append(glyph(x + 23, y + 24, "history" if title == "结果待确认" else "check", size=22, color="#7a7467"))
        p.append(t(x + 50, y + 38, title, 16, "#30303a", 620))
        p.append(t(x + 23, y + 86, message, 13, "#42424c", 530))
        p.append(t(x + 23, y + 114, detail, 11, "#73737e", 420))
        if action == "无操作":
            p.append('<circle cx="%s" cy="%s" r="3" fill="#9b927f"/>' % (x + 27, y + 204))
            p.append(t(x + 39, y + 208, "读取中", 11, "#73737e", 420))
        else:
            p.append(button(x + 23, y + 181, 132, action, "refresh" if action in ("重试", "检查状态") else "play", action == "检查状态", h=40))
    p.append(t(299, 836, "状态标题、说明、图标、按钮命中区和焦点顺序保持一致；具体文案与动作来自业务状态。", 11, "#777782", 420))
    save("10-states", p)


def board_button_states():
    p = shell("按钮与动效", "设置", global_search=False, subtitle="圆点图形保持统一栅格；外部材质按任务主次表达")
    samples = [
        (299, "静置", "低幅度玻璃反射；图案清晰稳定", "play", "运行", False, False),
        (548, "悬停 / 聚焦", "边缘高光增强；焦点环明确", "refresh", "刷新", False, True),
        (797, "按下", "面层轻压；点阵短暂收束后回弹", "search", "搜索", True, False),
        (1046, "禁用", "降低面层和光效；图案仍可辨", "settings", "设置", False, False),
    ]
    for x, title, caption, icon, label, primary, selected in samples:
        p.append(t(x + 72, 223, title, 14, "#3b3b45", 600, "middle"))
        p.append(f'<rect x="{x+1}" y="250" width="143" height="145" rx="28" fill="#706d78" fill-opacity=".13"/>')
        p.append(r(x, 246, 145, 145, "url(#glass)", 28, "#ffffff"))
        if primary:
            p.append('<rect x="%s" y="246" width="145" height="145" rx="28" fill="url(#warmGlow)" opacity=".58"/>' % x)
        if selected:
            p.append(f'<rect x="{x}" y="246" width="145" height="145" rx="28" fill="none" stroke="#c27b23" stroke-width="2"/>')
        p.append(glyph(x + 64, 305, icon, size=32))
        p.append(t(x + 72, 423, label, 14, "#31313a", 520, "middle"))
        p.append(t(x + 72, 455, caption, 10, "#74747f", 420, "middle"))
    p.append(section_title(299, 535, "动画节奏"))
    p.append(line(299, 560, 1309, 560))
    for y, label, value in [
        (594, "静置", "低幅呼吸与光线轻掠；无持续闪烁"),
        (641, "按下", "90–130 ms 压合；回弹 180–240 ms"),
        (688, "选中", "暖边缘出现 220 ms，保持低亮度"),
        (735, "忙碌", "只表达真实任务状态；装饰运动停止"),
        (782, "减少动态", "完全停止装饰动画，交互逻辑不变"),
    ]:
        p.append(t(299, y, label, 12, "#555560", 560))
        p.append(t(412, y, value, 12, "#6f6f7a", 430))
        p.append(line(299, y + 17, 1309, y + 17, "#c9c9d2", ".42"))
    save("11-button-motion", p)


def board_dark_reference():
    p = shell("所有功能", "所有功能", global_search=False, subtitle="深色主题沿用同一布局，材质和状态令牌切换")
    p.append('<rect x="16" y="16" width="1328" height="868" rx="18" fill="#202126" stroke="#454751"/>')
    p.append('<rect x="16" y="16" width="1328" height="42" rx="18" fill="#26272e"/>')
    for x, color in [(31, "#ee655a"), (56, "#efbe42"), (81, "#41b86b")]:
        p.append(f'<circle cx="{x}" cy="37" r="7" fill="{color}"/>')
    p.append(t(100, 42, "Aggregate", 15, "#d5d6de", 620))
    p.append('<path d="M16 58H1344M240 58V884" stroke="#454751"/>')
    p.append(t(42, 103, "▦  Aggregate", 21, "#efeff3", 680))
    p.append(t(42, 152, "我的连接", 12, "#b8bac5", 580))
    p.append(r(188, 132, 36, 36, "#292b32", 11, "#454751"))
    p.append(glyph(198, 142, "plus", size=16, color="#c4c5ce"))
    for idx, (label, icon) in enumerate([("示例 Git CLI", "terminal"), ("示例 MCP", "link"), ("示例网易云音乐", "music")]):
        yy = 169 + idx * 49
        p.append(f'<rect x="32" y="{yy}" width="192" height="40" rx="11" fill="#292b32" stroke="#454751"/>')
        p.append(glyph(45, yy + 12, icon, size=16, color="#c4c5ce"))
        p.append(t(65, yy + 25, label, 13, "#d5d6de", 520))
        p.append(f'<circle cx="215" cy="{yy+20}" r="3" fill="#a2d6bc"/>')
    p.append('<path d="M32 334H224" stroke="#454751"/>')
    for idx, (label, icon) in enumerate([("所有功能", "search"), ("管理连接", "link"), ("活动", "history")]):
        yy = 356 + idx * 47
        edge = "#ffd29b" if idx == 0 else "#454751"
        p.append(f'<rect x="32" y="{yy}" width="192" height="38" rx="11" fill="#292b32" stroke="{edge}"/>')
        p.append(glyph(46, yy + 11, icon, size=16, color="#c4c5ce"))
        p.append(t(66, yy + 24, label, 13, "#efeff3", 540 if idx == 0 else 450))
    p.append('<rect x="32" y="820" width="192" height="38" rx="11" fill="#292b32" stroke="#454751"/>')
    p.append(glyph(46, 831, "settings", size=16, color="#c4c5ce"))
    p.append(t(66, 844, "设置", 13, "#d5d6de", 450))
    p.append(t(298, 126, "所有功能", 25, "#efeff3", 680))
    p.append(t(298, 151, "相同的任务结构、间距与焦点顺序。", 12, "#b8bac5", 420))
    p.append(r(298, 174, 600, 42, "#111216", 10, "#454751"))
    p.append(glyph(316, 185, "search", size=16, color="#c4c5ce"))
    p.append(t(339, 201, "搜索名称、说明或来源", 13, "#b8bac5", 420))
    p.append(t(878, 201, "⌘ K", 11, "#b8bac5", 500, "end"))
    for x, label, selected, width in [
        (298, "全部", True, 72), (380, "CLI", False, 62),
        (452, "MCP 工具", False, 98), (560, "资源", False, 68),
        (638, "提示", False, 68),
    ]:
        p.append(f'<rect x="{x}" y="229" width="{width}" height="32" rx="10" fill="#292b32" stroke="#454751"/>')
        p.append(t(x + width/2, 250, label, 12, "#efeff3" if selected else "#b8bac5", 550 if selected else 420, "middle"))
    p.append(t(298, 292, "功能目录", 17, "#efeff3", 640))
    p.append(t(643, 292, "12 项", 11, "#b8bac5", 420, "end"))
    p.append(line(642, 276, 642, 842, "#454751"))
    dark_rows = [
        ("查看 Git 状态", "CLI · 示例 Git CLI", "terminal"),
        ("读取项目说明", "资源 · 示例 MCP", "document"),
        ("两个整数相加", "MCP 工具 · 示例 MCP", "data"),
        ("搜索歌曲", "CLI · 示例网易云音乐", "music"),
        ("继续播放", "CLI · 示例网易云音乐", "play"),
        ("播放状态", "CLI · 示例网易云音乐", "refresh"),
        ("生成摘要提示", "提示 · 示例 MCP", "chat"),
        ("暂停播放", "CLI · 示例网易云音乐", "pause"),
    ]
    for i, (title, source, icon) in enumerate(dark_rows):
        y = 317 + i * 65
        if i == 2:
            p.append('<rect x="298" y="%s" width="344" height="56" rx="12" fill="#292b32" stroke="#ffd29b"/>' % y)
        else:
            p.append('<rect x="298" y="%s" width="344" height="56" rx="12" fill="#292b32" fill-opacity=".52" stroke="#454751"/>' % y)
        p.append(glyph(310, y + 16, icon, size=22, color="#d1d2db"))
        p.append(t(333, y + 24, title, 13, "#efeff3", 580))
        p.append(t(333, y + 43, source, 10, "#b8bac5", 420))
        p.append(icon_button(595, y + 5, "star", "收藏功能", size=46))
    p.append(t(689, 292, "两个整数相加", 21, "#efeff3", 660))
    p.append(t(689, 318, "以预览结果演示 MCP 工具与结构化输出。", 13, "#b8bac5", 420))
    p.append(t(689, 351, "示例 MCP · 只读", 12, "#a2d6bc", 520))
    p.append(t(689, 381, "第一个整数", 12, "#b8bac5", 520))
    p.append('<rect x="689" y="389" width="290" height="42" rx="9" fill="#111216" stroke="#454751"/>')
    p.append(t(702, 415, "输入整数", 14, "#777782", 420))
    p.append(t(1002, 381, "第二个整数", 12, "#b8bac5", 520))
    p.append('<rect x="1002" y="389" width="287" height="42" rx="9" fill="#111216" stroke="#454751"/>')
    p.append(t(1015, 415, "输入整数", 14, "#777782", 420))
    p.append('<rect x="1102" y="454" width="207" height="48" rx="12" fill="#292b32" stroke="#ffd29b"/>')
    p.append(glyph(1117, 467, "play", size=24, color="#f4efdf"))
    p.append(t(1141, 485, "运行", 14, "#efeff3", 570))
    p.append(line(689, 515, 1309, 515, "#454751", ".75"))
    p.append(t(689, 552, "运行结果", 17, "#efeff3", 640))
    p.append('<rect x="689" y="574" width="620" height="180" rx="12" fill="#111216" fill-opacity=".82" stroke="#454751"/>')
    p.append(t(712, 612, "结果会显示在这里", 13, "#b8bac5", 440))
    save("12-dark-reference", p)


def board_action_editor():
    p = shell("管理连接", "管理连接", global_search=True, subtitle="编辑动作清单 · 变更保存前可检查和预览参数")
    p.append(t(299, 190, "示例 Git CLI", 22, "#2b2b34", 650))
    p.append(t(299, 219, "动作由当前连接的清单定义。", 12, "#6f6f7a", 420))
    p.append(r(299, 255, 1010, 468, "url(#quiet)", 14, "#ffffff", .5))
    p.append('<rect x="263" y="58" width="1081" height="826" fill="#25252b" fill-opacity=".22"/>')
    p.append('<rect x="348" y="93" width="664" height="713" rx="18" fill="#6e6c76" fill-opacity=".13"/>')
    p.append('<rect x="345" y="90" width="664" height="713" rx="18" fill="url(#glass)" stroke="#ffffff" stroke-width="1.5"/>')
    p.append(t(380, 133, "编辑动作 · 示例 Git CLI", 20, "#2b2b34", 650))
    p.append(t(380, 159, "清单版本 1 · 参数以数组传递，{{变量名}} 从输入规则取值。", 11, "#72727d", 420))
    p.append(button(380, 176, 111, "新增动作", "plus", False, h=38))
    p.append(button(501, 176, 88, "导入", "folder", False, quiet=True, h=38))
    p.append(button(599, 176, 88, "导出", "folder", False, quiet=True, h=38))
    p.append(t(380, 239, "动作清单 JSON", 12, "#696975", 520))
    p.append(r(380, 251, 594, 283, "#d8d8e0", 10, "#ffffff", .76))
    json_lines = [
        ('{', '#555560'),
        ('  "schemaVersion": 1,', '#555560'),
        ('  "executable": "/usr/bin/git",', '#555560'),
        ('  "actions": [', '#555560'),
        ('    { "id": "status",', '#51515c'),
        ('      "title": "查看 Git 状态",', '#51515c'),
        ('      "argv": ["status", "--short"],', '#51515c'),
        ('      "permission": "read",', '#51515c'),
        ('      "timeoutMs": 30000 }', '#51515c'),
        ('  ]', '#555560'),
        ('}', '#555560'),
    ]
    for i, (value, color) in enumerate(json_lines):
        p.append(t(398, 278 + i * 21, value, 11, color, 420))
    p.append(t(380, 571, "预览动作", 12, "#696975", 520))
    p.append(r(380, 583, 274, 40, "url(#inset)", 9, "#ffffff"))
    p.append(t(394, 608, "查看 Git 状态  ▾", 13, "#44444e", 460))
    p.append(t(677, 571, "预览输入 JSON", 12, "#696975", 520))
    p.append(r(677, 583, 297, 72, "url(#inset)", 9, "#ffffff"))
    p.append(t(693, 610, "{}", 12, "#555560", 420))
    p.append(button(380, 667, 179, "检查并预览参数", "search", False, h=40))
    p.append(r(573, 666, 401, 62, "url(#quiet)", 9, "#ffffff", .52))
    p.append(t(590, 692, "清单有效；此处只显示最终参数数组，不会运行程序。", 10, "#6e6e79", 420))
    p.append(line(380, 746, 974, 746))
    p.append(button(702, 761, 113, "取消", "settings", False, quiet=True, h=40))
    p.append(button(824, 761, 150, "保存动作", "check", True, h=40))
    save("13-action-editor", p)


def board_music_account():
    p = shell("示例网易云音乐", "示例网易云音乐", global_search=False, subtitle="网易云音乐账号通过可选的连接账号能力管理")
    p.append(r(299, 196, 1010, 528, "url(#quiet)", 14, "#ffffff", .48))
    p.append('<rect x="263" y="58" width="1081" height="826" fill="#25252b" fill-opacity=".20"/>')
    p.append('<rect x="449" y="166" width="466" height="552" rx="18" fill="#6e6c76" fill-opacity=".13"/>')
    p.append('<rect x="446" y="163" width="466" height="552" rx="18" fill="url(#glass)" stroke="#ffffff" stroke-width="1.5"/>')
    p.append(glyph(469, 187, "link", size=22))
    p.append(t(498, 202, "网易云音乐账号", 18, "#2b2b34", 640))
    p.append(icon_button(856, 177, "close", "关闭账号面板", size=38))
    p.append(t(471, 239, "当前未登录", 13, "#4a4a54", 520))
    p.append(t(471, 270, "使用网易云音乐 App 扫描二维码，在手机上确认登录。", 11, "#70707b", 420))
    p.append(r(559, 297, 240, 240, "#ffffff", 12, "#e2e2e7", 1))
    # A non-scannable visual placeholder clearly labeled as sample artwork.
    for row in range(13):
        for col in range(13):
            if (row * 7 + col * 11 + row * col) % 5 != 0:
                p.append(f'<rect x="{576+col*15}" y="{314+row*15}" width="10" height="10" rx="1" fill="#54545f"/>')
    p.append(t(679, 555, "样例二维码位置 · 不可扫描", 10, "#767680", 420, "middle"))
    p.append(t(471, 591, "登录二维码会在生成后显示，并等待手机确认。", 11, "#70707b", 420))
    p.append(button(646, 638, 139, "取消扫码", "close", False, quiet=True, h=40))
    p.append(t(471, 686, "读取失败、生成超时和会话中断时保留重试提示；登录状态由连接端确认。", 10, "#777782", 420))
    save("14-music-account-login", p)


def board_settings_shortcuts():
    p = shell("设置", "设置", global_search=True, subtitle="快捷键")
    p.append(line(489, 184, 489, 843))
    for i, label in enumerate(["外观", "Mac Host", "快捷键", "本机数据"]):
        y = 198 + i * 49
        selected = i == 2
        p.append(r(299, y, 176, 40, "url(#glass)" if selected else "url(#quiet)", 11, "#efb24f" if selected else "#ffffff"))
        p.append(glyph(314, y + 10, ["settings", "link", "terminal", "history"][i], size=16))
        p.append(t(337, y + 26, label, 13, "#383842", 550 if selected else 440))
    p.append(section_title(526, 204, "快捷键", "常用操作始终使用同一组系统组合键。"))
    for i, (label, combo) in enumerate([
        ("搜索所有功能", "⌘ K"),
        ("运行当前功能", "⌘ ↵"),
        ("返回或关闭", "Esc"),
    ]):
        y = 269 + i * 45
        p.append(t(526, y, label, 13, "#40404a", 500))
        p.append(t(1290, y, combo, 13, "#565660", 560, "end"))
        p.append(line(526, y + 18, 1309, y + 18))
    save("15-settings-shortcuts", p)


def board_settings_local_data():
    p = shell("设置", "设置", global_search=True, subtitle="本机数据")
    p.append(line(489, 184, 489, 843))
    for i, label in enumerate(["外观", "Mac Host", "快捷键", "本机数据"]):
        y = 198 + i * 49
        selected = i == 3
        p.append(r(299, y, 176, 40, "url(#glass)" if selected else "url(#quiet)", 11, "#efb24f" if selected else "#ffffff"))
        p.append(glyph(314, y + 10, ["settings", "link", "terminal", "history"][i], size=16))
        p.append(t(337, y + 26, label, 13, "#383842", 550 if selected else 440))
    p.append(section_title(526, 204, "本机数据", "连接配置和活动记录保存在本机或执行端；活动内容不会保存参数或结果。"))
    p.append(t(526, 254, "HTTP MCP 的 Bearer Token 保存在当前运行端的安全存储中。", 12, "#70707b", 420))
    p.append(t(526, 302, "活动保留时长", 13, "#40404a", 520))
    p.append(t(526, 325, "只保留最近活动记录。", 11, "#74747f", 420))
    p.append(r(1190, 294, 119, 42, "url(#glass)", 10, "#ffffff"))
    p.append(t(1205, 320, "30 天  ▾", 12, "#42424c", 500))
    p.append(line(526, 356, 1309, 356))
    p.append(t(526, 376, "清空活动记录", 13, "#9e5550", 550))
    p.append(t(526, 399, "删除本机保存的调用历史。", 11, "#74747f", 420))
    p.append(button(1150, 374, 159, "清空记录", "trash", False, quiet=True, h=42, danger=True))
    p.append(line(526, 446, 1309, 446))
    p.append(section_title(526, 472, "关于 Aggregate"))
    p.append(t(526, 503, "Aggregate 开发版 · CLI 与 MCP 功能聚合工作台", 12, "#70707b", 420))
    save("22-settings-local-data", p)


def board_result_success():
    p = shell("所有功能", "所有功能", global_search=False, subtitle="运行结果保持在当前能力上下文内，动作仍沿用 Runtime 事件")
    p.append(r(298, 174, 250, 42, "url(#inset)", 10, "#ffffff"))
    p.append(glyph(315, 185, "search", size=16))
    p.append(t(338, 201, "搜索功能", 13, "#777782", 420))
    p.append(section_title(298, 263, "功能目录", "12 项"))
    for i, (name, desc) in enumerate([
        ("查看 Git 状态", "CLI · 示例 Git CLI"),
        ("读取项目说明", "资源 · 示例 MCP"),
        ("两个整数相加", "MCP 工具 · 示例 MCP"),
    ]):
        y = 286 + i * 62
        selected = i == 2
        p.append(r(298, y, 250, 54, "url(#glass)" if selected else "url(#quiet)", 12, "#efb24f" if selected else "#ffffff", .9))
        p.append(t(312, y + 22, name, 12, "#30303a", 570))
        p.append(t(312, y + 41, desc, 10, "#777782", 420))
    p.append(line(570, 247, 570, 833))
    p.append(t(602, 263, "两个整数相加", 22, "#2b2b34", 650))
    p.append(t(602, 290, "将两个整数相加并返回结构化结果。", 12, "#6f6f7a", 420))
    p.append(badge(602, 321, "完成", "good"))
    p.append(t(699, 321, "示例 MCP · 刚刚", 11, "#74747f", 420))
    p.append(line(602, 345, 1309, 345))
    p.append(section_title(602, 387, "运行结果", "成功 · 结构化输出"))
    p.append(button(1190, 361, 119, "复制结果", "check", False, h=40))
    p.append(r(602, 411, 707, 240, "url(#inset)", 12, "#ffffff", .72))
    for i, value in enumerate(['{', '  "sum": 42', '}']):
        p.append(t(625, 450 + i * 30, value, 13, "#41414b", 460))
    p.append(t(602, 697, "文件预览、在访达中显示和复制只在结果内容支持时出现。", 11, "#73737e", 420))
    p.append(button(602, 736, 160, "再次运行", "play", True, h=44))
    p.append(button(775, 736, 147, "查看活动记录", "history", False, h=44))
    save("16-result-success", p)


def board_connection_home():
    p = shell("示例 Git CLI", "示例 Git CLI", global_search=True, subtitle="连接首页按来源展示命令、工具、资源与提示")
    p.append(badge(299, 184, "已连接", "good"))
    p.append(t(385, 184, "CLI 程序 · 1 项功能", 12, "#6f6f7a", 420))
    p.append(button(1155, 157, 154, "刷新能力", "refresh", False, h=40))
    p.append(line(299, 211, 1309, 211))
    p.append(section_title(299, 254, "命令与动作", "此连接提供 1 项功能"))
    p.append(r(299, 284, 252, 64, "url(#glass)", 11, "#efb24b", .88))
    p.append(t(314, 309, "查看 Git 状态", 13, "#33333d", 570))
    p.append(t(314, 331, "以预览结果演示 CLI 动作", 10, "#74747f", 420))
    p.append(line(575, 234, 575, 830))
    p.append(t(606, 254, "查看 Git 状态", 21, "#2b2b34", 650))
    p.append(t(606, 282, "以预览结果演示 CLI 动作 · git · 预览", 12, "#6f6f7a", 420))
    p.append(badge(606, 316, "只读 · 预览数据", "good"))
    p.append(line(606, 337, 1309, 337))
    p.append(section_title(606, 376, "参数"))
    p.append(t(606, 410, "此动作没有可编辑的输入参数。", 12, "#6f6f7a", 440))
    p.append(button(1118, 432, 191, "运行  ⌘ ↵", "play", True, h=46))
    p.append(line(606, 510, 1309, 510))
    p.append(section_title(606, 549, "运行结果", "预览数据 · 最近一次调用"))
    p.append(r(606, 573, 703, 142, "url(#inset)", 11, "#ffffff", .7))
    p.append(t(628, 608, "预览结果：工作区干净", 13, "#41414b", 470))
    p.append(t(628, 637, "状态、复制与文件操作由实际返回内容决定。", 11, "#777782", 420))
    save("17-connection-home", p)


def board_mini_player():
    p = shell("所有功能", "所有功能", global_search=False, subtitle="搜索所有连接中的功能 · 预览数据", mini_player=True)
    p.append(r(298, 174, 600, 42, "url(#inset)", 10, "#ffffff"))
    p.append(glyph(316, 185, "search", size=16))
    p.append(t(339, 201, "搜索名称、说明或来源", 13, "#777782", 420))
    p.append(t(878, 201, "⌘ K", 11, "#787883", 500, "end"))
    x = 298
    for label, selected, width in [("全部", True, 72), ("CLI", False, 62), ("MCP 工具", False, 98), ("资源", False, 68), ("提示", False, 68)]:
        p.append(pill(x, 229, label, selected, width))
        x += width + 10
    p.append(section_title(298, 292, "功能目录"))
    p.append(t(643, 292, "12 项", 11, "#777782", 420, "end"))
    p.append(line(642, 276, 642, 776))
    mini_rows = [
        ("查看 Git 状态", "CLI · 示例 Git CLI", "terminal"),
        ("读取项目说明", "资源 · 示例 MCP", "folder"),
        ("两个整数相加", "MCP 工具 · 示例 MCP", "play"),
        ("搜索歌曲", "CLI · 示例网易云音乐", "music"),
        ("继续播放", "CLI · 示例网易云音乐", "play"),
    ]
    for i, (title, source, icon) in enumerate(mini_rows):
        y = 317 + i * 65
        p.append(r(298, y, 344, 56, "url(#quiet)", 12, "#ffffff", .55))
        p.append(glyph(310, y + 16, icon, size=22))
        p.append(t(333, y + 23, title, 13, "#30303a", 590))
        p.append(t(333, y + 43, source, 10, "#777782", 420))
    p.append(t(689, 520, "从目录选择功能，查看参数、权限和运行结果。", 13, "#777782", 420, "middle"))
    p.append(line(52, 786, 1344, 786))
    p.append(r(52, 788, 1292, 96, "url(#glass)", 0, "#ffffff", .86))
    p.append(glyph(87, 826, "music", size=22))
    p.append(t(123, 829, "示例歌曲", 13, "#34343d", 580))
    p.append(t(123, 850, "声音由此设备输出 · 示例网易云音乐 · 示例歌手 · 0:12 / 3:20", 10, "#74747f", 420))
    p.append(icon_button(1080, 809, "pause", "暂停播放", True, size=48))
    p.append(icon_button(1130, 813, "stop", "停止播放", size=46))
    p.append(icon_button(1180, 813, "refresh", "刷新播放状态", size=46))
    p.append(icon_button(1230, 809, "open", "打开播放器", size=48))
    p.append(icon_button(1282, 809, "close", "收起迷你播放器", size=48))
    save("18-mini-player", p)


def board_target_selector():
    p = shell("管理连接", "管理连接", global_search=True, subtitle="添加前先确认连接应运行在哪个设备")
    p.append(r(299, 177, 1010, 640, "url(#quiet)", 14, "#ffffff", .38))
    p.append('<rect x="263" y="58" width="1081" height="826" fill="#25252b" fill-opacity=".20"/>')
    p.append('<rect x="467" y="244" width="585" height="390" rx="18" fill="#696873" fill-opacity=".13"/>')
    p.append('<rect x="464" y="240" width="585" height="390" rx="18" fill="url(#glass)" stroke="#ffffff" stroke-width="1.5"/>')
    p.append(t(500, 285, "先选择执行设备", 20, "#2b2b34", 650))
    p.append(t(500, 309, "连接配置会保存到选中的设备。", 12, "#70707b", 420))
    p.append(line(500, 330, 1013, 330))
    p.append(r(500, 352, 513, 76, "url(#glass)", 12, "#efb24f", .94))
    p.append(glyph(520, 374, "settings", size=22))
    p.append(t(557, 382, "此 Mac", 14, "#35353f", 560))
    p.append(t(557, 405, "本机运行端 · 可配置 CLI 和 MCP", 10, "#777782", 420))
    p.append(badge(927, 391, "可用", "good"))
    p.append(r(500, 438, 513, 76, "url(#quiet)", 12, "#ffffff", .48))
    p.append(glyph(520, 460, "link", size=22))
    p.append(t(557, 468, "已配对 Mac Host", 14, "#35353f", 560))
    p.append(t(557, 491, "仅在 Host 在线且该设备有连接向导权限时可选", 10, "#777782", 420))
    p.append(badge(902, 477, "状态依设备而定", "neutral"))
    p.append(line(500, 544, 1013, 544))
    p.append(button(500, 566, 112, "取消", "close", False, quiet=True, h=42))
    p.append(t(1013, 594, "选择后进入连接类型步骤", 11, "#777782", 420, "end"))
    save("19-target-selector", p)


def board_host_permissions():
    p = shell("设置", "设置", global_search=True, subtitle="设备授权可按功能范围和单个连接细分")
    p.append(r(299, 177, 1010, 642, "url(#quiet)", 14, "#ffffff", .38))
    p.append('<rect x="263" y="58" width="1081" height="826" fill="#25252b" fill-opacity=".20"/>')
    p.append('<rect x="426" y="112" width="658" height="720" rx="18" fill="#696873" fill-opacity=".13"/>')
    p.append('<rect x="423" y="108" width="658" height="720" rx="18" fill="url(#glass)" stroke="#ffffff" stroke-width="1.5"/>')
    p.append(t(460, 151, "配置设备权限", 20, "#2b2b34", 650))
    p.append(t(460, 174, "LGE AN10 · 已配对设备", 11, "#777782", 420))
    p.append(line(460, 193, 1044, 193))
    p.append(section_title(460, 228, "设备可执行的功能范围"))
    scopes = [
        ("读取连接", "必需；未设单连接规则时可读取所有连接。", True),
        ("连接向导", "检测、测试和保存 Mac 上的连接。", True),
        ("连接管理", "删除或排序连接；动作清单写入仍受连接权限约束。", False),
        ("音乐账号", "查看账号状态、登录或退出。", False),
        ("终端", "打开并交互操作 Mac CLI 终端。", False),
        ("清理活动", "清除 Mac 上的运行活动记录。", False),
    ]
    for i, (label, detail, checked) in enumerate(scopes):
        y = 254 + i * 52
        p.append(f'<rect x="461" y="{y-15}" width="16" height="16" rx="4" fill="{"#e9a63e" if checked else "#f8f8fa"}" stroke="{"#e9a63e" if checked else "#c6c6ce"}"/>')
        if checked:
            p.append(f'<path d="M465 {y-7}l4 4 6-8" fill="none" stroke="#ffffff" stroke-width="1.6"/>')
        p.append(t(488, y, label, 12, "#383842", 520))
        p.append(t(603, y, detail, 10, "#74747f", 420))
    p.append(line(460, 576, 1044, 576))
    p.append(section_title(460, 610, "逐连接权限", "控制或外部写入会同时包含读取权限"))
    p.append(r(460, 641, 584, 112, "url(#quiet)", 10, "#ffffff", .58))
    p.append(t(480, 669, "示例 Git CLI", 13, "#34343d", 560))
    for i, (label, selected) in enumerate([("读取", True), ("本机控制", True), ("外部写入", False)]):
        p.append(pill(480 + i * 129, 685, label, selected, 116))
    p.append(line(460, 775, 1044, 775))
    p.append(button(795, 791, 111, "取消", "close", False, quiet=True, h=40))
    p.append(button(916, 791, 128, "保存权限", "check", True, h=40))
    save("20-host-permissions", p)


def board_mcp_home():
    p = shell("示例 MCP", "示例 MCP", global_search=True, subtitle="MCP 按工具、资源和提示分组")
    p.append(badge(299, 184, "已连接", "good"))
    p.append(t(385, 184, "HTTP MCP · 3 项能力", 12, "#6f6f7a", 420))
    p.append(button(1155, 157, 154, "刷新能力", "refresh", False, h=40))
    p.append(line(299, 211, 1309, 211))
    p.append(section_title(299, 252, "工具"))
    for i, (name, detail, selected) in enumerate([
        ("两个整数相加", "只读", True),
    ]):
        y = 272 + i * 57
        p.append(r(299, y, 254, 48, "url(#glass)" if selected else "url(#quiet)", 10, "#efb24f" if selected else "#ffffff", .88 if selected else .48))
        p.append(t(312, y + 20, name, 12, "#34343d", 560))
        p.append(t(312, y + 38, detail, 10, "#777782", 420))
    p.append(section_title(299, 466, "资源"))
    p.append(t(312, 494, "读取项目说明", 12, "#4c4c56", 470))
    p.append(t(312, 514, "资源阅读器预览样本", 10, "#777782", 420))
    p.append(section_title(299, 612, "提示"))
    p.append(t(312, 642, "生成摘要提示", 12, "#4c4c56", 470))
    p.append(t(312, 662, "必填 · 字符串", 10, "#777782", 420))
    p.append(line(575, 234, 575, 830))
    p.append(t(606, 252, "两个整数相加", 21, "#2b2b34", 650))
    p.append(t(606, 280, "以预览结果演示 MCP 工具与结构化输出。", 12, "#6f6f7a", 420))
    p.append(badge(606, 315, "示例 MCP · 预览数据", "good"))
    p.append(line(606, 338, 1309, 338))
    p.append(section_title(606, 375, "输入参数"))
    p.append(field(606, 409, 329, "第一个整数", "12"))
    p.append(field(960, 409, 349, "第二个整数", "30"))
    p.append(t(606, 486, "必填和类型检查由 MCP schema 提供；资源与提示按各自内容展示。", 11, "#777782", 420))
    p.append(button(1121, 512, 188, "运行  ⌘ ↵", "play", True, h=46))
    p.append(line(606, 585, 1309, 585))
    p.append(section_title(606, 624, "运行结果"))
    p.append(r(606, 650, 703, 138, "url(#inset)", 11, "#ffffff", .7))
    p.append(t(628, 686, '{"sum": 42}', 12, "#585863", 450))
    p.append(t(628, 714, "打开资源时显示读取内容；提示先生成参数表单，不直接执行。", 11, "#777782", 420))
    save("21-mcp-home", p)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    board_workspace()
    board_music()
    board_connections()
    board_activity()
    board_settings()
    board_host()
    board_setup()
    board_run_terminal()
    board_permission()
    board_states()
    board_button_states()
    board_dark_reference()
    board_action_editor()
    board_music_account()
    board_settings_shortcuts()
    board_settings_local_data()
    board_result_success()
    board_connection_home()
    board_mini_player()
    board_target_selector()
    board_host_permissions()
    board_mcp_home()
