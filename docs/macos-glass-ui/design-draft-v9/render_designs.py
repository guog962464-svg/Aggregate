#!/usr/bin/env python3
"""Generate the reviewable, fixed-size SVG screens for Aggregate design v9."""

from html import escape
import base64
from pathlib import Path
import re

OUT = Path(__file__).resolve().parent
W, H = 1360, 900
SWITCH_REFERENCE = base64.b64encode(
    (OUT / "glass-theme-switch-light.png").read_bytes()
).decode("ascii")
APP_ROOT = OUT.parents[2]
GLYPH_TOKENS = (APP_ROOT / "app/lib/widgets/glass/glass_design_tokens.dart").read_text(
    encoding="utf-8"
)
GLYPH_PITCH = float(re.search(r"glyphPitch = ([0-9.]+);", GLYPH_TOKENS).group(1))
GLYPH_CELL_SIZE = float(
    re.search(r"glyphCellSize = ([0-9.]+);", GLYPH_TOKENS).group(1)
)
GLYPH_CORNER_RADIUS = float(
    re.search(r"glyphCornerRadius = ([0-9.]+);", GLYPH_TOKENS).group(1)
)
GLYPH_FEATHER = float(re.search(r"glyphFeather = ([0-9.]+);", GLYPH_TOKENS).group(1))
GLYPH_OUTER_HALO = float(
    re.search(r"glyphOuterHalo = ([0-9.]+);", GLYPH_TOKENS).group(1)
)
GLYPH_HALO_ALPHA = float(
    re.search(r"glyphHaloAlpha = ([0-9.]+);", GLYPH_TOKENS).group(1)
)

LIGHT = {
    "scene0":"#d9d8d5", "scene1":"#deddd9", "scene2":"#f3f1ec", "warm":"#a95f1e",
    "warmEdge":"#ffc66b", "ink":"#2b2a27", "muted":"#686761", "line":"#c1bfba",
    "glyph":"#5d574b", "panelTop":"#f8f7f3", "panelBottom":"#e5e3de", "panelEdge":"#f4f2ed",
    "edgeStrong":"#fbfaf6", "shadow":"#4c4942", "inset":"#d0cec8", "insetEdge":"#bebcb6",
    "good":"#3e7158", "danger":"#a24640", "dangerInk":"#a24640",
}
DARK = {
    "scene0":"#191a1b", "scene1":"#222325", "scene2":"#333436", "warm":"#d28a3d",
    "warmEdge":"#f2bd70", "ink":"#f0efeb", "muted":"#b4b1aa", "line":"#41413f",
    "glyph":"#dfd5c1", "panelTop":"#383a3b", "panelBottom":"#292a2c", "panelEdge":"#51514e",
    "edgeStrong":"#62615d", "shadow":"#080909", "inset":"#161718", "insetEdge":"#424240",
    "good":"#9dc7aa", "danger":"#e5948c", "dangerInk":"#e5948c",
}

RENDER_GLYPH_ENUMS = {
    "back": "arrowBack",
    "connection": "network",
    "error": "error",
    "history": "activity",
    "hourglass": "hourglass",
    "inbox": "inbox",
    "info": "info",
    "lock": "lock",
    "moon": "appearance",
    "spark": "flash",
    "sun": "brightness",
}


def load_flutter_glyphs():
    """Use the production dot masks so design boards cannot drift from Flutter."""
    source_path = OUT.parents[2] / "app/lib/widgets/glass/glass_glyph.dart"
    source = source_path.read_text(encoding="utf-8")
    rows = {
        match.group(1): tuple(re.findall(r"'([01]{9})'", match.group(2)))
        for match in re.finditer(
            r"static const (\w+) = \[([^\]]+)\];", source, re.DOTALL
        )
    }
    rows = {name: pattern for name, pattern in rows.items() if len(pattern) == 9}

    resolver_source = source[
        source.index("List<String> _rowsFor") : source.index("abstract final class _GlyphRows")
    ]
    enum_to_rows = {}
    for match in re.finditer(
        r"((?:GlassGlyph\.\w+(?:\s*\|\|\s*GlassGlyph\.\w+)*)\s*=>\s*_GlyphRows\.(\w+))",
        resolver_source,
    ):
        for enum_name in re.findall(r"GlassGlyph\.(\w+)", match.group(1)):
            enum_to_rows[enum_name] = match.group(2)

    glyphs = {}
    # These are the symbols used by the layouts and fixture data below.
    renderer_names = set(RENDER_GLYPH_ENUMS) | {
        "play", "pause", "next", "previous", "plus", "stop", "copy", "playlist",
        "grid", "chat", "device", "terminal", "check", "close", "folder", "trash",
        "visibility", "desktop", "build",
        "error", "hourglass", "inbox", "info",
        "star", "document", "filter", "expand", "music", "settings", "search", "refresh",
    }
    for renderer_name in renderer_names:
        enum_name = RENDER_GLYPH_ENUMS.get(renderer_name, renderer_name)
        row_name = enum_to_rows.get(enum_name)
        if row_name is None or row_name not in rows:
            raise KeyError(f"No Flutter dot mask for renderer glyph {renderer_name!r}")
        glyphs[renderer_name] = rows[row_name]
    invalid = {
        name: pattern
        for name, pattern in glyphs.items()
        if len(pattern) != 9
        or any(len(row) != 9 or set(row) - {"0", "1"} for row in pattern)
    }
    if invalid:
        raise ValueError(f"Glyph masks must be 9x9 binary grids: {sorted(invalid)}")
    return glyphs


GLYPHS = load_flutter_glyphs()

# These three high-frequency marks are deliberately redrawn in the design
# system rather than copied from the earlier draft. They keep its 9x9 dot
# grammar, but use a clearer silhouette at action-button sizes.
GLYPHS["play"] = (
    "000000000",
    "001000000",
    "001100000",
    "001110000",
    "001111100",
    "001110000",
    "001100000",
    "001000000",
    "000000000",
)
GLYPHS["refresh"] = (
    "000111000",
    "001000110",
    "010000010",
    "010000010",
    "010000010",
    "001000100",
    "000111000",
    "000000000",
    "000000000",
)
GLYPHS["search"] = (
    "000111000",
    "001000100",
    "010000010",
    "010000010",
    "010000010",
    "001000110",
    "000111100",
    "000000110",
    "000000011",
)


def txt(x, y, value, size=14, color="var(--ink)", weight=450, anchor="start"):
    return (f'<text x="{x}" y="{y}" text-anchor="{anchor}" '
            f'font-family="-apple-system,BlinkMacSystemFont,PingFang SC,sans-serif" '
            f'font-size="{size}" font-weight="{weight}" fill="{color}">{escape(str(value))}</text>')


def rect(x, y, w, h, fill="url(#panel)", r=14, stroke="url(#edge)", sw=1):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')


def line(x1, y1, x2, y2, color="var(--line)", width=1, opacity=1):
    return f'<path d="M{x1} {y1}H{x2}" fill="none" stroke="{color}" stroke-opacity="{opacity}" stroke-width="{width}"/>'


def glyph(kind, x, y, size=20, color="var(--glyph)"):
    grid = GLYPHS[kind]
    scale = size / 32
    half_cell = GLYPH_CELL_SIZE / 2
    halo_inset = GLYPH_FEATHER + GLYPH_OUTER_HALO
    halo_radius = min(
        half_cell,
        GLYPH_CORNER_RADIUS + GLYPH_FEATHER + GLYPH_OUTER_HALO,
    )
    halo_shapes = []
    core_shapes = []
    for row, bits in enumerate(grid):
        for col, bit in enumerate(bits):
            if bit == "1":
                cx = 4 + col * GLYPH_PITCH
                cy = 4 + row * GLYPH_PITCH
                halo_shapes.append(
                    f'<rect x="{cx-half_cell-halo_inset:.2f}" '
                    f'y="{cy-half_cell-halo_inset:.2f}" '
                    f'width="{GLYPH_CELL_SIZE+2*halo_inset:.2f}" '
                    f'height="{GLYPH_CELL_SIZE+2*halo_inset:.2f}" '
                    f'rx="{halo_radius:.2f}" fill="{color}"/>'
                )
                core_shapes.append(
                    f'<rect x="{cx-half_cell:.2f}" y="{cy-half_cell:.2f}" '
                    f'width="{GLYPH_CELL_SIZE:.2f}" height="{GLYPH_CELL_SIZE:.2f}" '
                    f'rx="{GLYPH_CORNER_RADIUS:.2f}" fill="{color}"/>'
                )
    return (
        f'<g transform="translate({x} {y}) scale({scale:.5f})">'
        f'<g fill-opacity="{GLYPH_HALO_ALPHA:.2f}" filter="url(#glyphHalo)">'
        f'{"".join(halo_shapes)}</g>'
        f'{"".join(core_shapes)}</g>'
    )


def button(x, y, w, label, icon=None, primary=False, selected=False, danger=False, h=42, icon_only=False, pressed=False, disabled=False, navigation=False):
    kind = "danger" if danger else "primary" if primary or selected else "quiet"
    if navigation:
        radius = 11
    elif h == 32:
        radius = 10
    elif h == 40 and w >= 280:
        radius = 12
    elif h == 72:
        radius = 12
    elif h == 58 or h >= 96:
        radius = 22
    elif primary:
        radius = 14
    elif icon_only:
        radius = 14
    else:
        radius = 13
    is_lit = (primary or selected) and not navigation and not disabled
    opacity = ".48" if disabled else "1"
    out = [f'<g transform="translate({x} {y})" class="button-{kind}" opacity="{opacity}">']
    if navigation and not selected and not pressed:
        # Navigation reads as a quiet list. The active destination alone gets
        # a shallow glass landing, so the rail does not become a stack of cards.
        pass
    else:
        shadow_y, shadow_alpha = (1.2, ".075") if pressed else (2.4, ".15" if is_lit else ".105")
        out.append(f'<rect x="1" y="{shadow_y}" width="{w-1}" height="{h}" rx="{radius}" fill="var(--shadow)" opacity="{shadow_alpha}" filter="url(#softShadow)"/>')
        face_y = 1 if pressed else .5
        edge_alpha = ".66" if navigation and not selected else ".88"
        out.append(f'<rect x="0.5" y="{face_y}" width="{w-1}" height="{h-1}" rx="{radius}" fill="url(#buttonFace)" stroke="var(--edgeStrong)" stroke-opacity="{edge_alpha}" stroke-width="1"/>')
        if is_lit:
            out.append(f'<rect x="1" y="1" width="{w-2}" height="{h-2}" rx="{max(10,radius-1)}" fill="url(#warmSurface)" opacity=".34"/>')
            out.append(f'<ellipse cx="{w-12}" cy="4" rx="{max(11,w*.22):.1f}" ry="{max(7,h*.20):.1f}" fill="var(--warmEdge)" opacity=".22" filter="url(#blurGlow)"/>')
        # A curved, narrow specular edge echoes the theme switch's glass lip.
        # It replaces the old flat gold dash that made controls look stamped.
        out.append(f'<path d="M{min(12,w*.40)} 1 H{w*.56:.1f} C{w*.67:.1f} 1 {w*.70:.1f} {h*.05:.1f} {w*.78:.1f} {h*.05:.1f}" stroke="white" stroke-opacity=".57" stroke-width="1" fill="none"/>')
        if is_lit:
            out.append(f'<path d="M{w*.52:.1f} 1 C{w*.70:.1f} -1 {w-2:.1f} {h*.02:.1f} {w-2:.1f} {h*.32:.1f}" stroke="var(--warmEdge)" stroke-opacity=".88" stroke-width="1.3" fill="none"/>')
        if selected and navigation:
            out.append(f'<path d="M1 {radius} Q1 1 {radius} 1 V{h-1}" stroke="var(--warmEdge)" stroke-opacity=".75" stroke-width="1.4" fill="none"/>')
    if danger:
        out.append(f'<path d="M{w-25} 1 C{w-14} 1 {w-1} 3 {w-1} 14" stroke="var(--danger)" stroke-opacity=".62" stroke-width="1.2" fill="none"/>')
    if pressed:
        out.append(f'<path d="M{radius} {h-2} H{w-radius}" stroke="var(--line)" stroke-opacity=".42" stroke-width="1"/>')
    if icon:
        if navigation:
            isize, ix, iy = 16, 12, (h-16)/2
        elif icon_only:
            isize = 44 if h >= 72 else 22
            ix, iy = (w-isize)/2, (h-isize)/2
        elif h <= 34:
            ix, iy, isize = 12, (h-18)/2, 18
        else:
            isize = 24 if primary and h >= 40 else 22
            ix, iy = 14, (h-isize)/2
        out.append(glyph(icon, ix, iy, isize, "var(--dangerInk)" if danger else "var(--glyph)"))
        # Each familiar action gets a restrained point of light in a different
        # place: the play tip, the refresh arrow, or the search lens.
        if icon == "play":
            out.append(f'<circle cx="{ix+isize*.78:.1f}" cy="{iy+isize*.50:.1f}" r="{max(1.2,isize*.035):.1f}" fill="var(--warmEdge)" opacity=".72" filter="url(#glyphHalo)"/>')
        elif icon == "refresh":
            out.append(f'<circle cx="{ix+isize*.77:.1f}" cy="{iy+isize*.25:.1f}" r="{max(1.1,isize*.032):.1f}" fill="var(--warmEdge)" opacity=".72" filter="url(#glyphHalo)"/>')
        elif icon == "search":
            out.append(f'<circle cx="{ix+isize*.35:.1f}" cy="{iy+isize*.35:.1f}" r="{max(1.1,isize*.032):.1f}" fill="white" opacity=".82" filter="url(#glyphHalo)"/>')
    if label and not icon_only:
        label_x = 36 if navigation or icon and h <= 34 else 44 if icon else 16
        label_size = 13 if navigation else 12 if h == 32 or (h == 40 and w >= 280) else 13
        label_y = h/2 if h == 32 else h/2+3 if navigation else h/2+5
        out.append(txt(label_x, label_y, label, label_size, "var(--ink)", 600 if primary or selected else 510))
    out.append('</g>')
    return "".join(out)


def field(x, y, w, label, value, h=44, icon=None):
    out = [rect(x, y, w, h, "url(#inset)", 12, "var(--insetEdge)")]
    if label:
        out.append(txt(x+14, y+15, label, 10, "var(--muted)", 520))
        out.append(txt(x+14, y+34, value, 13, "var(--ink)", 480))
    else:
        if icon:
            out.append(glyph(icon, x+13, y+(h-18)/2, 18, "var(--muted)"))
        out.append(txt(x+(icon and 42 or 14), y+h/2+5, value, 13, "var(--muted)", 440))
    return "".join(out)


def tag(x, y, label, color="good"):
    c = {"good":"var(--good)", "warn":"var(--warmEdge)", "danger":"var(--danger)"}.get(color, "var(--muted)")
    return f'<circle cx="{x+4}" cy="{y-4}" r="3" fill="{c}"/>' + txt(x+13, y, label, 11, c, 520)


def mini_player(p, fixture="preview"):
    x, y, w, h = 270, 812, 1048, 58
    p.append(rect(x, y, w, h, "url(#panel)", 15, "var(--panelEdge)"))
    p.append(glyph("music", x + 20, y + 18, 22))
    p.append(txt(x + 52, y + 24, "示例歌曲", 13, "var(--ink)", 570))
    connection = "示例网易云音乐" if fixture == "inspection" else "示例网易云音乐"
    p.append(txt(x + 52, y + 39, f"{connection} · 示例歌手 · 0:12 / 3:20", 10, "var(--muted)", 430))
    controls = ("previous", "pause", "next", "stop", "refresh", "expand", "close")
    right = x + w - 14
    for index, icon in enumerate(controls):
        left = right - 46 * (len(controls) - index) - 4 * (len(controls) - index - 1)
        p.append(button(left, y + 6, 46, "", icon, primary=icon == "pause", h=46, icon_only=True))


def target_status(p, x, y, label="此设备"):
    p.append(rect(x,y,142,40,"url(#panel)",14,"var(--panelEdge)"))
    p.append(glyph("device",x+12,y+10,18))
    p.append(txt(x+40,y+25,label,12,"var(--ink)",520))


def defs(dark=False):
    if dark:
        vars_ = """
        --scene0:#191a1b; --scene1:#222325; --scene2:#333436; --warm:#d28a3d;
        --warmEdge:#f2bd70; --ink:#f0efeb; --muted:#b4b1aa; --line:#41413f;
        --glyph:#dfd5c1; --panelTop:#383a3b; --panelBottom:#292a2c; --panelEdge:#51514e;
        --edgeStrong:#62615d; --shadow:#080909; --inset:#161718; --insetEdge:#424240;
        --good:#9dc7aa; --danger:#e5948c; --dangerInk:#e5948c;
        """
    else:
        vars_ = """
        --scene0:#d9d8d5; --scene1:#deddd9; --scene2:#f3f1ec; --warm:#a95f1e;
        --warmEdge:#ffc66b; --ink:#2b2a27; --muted:#686761; --line:#c1bfba;
        --glyph:#5d574b; --panelTop:#f8f7f3; --panelBottom:#e5e3de; --panelEdge:#f4f2ed;
        --edgeStrong:#fbfaf6; --shadow:#4c4942; --inset:#d0cec8; --insetEdge:#bebcb6;
        --good:#35735b; --danger:#a24640; --dangerInk:#a24640;
        """
    dots = []
    seed = 91731 if dark else 24679
    for index in range(256):
        seed = (1103515245 * seed + 12345) & 0x7fffffff
        cx = (seed % 12800) / 100
        seed = (1103515245 * seed + 12345) & 0x7fffffff
        cy = (seed % 12800) / 100
        radius = .24 + (seed % 30) / 100
        color = "#ffffff" if index % 2 else "#1b1b22"
        dots.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{radius:.2f}" fill="{color}" fill-opacity=".13"/>')
    grain_pattern = "".join(dots)
    return f"""
    <defs>
      <linearGradient id="scene" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--scene0)"/><stop offset="1" stop-color="var(--scene1)"/></linearGradient>
      <radialGradient id="skyGlow" cx=".78" cy=".08" r="1.15"><stop offset="0" stop-color="var(--scene2)" stop-opacity=".43"/><stop offset=".52" stop-color="var(--scene2)" stop-opacity=".13"/><stop offset="1" stop-color="var(--scene2)" stop-opacity="0"/></radialGradient>
      <pattern id="sceneGrain" width="128" height="128" patternUnits="userSpaceOnUse">{grain_pattern}</pattern>
      <linearGradient id="panel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--panelTop)" stop-opacity=".76"/><stop offset=".46" stop-color="var(--panelTop)" stop-opacity=".65"/><stop offset="1" stop-color="var(--panelBottom)" stop-opacity=".78"/></linearGradient>
      <linearGradient id="dialogPanel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--panelTop)" stop-opacity=".98"/><stop offset=".46" stop-color="var(--panelTop)" stop-opacity=".95"/><stop offset="1" stop-color="var(--panelBottom)" stop-opacity=".96"/></linearGradient>
      <linearGradient id="buttonFace" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--panelTop)" stop-opacity=".87"/><stop offset=".52" stop-color="var(--panelTop)" stop-opacity=".68"/><stop offset="1" stop-color="var(--panelBottom)" stop-opacity=".82"/></linearGradient>
      <linearGradient id="inset" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--inset)"/><stop offset="1" stop-color="var(--scene0)"/></linearGradient>
      <filter id="glyphHalo" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation=".28"/></filter>
      <radialGradient id="warmSurface" cx="1" cy="0" r=".9"><stop offset="0" stop-color="var(--warmEdge)" stop-opacity=".44"/><stop offset=".30" stop-color="var(--warm)" stop-opacity=".13"/><stop offset="1" stop-color="var(--warm)" stop-opacity="0"/></radialGradient>
      <linearGradient id="warmGlow" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--warmEdge)" stop-opacity=".50"/><stop offset=".52" stop-color="var(--warm)" stop-opacity=".18"/><stop offset="1" stop-color="var(--warm)" stop-opacity="0"/></linearGradient>
      <filter id="softShadow" x="-25%" y="-25%" width="150%" height="170%"><feGaussianBlur stdDeviation="2.8"/></filter>
      <filter id="blurGlow" x="-40%" y="-50%" width="180%" height="200%"><feGaussianBlur stdDeviation="5"/></filter>
      <clipPath id="windowClip"><rect x="0" y="0" width="1360" height="900" rx="14"/></clipPath>
      <style>:root {{{vars_}}} text {{font-synthesis:none}} .button-primary {{}} .button-danger {{}}</style>
    </defs>
    """


def shell(title, active="全部功能", subtitle=None, dark=False, search=True, mini=False, fixture="preview"):
    p = ['<svg xmlns="http://www.w3.org/2000/svg" width="1360" height="900" viewBox="0 0 1360 900">', defs(dark)]
    p.append('<g clip-path="url(#windowClip)"><rect x="0" y="0" width="1360" height="900" fill="url(#scene)"/><rect x="0" y="0" width="1360" height="900" fill="url(#skyGlow)"/><rect x="0" y="0" width="1360" height="900" fill="url(#sceneGrain)" opacity=".42"/>')
    # macOS contributes a 32 pt native titlebar above Flutter's 40 pt AppBar.
    # The two regions form a 72 pt toolbar band in a 1360x900 window.
    p.append('<rect x="0" y="0" width="1360" height="72" fill="var(--panelBottom)" opacity=".30"/><path d="M0 72H1360M240 72V900" stroke="var(--line)" stroke-opacity=".72"/>')
    for x, c in ((16,"#f26a5f"),(34,"#f0c34d"),(52,"#49bd6c")):
        p.append(f'<circle cx="{x}" cy="16" r="7" fill="{c}"/>')
    p.append(txt(84,17,"Aggregate",13,"var(--muted)",620))
    p.append(glyph("connection",42,85,17))
    p.append(txt(67,103,"Aggregate",19,"var(--ink)",680))
    p.append(txt(40,155,"我的连接",11,"var(--muted)",560))
    p.append(button(186,136,38,"","plus",h=38,icon_only=True))
    connections = (
        (("示例 Git CLI", "terminal"), ("示例 MCP", "connection"), ("示例网易云音乐", "music"))
        if fixture == "inspection"
        else (("示例网易云音乐", "music"), ("示例 Git CLI", "terminal"), ("示例 MCP", "connection"))
    )
    for i, (label, icon) in enumerate(connections):
        y=186+i*49
        p.append(button(32,y,192,label,icon,selected=active==label,h=40,navigation=True))
        status_x = 32 + 36 + min(112, len(label) * 6.4) + 10
        p.append(f'<circle cx="{status_x:.1f}" cy="{y+20}" r="2.5" fill="var(--good)"/>')
    p.append(line(32,354,224,354))
    for i,(label,icon) in enumerate((("所有功能","search"),("管理连接","connection"),("活动","history"))):
        y=374+i*47
        p.append(button(32,y,192,label,icon,selected=active==label,h=38,navigation=True))
    settings_y = 718 if mini else 807
    p.append(button(32,settings_y,192,"设置","settings",selected=active=="设置",h=38,navigation=True))
    p.append(tag(41,772 if mini else 870,"本机工作空间"))
    if search:
        # Match the production toolbar action: 29% width clamped to 360 pt,
        # right-aligned with a 24 pt window inset and centered in the 40 pt bar.
        p.append(button(976,32,360,"搜索功能…","search",h=40))
        p.append(txt(1324,57,"⌘ K",12,"var(--muted)",520,"end"))
    p.append(txt(280,131,title,25,"var(--ink)",690))
    if subtitle:
        p.append(txt(281,157,subtitle,12,"var(--muted)",440))
    if mini:
        mini_player(p, fixture=fixture)
    return p


def heading(p, x, y, name, hint=None):
    p.append(txt(x,y,name,16,"var(--ink)",650))
    if hint: p.append(txt(x,y+21,hint,11,"var(--muted)",430))


def small_button(p, x, y, label, icon=None, primary=False, danger=False, w=None):
    w = w or max(86, len(label)*14+44)
    p.append(button(x,y,w,label,icon,primary=primary,danger=danger,h=46 if primary else 40))


def row(p, x, y, w, title, sub, icon="document", selected=False, right=None, height=56):
    if selected:
        p.append(f'<rect x="{x}" y="{y+1}" width="{w}" height="{height-2}" rx="12" fill="var(--shadow)" opacity=".08" filter="url(#softShadow)"/>')
        p.append(rect(x,y,w,height,"url(#buttonFace)",12,"var(--edgeStrong)",.9))
        p.append(f'<rect x="{x+1}" y="{y+8}" width="2" height="{height-16}" rx="1" fill="var(--warmEdge)" opacity=".82"/>')
        p.append(f'<ellipse cx="{x+w-10}" cy="{y+4}" rx="{min(46,w*.16):.1f}" ry="7" fill="var(--warmEdge)" opacity=".12" filter="url(#blurGlow)"/>')
    else:
        p.append(line(x+2,y+height,w+x-2,y+height,"var(--line)",1,.58))
    p.append(glyph(icon,x+13,y+15,19))
    p.append(txt(x+42,y+24,title,13,"var(--ink)",560 if selected else 480))
    if sub: p.append(txt(x+42,y+42,sub,10,"var(--muted)",430))
    if right: p.append(txt(x+w-12,y+24,right,10,"var(--muted)",480,"end"))


UI6_DIRECTORY_ROWS = (
    ("上一首", "CLI · 示例网易云音乐", "previous"),
    ("下一首", "CLI · 示例网易云音乐", "next"),
    ("两个整数相加", "MCP 工具 · 示例 MCP", "spark"),
    ("停止播放", "CLI · 示例网易云音乐", "stop"),
    ("刷新播放状态", "CLI · 示例网易云音乐", "music"),
    ("加入播放队列", "CLI · 示例网易云音乐", "playlist"),
    ("打开预览终端", "CLI · 示例 Git CLI", "terminal"),
    ("搜索歌曲", "CLI · 示例网易云音乐", "music"),
    ("播放歌曲", "CLI · 示例网易云音乐", "play"),
    ("暂停播放", "CLI · 示例网易云音乐", "pause"),
    ("查看 Git 状态", "CLI · 示例 Git CLI", "play"),
    ("演示写入权限确认", "CLI · 示例 Git CLI", "play"),
    ("演示恢复状态", "MCP 工具 · 示例 MCP", "refresh"),
    ("生成摘要提示", "MCP 工具 · 示例 MCP", "spark"),
    ("继续播放", "CLI · 示例网易云音乐", "play"),
    ("编辑 JSON 参数", "MCP 工具 · 示例 MCP", "document"),
    ("读取预览说明", "资源 · 示例 MCP", "folder"),
)


def workspace_directory_header(p, count="12 项", y=302, selected="全部"):
    p.append(txt(280,y,"功能目录",14,"var(--ink)",600))
    p.append(txt(575,y,count,11,"var(--muted)",450,"end"))
    scopes=(("最近使用","history",97),("收藏","star",73),("全部","grid",73))
    x=280
    for label,icon,width in scopes:
        p.append(button(x,y+7,width,label,icon,selected=label==selected,h=32))
        x+=width+3


def workspace_type_filters(p, y=233):
    filters=(("全部","grid",73,True),("CLI","terminal",68,False),("MCP 工具","settings",104,False),("资源","document",73,False),("提示","chat",73,False))
    x=280
    for label,icon,width,selected in filters:
        p.append(button(x,y,width,label,icon,selected=selected,h=32))
        x+=width+9


def screen_workspace():
    # Workspace owns the only visible search field. ⌘K still focuses it from
    # every page, so showing a second toolbar field here would duplicate it.
    # This board uses the same 12-item inspection fixture as the Profile review:
    # Git, MCP, Music connection order and CapabilityCatalog title sorting.
    p=shell(
        "所有功能",
        "所有功能",
        "从一个地方找到并运行 CLI 与 MCP 功能。",
        search=False,
        mini=True,
        fixture="inspection",
    )
    p.append(field(280,178,570,"","搜索名称、说明或来源",42,"search"))
    workspace_type_filters(p)
    workspace_directory_header(p)
    for i,(name,sub,icon) in enumerate((("上一首","CLI · 示例网易云音乐","previous"),("下一首","CLI · 示例网易云音乐","next"),("两个整数相加","MCP 工具 · 示例 MCP","spark"),("停止播放","CLI · 示例网易云音乐","stop"),("刷新播放状态","CLI · 示例网易云音乐","music"),("搜索歌曲","CLI · 示例网易云音乐","music"),("播放歌曲","CLI · 示例网易云音乐","play"))):
        row(p,280,354+i*60,295,name,sub,icon,i==2, "☆",56)
    p.append(line(596,344,596,776,"var(--line)"))
    p.append(txt(624,353,"两个整数相加",20,"var(--ink)",680))
    p.append(tag(624,380,"示例 MCP · 只读"))
    p.append(txt(624,415,"读取两个数字并返回结果",12,"var(--muted)",430))
    heading(p,624,450,"参数","两个字段都会在执行前检查")
    p.append(field(624,486,332,"第一个整数","例如 12"))
    p.append(field(976,486,332,"第二个整数","例如 30"))
    target_status(p,624,547)
    p.append(button(776,544,104,"运行","play",primary=True,h=46))
    p.append(line(624,605,1308,605))
    heading(p,624,638,"运行结果","尚无调用 · 结果仅在本机显示")
    p.append(rect(624,663,684,105,"url(#inset)",12,"var(--insetEdge)"))
    p.append(txt(646,696,"结果会显示在这里",13,"var(--muted)",480))
    p.append(txt(646,722,"结构化输出、复制与文件操作只在结果提供时出现。",11,"var(--muted)",430))
    return p+["</g></svg>"]


def screen_connection_home(mcp=False):
    title="示例 MCP" if mcp else "示例 Git CLI"
    active=title
    p=shell(title,active,"查看当前连接提供的能力与最近结果",mini=True)
    # The connection page exposes its real refresh action in the page header.
    # Keep it separate from the global search in the app toolbar.
    p.append(button(1266,112,46,"","refresh",h=46,icon_only=True))
    heading(p,280,204,"能力目录","选择一项查看详情或填写参数")
    if mcp:
        groups=(("工具",(("两个整数相加","读取两个数字并返回结果","spark"),)),("资源",(("读取项目说明","项目中的 README 文本","folder"),)),("提示",(("生成摘要提示","根据输入生成摘要","document"),)))
        y=240
        for group,items in groups:
            p.append(txt(280,y,group,11,"var(--muted)",600)); y+=13
            for name,sub,icon in items:
                row(p,280,y,306,name,sub,icon,name=="两个整数相加",height=58); y+=64
            y+=16
    else:
        row(p,280,236,306,"查看 Git 状态","显示当前分支与工作区状态","terminal",True,height=60)
    p.append(line(609,204,609,775))
    p.append(txt(642,242,"两个整数相加" if mcp else "查看 Git 状态",20,"var(--ink)",680))
    p.append(tag(642,269,"示例 MCP · 此设备" if mcp else "示例 Git CLI · 此设备"))
    p.append(txt(642,304,"连接参数与结果只显示实际提供的内容。",12,"var(--muted)",440))
    if mcp:
        heading(p,642,352,"参数","来自当前工具输入 schema")
        p.append(field(642,386,320,"第一个整数","例如 12"))
        p.append(field(978,386,320,"第二个整数","例如 30"))
        action_y, result_line_y, result_head_y, result_box_y = 442, 502, 535, 561
    else:
        heading(p,642,352,"运行","此能力无需输入参数")
        p.append(rect(642,384,656,44,"url(#inset)",11,"var(--insetEdge)"))
        p.append(glyph("terminal",658,396,18,"var(--muted)"))
        p.append(txt(686,411,"显示当前分支与工作区状态",12,"var(--muted)",450))
        action_y, result_line_y, result_head_y, result_box_y = 442, 502, 535, 561
    target_status(p,642,action_y+3)
    p.append(button(794,action_y,104,"运行","play",primary=True,h=46))
    p.append(line(642,result_line_y,1298,result_line_y))
    heading(p,642,result_head_y,"最近结果","不会把参数正文写入活动记录")
    p.append(rect(642,result_box_y,656,142,"url(#inset)",12,"var(--insetEdge)"))
    p.append(txt(664,result_box_y+32,"尚无最近结果",13,"var(--muted)",480))
    p.append(txt(664,result_box_y+59,"运行后在此查看输出、状态和可用操作。",11,"var(--muted)",430))
    return p+["</g></svg>"]


def screen_connections():
    p=shell("管理连接","管理连接","查看连接状态、诊断与可执行的管理操作",mini=True,fixture="inspection")
    small_button(p,1160,115,"添加连接","plus",primary=True,w=148)
    heading(p,280,203,"连接列表","选择连接查看详情 · 使用操作调整顺序")
    for i,(name,sub) in enumerate((("示例 Git CLI","CLI 程序 · 本机 · 就绪"),("示例 MCP","远程 MCP · 本机 · 就绪"),("示例网易云音乐","CLI 程序 · 本机 · 就绪"))):
        y=230+i*70
        if i == 0:
            p.append(f'<rect x="281" y="{y+3}" width="283" height="60" rx="12" fill="var(--shadow)" opacity=".08" filter="url(#softShadow)"/>')
            p.append(rect(280,y,285,60,"url(#buttonFace)",12,"var(--edgeStrong)",.9))
            p.append(f'<rect x="281" y="{y+10}" width="2" height="40" rx="1" fill="var(--warmEdge)" opacity=".82"/>')
        else:
            p.append(line(282,y+60,563,y+60,"var(--line)",1,.58))
        p.append(tag(294,y+22,"就绪"))
        p.append(txt(318,y+25,name,13,"var(--ink)",570 if i==0 else 500))
        p.append(txt(294,y+46,sub,10,"var(--muted)",430))
    p.append(line(589,201,589,780))
    p.append(txt(624,242,"示例 Git CLI",20,"var(--ink)",680))
    p.append(txt(624,267,"本机执行",11,"var(--muted)",440)); p.append(tag(691,267,"就绪"))
    small_button(p,1105,224,"测试连接","refresh",w=142)
    heading(p,624,322,"连接信息")
    p.append(txt(624,353,"执行程序",11,"var(--muted)",450)); p.append(txt(753,353,"仅内存预览",13,"var(--ink)",480))
    p.append(line(624,376,1298,376))
    heading(p,624,411,"可用功能","3 项 · 选择后打开参数与结果")
    for i,(name,icon) in enumerate((("打开预览终端","terminal"),("查看 Git 状态","play"),("演示写入权限确认","lock"))):
        row(p,624,441+i*56,674,name,"",icon,False,None,48)
    p.append(line(624,626,1298,626))
    heading(p,624,650,"诊断","当前数据来自只读预览")
    p.append(tag(624,700,"就绪")); p.append(txt(697,700,"已发现 3 项功能",11,"var(--muted)",430))
    small_button(p,624,729,"编辑动作","document",w=125)
    small_button(p,760,729,"上移","back",w=92)
    small_button(p,861,729,"下移","next",w=92)
    small_button(p,1161,729,"删除连接","trash",danger=True,w=137)
    return p+["</g></svg>"]


def activity_header(p):
    p.append(txt(280,194,"运行记录",16,"var(--ink)",650))
    p.append(txt(280,211,"最近 100 条",11,"var(--muted)",430))
    p.append(button(1262,171,46,"","refresh",h=46,icon_only=True))
    filters=(
        ("全部",72,"grid",True),
        ("成功",72,"check",False),
        ("失败",72,"error",False),
        ("取消",72,"close",False),
        ("超时",72,"error",False),
        ("运行中",84,"hourglass",False),
        ("结果待确认",108,"info",False),
    )
    cursor=280
    for label,width,icon,selected in filters:
        p.append(button(cursor,219,width,label,icon,selected=selected,h=32))
        cursor+=width+8


def activity_row(p,y,title,timestamp,state,icon,selected=False):
    x,w,h=280,361,72
    if selected:
        p.append(f'<rect x="{x+1}" y="{y+3}" width="{w-1}" height="{h-2}" rx="12" fill="var(--shadow)" opacity=".08" filter="url(#softShadow)"/>')
        p.append(rect(x,y,w,h,"url(#buttonFace)",12,"var(--edgeStrong)",.9))
        p.append(f'<rect x="{x+1}" y="{y+11}" width="2" height="50" rx="1" fill="var(--warmEdge)" opacity=".82"/>')
    else:
        p.append(line(x+3,y+h,w+x-3,y+h,"var(--line)",1,.55))
    p.append(glyph(icon,x+14,y+20,18,"var(--muted)"))
    p.append(txt(x+46,y+24,title,13,"var(--ink)",570 if selected else 500))
    p.append(txt(x+46,y+42,timestamp,10,"var(--muted)",430))
    p.append(txt(x+46,y+59,state,10,"var(--muted)",480))


def activity_content(p,has_runs):
    activity_header(p)
    if not has_runs:
        # PageState.empty shrink-wraps to its message width at the content edge;
        # its Material inbox glyph is centered over that message, not the page.
        p.append('<g transform="translate(324 306)" fill="none" stroke="var(--muted)" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="M2 3h20v15h-5l-2.2 3h-5.6L7 18H2z"/><path d="M2 13h5l2.2 3h5.6l2.2-3h5"/></g>')
        p.append(txt(280,356,"还没有运行记录。",14,"var(--ink)",450))
        return p

    timestamp="2026-11-21 12:00:00"
    rows=(
        ("查看 Git 状态","超时","error",True),
        ("查看 Git 状态","结果待确认","info",False),
        ("查看 Git 状态","已取消","close",False),
        ("两个整数相加","失败","error",False),
        ("查看 Git 状态","成功","check",False),
    )
    for index,(name,state,icon,selected) in enumerate(rows):
        activity_row(p,274+index*83,name,timestamp,state,icon,selected)

    p.append(txt(708,301,"查看 Git 状态",19,"var(--ink)",650))
    p.append(tag(708,330,"超时","warn"))
    p.append(txt(754,330,"2026-11-21 12:00:00 · 示例 Git CLI",11,"var(--muted)",430))
    p.append(txt(708,397,"运行信息",16,"var(--ink)",650))
    p.append(txt(708,415,"活动只保留状态元数据",11,"var(--muted)",430))
    for index,(label,value) in enumerate((
        ("功能","查看 Git 状态"),
        ("来源","示例 Git CLI"),
        ("状态","超时"),
        ("时间",timestamp),
        ("运行 ID","ui6-inspection-timed-out"),
    )):
        y=438+index*38
        p.append(txt(708,y,label,11,"var(--muted)",450))
        p.append(txt(809,y,value,12,"var(--ink)",480))
    p.append(txt(708,654,"参数和结果正文未写入活动记录。",11,"var(--muted)",430))
    small_button(p,708,709,"重新打开功能","folder",primary=True,w=124)
    small_button(p,842,709,"复制诊断","document",w=100)
    return p


def screen_activity():
    p=shell("活动","活动","查看最近调用状态；参数和结果正文不写入历史",mini=True,fixture="inspection")
    activity_content(p,has_runs=True)
    return p+["</g></svg>"]


def settings_shell(section, fixture="preview", subtitle=None):
    """Settings remain one continuous page; each board captures a scroll point."""
    p=shell("设置","设置","外观、设备和本机数据",fixture=fixture)
    heading(p,316,238,section,subtitle)
    return p


def screen_appearance():
    p=settings_shell("外观","preview","拖动控件切换浅色和深色；也可以跟随 macOS。")
    p.append(txt(316,296,"当前模式",11,"var(--muted)",460))
    p.append(txt(316,320,"浅色",14,"var(--ink)",600))
    p.append(txt(316,353,"切换控件保留实时拖动、方向反转和太阳/月亮内部变化。",11,"var(--muted)",430))
    p.extend(switch_art(850,205,448,224))
    small_button(p,316,374,"跟随 macOS 系统","settings",w=178)
    p.append(line(316,456,1298,456))
    heading(p,316,493,"Mac Host","让已配对设备连接到这台 Mac")
    p.append(tag(316,551,"已停止","warn"))
    small_button(p,316,571,"启动 Host","play",primary=True,w=142)
    small_button(p,472,571,"生成邀请","plus",w=138)
    small_button(p,624,571,"已配对设备","connection",w=150)
    p.append(line(316,638,1298,638))
    heading(p,316,676,"快捷键","名称与组合键沿用当前快捷键配置。")
    p.append(txt(316,732,"导航",13,"var(--ink)",560))
    p.append(txt(316,770,"所有功能",13,"var(--ink)",460)); p.append(txt(1298,770,"⌘ K",12,"var(--muted)",540,"end"))
    p.append(line(316,786,1298,786,"var(--line)",1,.6))
    p.append(txt(316,818,"返回",13,"var(--ink)",460)); p.append(txt(1298,818,"Esc",12,"var(--muted)",540,"end"))
    return p+["</g></svg>"]


def switch_art(x,y,w,h):
    """Use the existing production control capture as an immutable visual reference."""
    sx,sy=w/980,h/490
    rail_x,rail_y,rail_w,rail_h=x+268*sx,y+127*sy,448*sx,232*sy
    thumb_x,thumb_y,thumb_w,thumb_h=x+494*sx,y+126*sy,210*sx,235*sy
    return [
        f'<mask id="switchReferenceMask" maskUnits="userSpaceOnUse" x="{x}" y="{y}" width="{w}" height="{h}"><rect x="{x}" y="{y}" width="{w}" height="{h}" fill="black"/><rect x="{rail_x}" y="{rail_y}" width="{rail_w}" height="{rail_h}" rx="{rail_h/2}" fill="white"/><rect x="{thumb_x}" y="{thumb_y}" width="{thumb_w}" height="{thumb_h}" rx="{thumb_w*.28}" fill="white"/></mask>',
        f'<rect x="{rail_x}" y="{rail_y+5}" width="{rail_w}" height="{rail_h}" rx="{rail_h/2}" fill="var(--shadow)" opacity=".24" filter="url(#softShadow)"/>',
        f'<ellipse cx="{thumb_x+thumb_w*.76}" cy="{thumb_y+thumb_h*.20}" rx="{thumb_w*.72}" ry="{thumb_h*.55}" fill="var(--warmEdge)" opacity=".38" filter="url(#blurGlow)"/>',
        f'<image href="data:image/png;base64,{SWITCH_REFERENCE}" x="{x}" y="{y}" width="{w}" height="{h}" preserveAspectRatio="none" mask="url(#switchReferenceMask)"/>',
    ]


def screen_host():
    p=settings_shell("Mac Host","inspection","运行状态、配对邀请和已连接设备")
    p.append(tag(316,288,"运行中"))
    p.append(txt(316,315,"允许已配对设备在这台 Mac 上运行获准的功能。",12,"var(--muted)",440))
    small_button(p,1018,263,"停止 Host","stop",danger=True,w=130)
    small_button(p,1158,263,"轮换身份","lock",danger=True,w=140)
    p.append(line(316,343,1298,343))
    heading(p,316,379,"配对邀请","二维码只包含短时邀请和 Host 地址，不含长期设备密钥。")
    small_button(p,1147,356,"生成新邀请","plus",primary=True,w=151)
    p.append(rect(316,410,982,154,"url(#panel)",14,"var(--panelEdge)"))
    p.extend(qr_placeholder(337,424,126))
    p.append(txt(493,446,"邀请于 16:30 到期",13,"var(--ink)",520))
    p.append(txt(493,470,"2 个本机网络地址",11,"var(--muted)",430))
    small_button(p,493,491,"复制配对信息","document",w=151)
    p.append(line(316,588,1298,588))
    p.append(txt(316,620,"待处理设备",16,"var(--ink)",650))
    p.append(txt(316,641,"核对设备名称与确认码后再审批",10,"var(--muted)",430))
    p.append(button(1260,601,38,"","refresh",h=38,icon_only=True))
    p.append(rect(316,655,982,68,"url(#panel)",13,"var(--panelEdge)"))
    p.append(glyph("connection",332,670,18)); p.append(txt(363,680,"Pixel 9",12,"var(--ink)",560))
    p.append(txt(363,701,"Android · 确认码 482 193",9,"var(--muted)",430))
    action_x=765
    for label,icon,width,primary,danger in (("拒绝","close",81,False,True),("批准只读","check",103,False,False),("连接向导","settings",125,True,False),("自定义权限","settings",125,False,False)):
        p.append(button(action_x,669,width,label,icon,primary=primary,danger=danger,h=40))
        action_x+=width+7
    p.append(txt(316,758,"已配对设备",16,"var(--ink)",650))
    p.append(txt(316,779,"权限可随时编辑或撤销",10,"var(--muted)",430))
    p.append(rect(316,795,982,48,"url(#panel)",12,"var(--panelEdge)"))
    p.append(glyph("connection",332,809,18)); p.append(txt(363,822,"LGE AN10 · Android · 读取连接 · 连接向导 · 连接管理",11,"var(--ink)",520))
    small_button(p,1060,799,"修改权限","settings",w=111)
    small_button(p,1179,799,"撤销","close",danger=True,w=119)
    return p+["</g></svg>"]


def qr_placeholder(x,y,size):
    modules=21; cell=size/modules
    parts=[rect(x,y,size,size,"#ffffff",8,"var(--panelEdge)")]
    for row_ in range(modules):
        for col_ in range(modules):
            finder=None
            for ox,oy in ((0,0),(14,0),(0,14)):
                dx,dy=col_-ox,row_-oy
                if 0<=dx<7 and 0<=dy<7:
                    finder=dx in (0,6) or dy in (0,6) or (2<=dx<=4 and 2<=dy<=4)
                    break
            filled=finder if finder is not None else ((col_*23+row_*17+col_*row_*3)%7)<3
            if filled:
                parts.append(rect(x+col_*cell+1,y+row_*cell+1,cell-1,cell-1,"#24242a",0,"none",0))
    return parts


def screen_shortcuts():
    p=settings_shell("快捷键","preview","名称与组合键沿用当前快捷键配置。")
    for i,(group,items) in enumerate((("导航",(("所有功能","⌘ K"),("返回","Esc"))), ("运行",(("运行当前功能","⌘ ↵"),)))):
        y=294+i*156
        heading(p,316,y,group)
        for j,(name,key) in enumerate(items):
            yy=y+38+j*48
            p.append(txt(316,yy,name,13,"var(--ink)",460))
            p.append(txt(1298,yy,key,12,"var(--muted)",540,"end"))
            p.append(line(316,yy+16,1298,yy+16,"var(--line)",1,.6))
    return p+["</g></svg>"]


def screen_local_data():
    p=settings_shell("本机数据","preview","连接配置和活动记录保存在本机。")
    heading(p,316,294,"活动保留时长","仅保存脱敏后的运行状态信息")
    p.append(txt(316,337,"保留最近",12,"var(--muted)",440))
    p.append(rect(1075,309,223,44,"url(#panel)",11,"var(--panelEdge)")); p.append(txt(1093,337,"30 天",13,"var(--ink)",500)); p.append(txt(1279,337,"⌄",14,"var(--muted)",500,"end"))
    p.append(line(316,382,1298,382))
    heading(p,316,422,"清空活动记录","只删除本机保存的调用历史，不移除连接")
    p.append(txt(316,466,"删除后无法恢复。",11,"var(--muted)",430))
    small_button(p,1134,436,"清空记录","trash",danger=True,w=164)
    return p+["</g></svg>"]


def screen_setup_variant(kind):
    p=shell("管理连接","管理连接","查看连接状态、诊断与可执行的管理操作",fixture="inspection")
    p.append('<rect x="16" y="58" width="1328" height="826" fill="#242329" opacity=".24"/>')
    x,y,w,h=356,116,648,668
    config = {
        "cli": ("自定义 CLI", "Git CLI", [
            ("程序绝对路径", "/usr/bin/git", 44, "folder"),
            ("启动参数 JSON 数组", "[]", 58, None),
            ("工作目录（可选）", "留空使用默认目录", 44, None),
            ("动作清单 JSON（可选）", "选择文件…", 44, "folder"),
        ]),
        "stdio": ("stdio MCP", "项目 MCP", [
            ("程序绝对路径", "/usr/local/bin/mcp-server", 44, "folder"),
            ("启动参数 JSON 数组", "[]", 58, None),
            ("工作目录（可选）", "留空使用默认目录", 44, None),
        ]),
        "http": ("HTTP MCP", "项目 MCP", [
            ("HTTP URL", "https://mcp.example.com", 44, None),
            ("Bearer Token（可选）", "••••••••", 44, None),
        ]),
        "music": ("网易云音乐", "网易云音乐", [
            ("程序", "/usr/local/bin/ncm-cli", 44, ("search", "folder")),
            ("开放平台 App ID", "输入 App ID", 44, None),
            ("Private Key（PEM）", "选择 .pem 文件", 44, "folder"),
        ]),
    }
    adapter, label, fields = config[kind]
    p.append(rect(x,y,w,h,"url(#dialogPanel)",20,"var(--panelEdge)",1.4))
    p.append(txt(x+30,y+40,"第 2 步 · 配置连接",20,"var(--ink)",670)); p.append(txt(x+30,y+64,"填写连接信息，测试通过后即可保存。",11,"var(--muted)",430))
    p.append(rect(x+30,y+83,w-60,54,"url(#buttonFace)",12,"var(--panelEdge)"))
    p.append(glyph("connection",x+44,y+101,18))
    p.append(txt(x+73,y+104,"执行设备",10,"var(--muted)",500))
    p.append(txt(x+73,y+124,"本机 Mac",13,"var(--ink)",550))
    p.append(line(x+30,y+151,x+w-30,y+151))
    p.append(txt(x+30,y+170,"适配器",10,"var(--muted)",520))
    p.append(rect(x+30,y+180,w-60,42,"url(#inset)",10,"var(--insetEdge)"))
    p.append(txt(x+45,y+207,adapter,13,"var(--ink)",500)); p.append(txt(x+w-48,y+207,"⌄",14,"var(--muted)",500,"end"))
    p.append(field(x+30,y+233,w-60,"名称",label,44))
    cursor=y+289
    for field_label, value, field_h, icon in fields:
        icons = (icon,) if isinstance(icon, str) else (icon or ())
        action_gap = 10 if len(icons) == 1 else 8
        field_w = w-60-len(icons)*42-len(icons)*action_gap
        p.append(field(x+30,cursor,field_w,field_label,value,field_h))
        button_x = x+30+field_w+action_gap
        for action_icon in icons:
            p.append(button(button_x,cursor,42,"",action_icon,h=field_h,icon_only=True))
            button_x += 42+action_gap
        cursor+=field_h+12
    if kind=="http":
        p.append(tag(x+30,cursor+4,"尚未测试","warn"))
        p.append(txt(x+30,cursor+27,"Bearer Token 仅留在当前进程内存，关闭后丢弃。",10,"var(--muted)",430))
    elif kind=="music":
        p.append(txt(x+30,cursor+9,"程序路径是内存样例；不会检查磁盘或发起登录。",10,"var(--muted)",430))
        p.append(txt(x+30,cursor+27,"Private Key 只用于连接配置，不写入连接清单。",10,"var(--muted)",430))
    else:
        p.append(glyph("refresh",x+30,y+538,14,"var(--muted)"))
        p.append(txt(x+52,y+550,"尚未测试 · 测试通过后才可保存",10,"var(--muted)",430))
    p.append(line(x+30,y+570,x+w-30,y+570))
    small_button(p,x+w-362,y+593,"取消","close",w=92)
    small_button(p,x+w-262,y+593,"测试连接","refresh",w=126)
    # Disabled until the connection check reports a saveable result.
    p.append(button(x+w-128,y+593,98,"保存连接", "check", primary=True, h=38, disabled=True))
    return p+["</g></svg>"]


def screen_setup():
    return screen_setup_variant("cli")


def screen_setup_stdio():
    return screen_setup_variant("stdio")


def screen_setup_http():
    return screen_setup_variant("http")


def screen_setup_music():
    return screen_setup_variant("music")


def overlay(title,subtitle,w,h,background="01-workspace",offset_y=12):
    # Draw the actual entry page behind the scrim so each dialog is reviewed
    # in the context where people reach it.
    p=screen_by_name(background)[:-1]
    p.append('<rect x="16" y="58" width="1328" height="826" fill="#24232a" opacity=".28"/>')
    x=(W-w)/2; y=(H-h)/2+offset_y
    p.append(rect(x,y,w,h,"url(#dialogPanel)",20,"var(--panelEdge)",1.4))
    p.append(txt(x+30,y+42,title,19,"var(--ink)",680))
    if subtitle: p.append(txt(x+30,y+66,subtitle,11,"var(--muted)",430))
    return p,x,y,w,h


def screen_permission():
    p,x,y,w,h=overlay("确认执行","检查执行目标与参数后再继续。",560,462,background="inspection-permission",offset_y=15)
    fields=(("功能","演示写入权限确认"),("来源","示例 Git CLI"),("执行目标","此设备"),("权限","外部写入"))
    yy=y+106
    for label,value in fields:
        p.append(txt(x+24,yy,label,10,"var(--muted)",520))
        p.append(txt(x+114,yy,value,12,"var(--ink)",520))
        yy+=30
    p.append(line(x+24,yy-5,x+w-24,yy-5))
    p.append(txt(x+24,yy+21,"提交参数（密钥字段已隐藏）",12,"var(--ink)",500))
    p.append(rect(x+24,yy+38,w-48,82,"url(#inset)",11,"var(--insetEdge)"))
    for index,line_text in enumerate(("{", '  "note": "仅内存预览备注"', "}")):
        p.append(
            f'<text x="{x+37}" y="{yy+62+index*17}" '
            f'font-family="SFMono-Regular,Menlo,monospace" font-size="11" '
            f'font-weight="450" fill="var(--ink)">{escape(line_text)}</text>'
        )
    warning_y=yy+146
    p.append(f'<path d="M{x+31} {warning_y-11}l7 13h-14z" fill="none" stroke="var(--danger)" stroke-width="1.3" stroke-linejoin="round"/>')
    p.append(f'<path d="M{x+31} {warning_y-7}v4m0 2v.5" stroke="var(--danger)" stroke-width="1.3" stroke-linecap="round"/>')
    p.append(txt(x+48,warning_y,"请确认执行目标与输入内容。外部写入可能无法撤回。",10,"var(--danger)",500))
    p.append(line(x+1,y+h-70,x+w-1,y+h-70,"var(--line)",1,.72))
    button_y=y+h-54
    p.append(button(x+w-225,button_y,87,"取消","close",h=40))
    p.append(button(x+w-130,button_y,112,"确认执行","play",primary=True,h=40))
    return p+["</g></svg>"]


def screen_danger_confirmation():
    p,x,y,w,h=overlay("清空本机活动记录？","请确认后继续。",520,330,background="22-settings-local-data")
    p.append(rect(x+30,y+99,46,46,"url(#buttonFace)",13,"var(--panelEdge)"))
    p.append(glyph("trash",x+43,y+112,20,"var(--danger)"))
    p.append(txt(x+91,y+117,"删除后无法恢复。",13,"var(--ink)",570))
    p.append(txt(x+91,y+139,"只删除本机保存的活动，不影响连接配置。",10,"var(--muted)",430))
    p.append(line(x+30,y+181,x+w-30,y+181))
    p.append(txt(x+30,y+211,"将清除",10,"var(--muted)",480))
    p.append(txt(x+112,y+211,"运行状态与时间记录",11,"var(--ink)",520))
    small_button(p,x+w-228,y+h-56,"取消","close",w=94)
    small_button(p,x+w-126,y+h-56,"清空记录","trash",danger=True,w=96)
    return p+["</g></svg>"]


def screen_target():
    p,x,y,w,h=overlay("选择执行目标","选择此连接实际可用的设备。",585,390,background="inspection-connections")
    row(p,x+28,y+103,w-56,"本机 Mac","默认目标 · 在此设备运行","connection",True,None,61)
    row(p,x+28,y+171,w-56,"示例 Mac Host","已配对 · 连接管理","connection",False,None,61)
    p.append(txt(x+30,y+273,"设备状态与授权说明来自当前运行时。",10,"var(--muted)",430))
    small_button(p,x+w-230,y+h-57,"取消","close",w=94)
    small_button(p,x+w-126,y+h-57,"选择","check",primary=True,w=96)
    return p+["</g></svg>"]


def screen_action_editor():
    p,x,y,w,h=overlay("编辑动作 · 示例 Git CLI","清单版本 1 · 参数以数组传递，{{变量名}} 从输入规则取值。",680,700,background="inspection-connections")
    small_button(p,x+30,y+88,"新增动作","plus",primary=True,w=134)
    small_button(p,x+175,y+88,"导入","folder",w=102)
    small_button(p,x+287,y+88,"导出","document",w=102)
    p.append(txt(x+30,y+153,"动作清单 JSON",11,"var(--muted)",520))
    p.append(rect(x+30,y+167,w-60,300,"url(#inset)",12,"var(--insetEdge)"))
    code=[
        "{",
        '  "schemaVersion": 1,',
        '  "id": "ui6-ui6-review-git",',
        '  "displayName": "示例 Git CLI",',
        '  "platforms": [',
        '    "macos"',
        '  ],',
        '  "executable": "仅内存预览",',
        '  "actions": [',
        '    {',
        '      "id": "version",',
        '      "title": "查看版本",',
        '      "argv": [',
        '        "--version"',
    ]
    for i,line_ in enumerate(code): p.append(txt(x+48,y+194+i*20,line_,11,"var(--ink)",440))
    p.append(field(x+30,y+472,300,"预览动作","查看版本 · version",55))
    p.append(field(x+350,y+472,300,"预览输入 JSON","{}",55))
    small_button(p,x+30,y+540,"检查并预览参数","search",w=179)
    p.append(rect(x+223,y+540,401,62,"url(#inset)",10,"var(--insetEdge)"))
    p.append(txt(x+235,y+565,"检查后显示最终参数数组。",10,"var(--muted)",430))
    p.append(txt(x+30,y+612,"只检查参数，不运行命令。",10,"var(--muted)",430))
    small_button(p,x+w-240,y+h-55,"取消","close",w=96)
    small_button(p,x+w-132,y+h-55,"保存动作","document",primary=True,w=110)
    return p+["</g></svg>"]


def screen_terminal():
    p=['<svg xmlns="http://www.w3.org/2000/svg" width="1360" height="900" viewBox="0 0 1360 900">',defs(False)]
    p.append('<rect width="1360" height="900" fill="#151519"/><g clip-path="url(#windowClip)"><rect x="16" y="16" width="1328" height="868" fill="url(#scene)"/><rect x="16" y="16" width="1328" height="868" fill="url(#skyGlow)"/><rect x="16" y="16" width="1328" height="868" fill="url(#sceneGrain)" opacity=".42"/><rect x="16" y="16" width="1328" height="42" fill="var(--panelBottom)" opacity=".30"/><path d="M16 58H1344" stroke="var(--line)" stroke-opacity=".72"/>')
    for x,c in ((42,"#f26a5f"),(66,"#f0c34d"),(90,"#49bd6c")):
        p.append(f'<circle cx="{x}" cy="37" r="7" fill="{c}"/>')
    p.append(txt(680,42,"Aggregate",15,"var(--muted)",620,"middle"))
    p.append(txt(48,105,"终端",19,"var(--ink)",650))
    p.append(txt(48,145,"示例 Git CLI   $ git status --short",12,"var(--ink)",520))
    p.append(txt(48,166,"执行端：本机 Mac · 权限：读取连接 · 交互会话",10,"var(--muted)",430))
    p.append(button(1270,78,42,"","stop",danger=True,h=42,icon_only=True))
    p.append(rect(32,184,1296,508,"#17181c",15,"#555660",1))
    for i,line_ in enumerate((
        "UI 检查终端：全内存模拟，不会运行外部命令。",
        "$ git status --short",
        " M README.md",
        "?? draft.md",
        "",
        "█",
    )):
        p.append(txt(58,226+i*27,line_,13,"#d7dccf" if i else "#d8bd8c",450))
    labels=(("Ctrl",64),("Esc",64),("Tab",64),("↑",52),("↓",52),("←",52),("→",52),("复制",90),("粘贴",90))
    cursor=32
    for i,(label,width) in enumerate(labels):
        p.append(button(cursor,718,width,label,"terminal" if label=="Ctrl" else None,selected=(label=="Ctrl"),h=40))
        cursor+=width+10
    return p+["</g></svg>"]


def screen_result():
    p=shell("所有功能","所有功能","从一个地方找到并运行 CLI 与 MCP 功能。",search=False,mini=True,fixture="inspection")
    p.append(field(280,178,570,"","搜索名称、说明或来源",42,"search"))
    workspace_type_filters(p)
    workspace_directory_header(p, count="17 项")
    # CapabilityCatalog sorts the inspection catalog by title. This viewport
    # shows rows 5–11 after scrolling to the selected Git action.
    result_rows=UI6_DIRECTORY_ROWS[4:11]
    for index,(name,sub,icon) in enumerate(result_rows):
        row(p,280,354+index*60,295,name,sub,icon,index==len(result_rows)-1,"☆",56)
    p.append(line(596,344,596,776,"var(--line)"))
    p.append(txt(624,353,"查看 Git 状态",20,"var(--ink)",680))
    p.append(tag(624,380,"示例 Git CLI · 成功"))
    p.append(txt(624,405,"显示当前分支与工作区状态",11,"var(--muted)",430))
    heading(p,624,450,"运行","此能力无需输入参数")
    target_status(p,624,502,"此设备")
    p.append(button(776,498,104,"运行","play",primary=True,h=46))
    p.append(line(624,552,1308,552,"var(--line)",1,.78))
    p.append(txt(624,590,"运行结果",14,"var(--ink)",620))
    p.append(txt(624,612,"运行成功",11,"var(--muted)",430))
    p.append(button(1235,575,77,"复制","copy",h=40))
    p.append(rect(624,618,684,104,"url(#inset)",12,"var(--insetEdge)"))
    p.append(txt(646,651,"预览结果：工作区干净",13,"var(--ink)",460))
    return p+["</g></svg>"]


def screen_states():
    p=shell("通用状态","所有功能","状态文案和操作必须对应真实运行时信息")
    cards=(("加载中","连接正在准备，请稍候。","refresh"),("没有连接","添加一个连接后即可运行功能。","connection"),("没有匹配","尝试更短的搜索词。","search"),("连接失败","检查连接设置或重新测试。","close"))
    for i,(title,copy,icon) in enumerate(cards):
        x=280+(i%2)*525; y=234+(i//2)*258
        p.append(glyph(icon,x,y+4,25,"var(--muted)"))
        p.append(txt(x+42,y+18,title,17,"var(--ink)",640))
        p.append(txt(x+42,y+43,copy,12,"var(--muted)",430))
        small_button(p,x+42,y+67,"查看下一步","next",primary=i==1,w=142)
        if i < 2: p.append(line(x,y+194,x+486,y+194,"var(--line)",1,.55))
    p.append(line(797,208,797,688,"var(--line)",1,.65))
    return p+["</g></svg>"]


def screen_buttons():
    p=shell("按钮与图案","设置","主操作、次操作与高频图案共享同一材质")
    col=(("主操作", "运行与保存", "play", True),("刷新", "重新读取当前状态", "refresh", False),("搜索", "查找功能与内容", "search", False),("关闭", "关闭当前面板", "close", False))
    for i,(title,sub,icon,primary) in enumerate(col):
        x=290+i*250
        p.append(txt(x,225,title,14,"var(--ink)",600)); p.append(txt(x,247,sub,10,"var(--muted)",430))
        p.append(button(x,274,96,"",icon,primary=primary,h=96,icon_only=True))
        p.append(txt(x,396,"静置",10,"var(--muted)",440))
        p.append(button(x+110,350,96,"",icon,selected=True,h=96,icon_only=True))
        p.append(txt(x+110,472,"聚焦",10,"var(--muted)",440))
        p.append(button(x,502,96,"",icon,h=96,icon_only=True))
        p.append(button(x+110,502,96,"",icon,h=96,icon_only=True,pressed=True))
        p.append(txt(x,624,"静置",10,"var(--muted)",440))
        p.append(txt(x+110,624,"按下",10,"var(--muted)",440))
    p.append(txt(290,698,"按钮静置和按下状态由同一个共享动画时钟驱动；减少动态效果时停在静态造型。",11,"var(--muted)",430))
    return p+["</g></svg>"]


def screen_dark():
    p=shell("所有功能","所有功能","深色模式保持玻璃厚度与点阵清晰度",dark=True,search=False,mini=True)
    p.append(field(280,178,570,"","搜索名称、说明或来源",42,"search"))
    workspace_type_filters(p)
    workspace_directory_header(p, count="3 项")
    for i,(name,sub,icon) in enumerate((("查看 Git 状态","CLI · 示例 Git CLI","terminal"),("读取项目说明","资源 · 示例 MCP","folder"),("两个整数相加","MCP 工具 · 示例 MCP","spark"))): row(p,280,354+i*60,295,name,sub,icon,i==2,"☆",56)
    p.append(line(600,344,600,770))
    p.append(txt(630,354,"两个整数相加",20,"var(--ink)",680)); p.append(tag(630,381,"示例 MCP · 只读"))
    p.append(field(630,425,320,"第一个整数","例如 12")); p.append(field(968,425,320,"第二个整数","例如 30"))
    target_status(p,630,496); p.append(button(782,493,104,"运行","play",primary=True,h=46))
    p.append(rect(630,562,658,128,"url(#inset)",12,"var(--insetEdge)")); p.append(txt(650,599,"输出将显示在这里",12,"var(--muted)",460))
    return p+["</g></svg>"]


def screen_music():
    p=shell("示例网易云音乐","示例网易云音乐","播放、搜索和账号状态来自同一音乐会话")
    p.append(rect(280,188,468,530,"url(#panel)",19,"var(--panelEdge)"))
    p.append(txt(310,224,"播放器",16,"var(--ink)",620)); p.append(tag(672,224,"播放中"))
    p.append(rect(310,248,150,150,"url(#inset)",18,"var(--insetEdge)")); p.append(glyph("music",354,292,60))
    p.append(txt(482,300,"示例歌曲",18,"var(--ink)",650)); p.append(txt(482,330,"示例歌手",12,"var(--muted)",450)); p.append(txt(482,356,"0:12 / 3:20",11,"var(--muted)",430))
    for i,ico in enumerate(("previous","pause","next","stop")): p.append(button(314+i*78,432,64,"",ico,primary=(ico=="pause"),h=58,icon_only=True))
    p.append(txt(310,534,"播放信息",11,"var(--muted)",500)); p.append(txt(310,558,"示例网易云音乐 · 声音由此设备输出",12,"var(--ink)",470))
    small_button(p,310,612,"刷新状态","refresh",w=132)
    small_button(p,454,612,"音乐账号","connection",w=132)
    heading(p,786,220,"找音乐","搜索歌曲并查看结果")
    p.append(field(786,245,522,"","搜索歌曲",44,"search")); small_button(p,1174,299,"搜索","search",primary=True,w=134)
    p.append(txt(786,360,"歌曲 · 2 首",12,"var(--ink)",560))
    p.append(txt(1308,360,"由当前连接提供",10,"var(--muted)",430,"end"))
    row(p,786,374,522,"示例歌曲","示例歌手 · 可播放","music",False,"播放",62)
    row(p,786,444,522,"暂不可播放的歌曲","示例歌手 · 当前音源不可播放","music",False,"不可播放",62)
    return p+["</g></svg>"]


def screen_account():
    p,x,y,w,h=overlay("音乐账号","连接端支持时才会显示账号管理。",520,420,background="inspection-music")
    p.append(rect(x+30,y+95,w-60,90,"url(#inset)",13,"var(--insetEdge)"))
    p.append(glyph("connection",x+49,y+124,24)); p.append(txt(x+88,y+127,"尚未登录",14,"var(--ink)",560)); p.append(txt(x+88,y+151,"使用扫码登录并等待连接端确认。",10,"var(--muted)",430))
    p.append(rect(x+30,y+207,160,150,"#f2f0ec",12,"var(--panelEdge)")); p.append(txt(x+110,y+286,"二维码预览",10,"var(--muted)",440,"middle"))
    p.append(txt(x+214,y+238,"等待扫码",13,"var(--ink)",540)); p.append(txt(x+214,y+264,"刷新二维码后使用音乐客户端扫码。",10,"var(--muted)",430))
    small_button(p,x+214,y+291,"刷新二维码","refresh",w=142)
    small_button(p,x+w-231,y+h-57,"取消扫码","close",w=100)
    small_button(p,x+w-121,y+h-57,"登录","check",primary=True,w=92)
    return p+["</g></svg>"]


def screen_mini():
    p=shell("活动","活动","查看最近调用状态；参数和结果正文不写入历史",mini=True,fixture="inspection")
    activity_content(p,has_runs=False)
    return p+["</g></svg>"]


def screen_host_permissions():
    p,x,y,w,h=overlay("配置设备权限","全局范围与逐连接权限分开管理。",720,640,background="06-settings-host")
    p.append(txt(x+30,y+99,"全局能力",12,"var(--ink)",560))
    p.append(rect(x+30,y+112,w-60,33,"url(#buttonFace)",9,"var(--panelEdge)"))
    p.append(glyph("check",x+42,y+120,16,"var(--good)")); p.append(txt(x+68,y+133,"读取连接",11,"var(--ink)",520)); p.append(txt(x+w-44,y+133,"必需",10,"var(--good)",520,"end"))
    for i,(label,selected) in enumerate((("连接向导",True),("连接管理",True),("账号",False),("终端",False),("清理活动",False),("内容传输 · 尚未开放",False))):
        yy=y+154+i*32
        p.append(rect(x+34,yy-12,16,16,"url(#panel)" if not selected else "var(--warmEdge)",4,"var(--panelEdge)"))
        if selected: p.append(glyph("check",x+36,yy-10,12,"var(--ink)"))
        p.append(txt(x+62,yy,label,11,"var(--muted)" if label.startswith("内容传输") else "var(--ink)",470))
    p.append(line(x+30,y+353,x+w-30,y+353))
    heading(p,x+30,y+382,"逐连接权限","本机控制或外部写入会同时包含读取权限")
    for i,(name,permissions) in enumerate((("示例 Git CLI",("读取","本机控制")),("示例 MCP",("读取",)),("示例网易云音乐",("读取","外部写入")))):
        yy=y+414+i*52
        row(p,x+30,yy,w-60,name,"", "connection",False,None,46)
        # Leave enough room for each dot-matrix glyph and the full Chinese
        # label while keeping the three controls flush with the row's right edge.
        bx=x+w-338
        options=(
            ("读取","visibility",80),
            ("本机控制","desktop",104),
            ("外部写入","build",104),
        )
        for permission,icon,bw in options:
            p.append(button(bx,yy+5,bw,permission,icon,selected=permission in permissions,h=32))
            bx+=bw+6
    small_button(p,x+w-235,y+h-55,"取消","close",w=96)
    small_button(p,x+w-130,y+h-55,"保存权限","document",primary=True,w=110)
    return p+["</g></svg>"]


def screen_terminal_state():
    p=shell("所有功能","所有功能","从一个地方找到并运行 CLI 与 MCP 功能。",search=False,fixture="inspection")
    p.append(field(280,178,570,"","搜索名称、说明或来源",42,"search"))
    workspace_type_filters(p)
    workspace_directory_header(p, count="1 项", selected="全部")
    row(p,280,354,295,"查看 Git 状态","CLI · 示例 Git CLI","play",True,"☆",56)
    p.append(line(596,344,596,776,"var(--line)"))
    p.append(txt(624,353,"查看 Git 状态",20,"var(--ink)",680))
    p.append(tag(624,380,"示例 Git CLI · 结果待确认","danger"))
    p.append(txt(624,405,"仅内存预览结果待确认状态",11,"var(--muted)",430))
    heading(p,624,450,"运行","此能力无需输入参数")
    target_status(p,624,502,"此设备")
    p.append(button(776,498,104,"运行","play",primary=True,h=46))
    p.append(line(624,552,1308,552,"var(--line)",1,.78))
    p.append(txt(624,590,"运行结果",14,"var(--ink)",620))
    p.append(txt(624,612,"结果待确认",11,"var(--danger)",500))
    p.append(rect(624,618,684,162,"url(#panel)",12,"var(--danger)"))
    p.append(txt(640,645,"需要处理",13,"var(--ink)",600))
    p.append(txt(640,669,"操作可能已经执行。先检查活动记录和执行端状态，不要直接重跑。",11,"var(--ink)",440))
    p.append(button(640,683,150,"检查活动状态","search",primary=True,h=40))
    p.append(txt(640,758,"查看错误详情   ⌄",11,"var(--muted)",440))
    return p+["</g></svg>"]


def screen_mcp():
    return screen_connection_home(True)


def screen_inspection_workspace(permission=False):
    p=shell("所有功能","所有功能","从一个地方找到并运行 CLI 与 MCP 功能。",search=False,mini=True,fixture="inspection")
    p.append(field(280,178,570,"","搜索名称、说明或来源",42,"search"))
    workspace_type_filters(p)
    workspace_directory_header(p,count="17 项",selected="全部")
    rows=UI6_DIRECTORY_ROWS[5:12] if permission else UI6_DIRECTORY_ROWS[4:11]
    for i,(name,sub,icon) in enumerate(rows):
        row(p,280,354+i*60,295,name,sub,icon,i==len(rows)-1,"☆",56)
    p.append(line(596,344,596,776,"var(--line)"))
    title="演示写入权限确认" if permission else "查看 Git 状态"
    p.append(txt(624,353,title,20,"var(--ink)",680))
    p.append(tag(624,380,"示例 Git CLI · 需要外部写入" if permission else "示例 Git CLI · 只读"))
    p.append(txt(624,405,"仅用于检查确认弹窗，不会执行外部命令" if permission else "显示当前分支与工作区状态",11,"var(--muted)",430))
    if permission:
        heading(p,624,450,"参数","参数会在运行前检查")
        p.append(field(624,490,336,"备注","仅内存预览备注"))
        target_status(p,624,550,"此设备")
        p.append(button(776,547,104,"运行","play",primary=True,h=46))
        p.append(line(624,603,1308,603,"var(--line)",1,.78))
        heading(p,624,642,"运行结果","尚无调用 · 结果仅在本机显示")
        p.append(rect(624,677,684,104,"url(#inset)",12,"var(--insetEdge)"))
        p.append(txt(646,708,"结果会显示在这里",13,"var(--ink)",500))
        p.append(txt(646,733,"结构化输出、复制与文件操作只在结果提供时出现。",11,"var(--muted)",430))
    else:
        heading(p,624,450,"运行结果","最近一次调用 · 预览数据")
        p.append(rect(624,486,684,105,"url(#inset)",12,"var(--insetEdge)"))
        p.append(txt(646,519,"预览结果：工作区干净",13,"var(--ink)",460))
    return p+["</g></svg>"]


def screen_inspection_music():
    p=shell("示例网易云音乐","示例网易云音乐","播放、搜索和账号状态来自同一音乐会话",fixture="inspection")
    p.append(rect(280,188,468,530,"url(#panel)",19,"var(--panelEdge)"))
    p.append(txt(310,224,"播放器",16,"var(--ink)",620)); p.append(tag(672,224,"播放中"))
    p.append(rect(310,248,150,150,"url(#inset)",18,"var(--insetEdge)")); p.append(glyph("music",354,292,60))
    p.append(txt(482,300,"示例歌曲",18,"var(--ink)",650)); p.append(txt(482,330,"示例歌手",12,"var(--muted)",450)); p.append(txt(482,356,"0:12 / 3:20",11,"var(--muted)",430))
    for i,ico in enumerate(("previous","pause","next","stop")): p.append(button(314+i*78,432,64,"",ico,primary=(ico=="pause"),h=58,icon_only=True))
    p.append(txt(310,534,"播放信息",11,"var(--muted)",500)); p.append(txt(310,558,"示例网易云音乐 · 声音由此设备输出",12,"var(--ink)",470))
    small_button(p,310,612,"刷新状态","refresh",w=132)
    small_button(p,454,612,"音乐账号","connection",w=132)
    heading(p,786,220,"找音乐","搜索歌曲并查看结果")
    p.append(field(786,245,522,"","搜索歌曲",44,"search")); small_button(p,1174,299,"搜索","search",primary=True,w=134)
    p.append(txt(786,360,"歌曲 · 2 首",12,"var(--ink)",560))
    row(p,786,374,522,"示例歌曲","示例歌手 · 可播放","music",False,"播放",62)
    row(p,786,444,522,"暂不可播放的歌曲","示例歌手 · 当前音源不可播放","music",False,"不可播放",62)
    return p+["</g></svg>"]


def screen_by_name(name):
    inspection_screens={
        "inspection-permission":lambda:screen_inspection_workspace(permission=True),
        "inspection-connections":screen_connections,
        "inspection-music":screen_inspection_music,
    }
    if name in inspection_screens:
        return inspection_screens[name]()
    mapping={
        "01-workspace":screen_workspace,
        "02-music":screen_music,
        "03-connections":screen_connections,
        "04-activity":screen_activity,
        "05-settings-appearance":screen_appearance,
        "06-settings-host":screen_host,
        "07-connection-setup":screen_setup,
        "08-terminal-running":screen_terminal,
        "09-permission-confirmation":screen_permission,
        "10-states":screen_states,
        "11-button-motion":screen_buttons,
        "12-dark-reference":screen_dark,
        "13-action-editor":screen_action_editor,
        "14-music-account-login":screen_account,
        "15-settings-shortcuts":screen_shortcuts,
        "16-result-success":screen_result,
        "17-connection-home":screen_connection_home,
        "18-mini-player":screen_mini,
        "19-target-selector":screen_target,
        "20-host-permissions":screen_host_permissions,
        "21-mcp-home":screen_mcp,
        "22-settings-local-data":screen_local_data,
        "23-danger-confirmation":screen_danger_confirmation,
        "24-result-unknown":screen_terminal_state,
        "25-setup-stdio-mcp":screen_setup_stdio,
        "26-setup-http-mcp":screen_setup_http,
        "27-setup-music-adapter":screen_setup_music,
    }
    return mapping[name]()


def main():
    for name in (
        "01-workspace","02-music","03-connections","04-activity","05-settings-appearance",
        "06-settings-host","07-connection-setup","08-terminal-running","09-permission-confirmation",
        "10-states","11-button-motion","12-dark-reference","13-action-editor","14-music-account-login",
        "15-settings-shortcuts","16-result-success","17-connection-home","18-mini-player",
        "19-target-selector","20-host-permissions","21-mcp-home","22-settings-local-data","23-danger-confirmation","24-result-unknown",
        "25-setup-stdio-mcp","26-setup-http-mcp","27-setup-music-adapter",
    ):
        source="\n".join(screen_by_name(name))
        palette=DARK if name=="12-dark-reference" else LIGHT
        source=re.sub(r"var\(--([A-Za-z][A-Za-z0-9]*)\)",lambda match:palette[match.group(1)],source)
        source="\n".join(line.rstrip() for line in source.splitlines())+"\n"
        (OUT/f"{name}.svg").write_text(source,encoding="utf-8")
if __name__ == "__main__":
    main()
