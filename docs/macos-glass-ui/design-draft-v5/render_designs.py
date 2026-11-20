#!/usr/bin/env python3
"""Generate the reviewable, fixed-size SVG screens for Aggregate design v5."""

from html import escape
import base64
from pathlib import Path
import re

OUT = Path(__file__).resolve().parent
W, H = 1360, 900
SWITCH_REFERENCE = base64.b64encode(
    (OUT / "glass-theme-switch-light.png").read_bytes()
).decode("ascii")

LIGHT = {
    "scene0":"#e6e6e8", "scene1":"#e6e6e8", "scene2":"#f4f4f6", "warm":"#b06520",
    "warmEdge":"#ffca73", "ink":"#27272f", "muted":"#656571", "line":"#c9c9d2",
    "glyph":"#4f493b", "panelTop":"#ffffff", "panelBottom":"#ececf0", "panelEdge":"#fafafd",
    "edgeStrong":"#ffffff", "shadow":"#5a596f", "inset":"#d4d4dc", "insetEdge":"#c9c9d2",
    "good":"#35735b", "danger":"#a24640", "dangerInk":"#a24640",
}
DARK = {
    "scene0":"#0a0a0c", "scene1":"#0a0a0c", "scene2":"#1e2025", "warm":"#8b9aff",
    "warmEdge":"#a7b3ff", "ink":"#efeff3", "muted":"#b8bac5", "line":"#35363e",
    "glyph":"#d3c5aa", "panelTop":"#41434c", "panelBottom":"#242630", "panelEdge":"#60626d",
    "edgeStrong":"#70717b", "shadow":"#101116", "inset":"#111216", "insetEdge":"#35363e",
    "good":"#a2d6bc", "danger":"#f2a09d", "dangerInk":"#f2a09d",
}

GLYPHS = {
    "search": ("001110000", "010001000", "100000100", "100000100", "100000100", "010001000", "001110000", "000001000", "000000100"),
    "play": ("000100000", "000110000", "000111000", "000111100", "000111110", "000111100", "000111000", "000110000", "000100000"),
    "pause": ("011000110",) * 9,
    "refresh": ("001111000", "010000100", "100000010", "100000110", "100000000", "000000001", "010000001", "001000010", "000111100"),
    "plus": ("000010000", "000010000", "000010000", "000010000", "111111111", "000010000", "000010000", "000010000", "000010000"),
    "music": ("000011110", "000010010", "000010010", "000010010", "000010010", "001110110", "011101110", "011001100", "000000000"),
    "settings": ("000111000", "010101010", "001111100", "111000111", "101010101", "111000111", "001111100", "010101010", "000111000"),
    "history": ("000010000", "000111000", "001101100", "011000110", "110000011", "110000011", "011000110", "001101100", "000111000"),
    "connection": ("000010000", "000111000", "001010100", "010010010", "100010001", "010010010", "001010100", "000111000", "000010000"),
    "terminal": ("000000000", "010000000", "001000000", "000100000", "001000000", "010000000", "000011110", "000000000", "000000000"),
    "check": ("000000001", "000000010", "000000100", "000001000", "100010000", "010100000", "001000000", "000000000", "000000000"),
    "close": ("100000001", "010000010", "001000100", "000101000", "000010000", "000101000", "001000100", "010000010", "100000001"),
    "stop": ("000000000", "011111110", "011111110", "011111110", "011111110", "011111110", "011111110", "011111110", "000000000"),
    "folder": ("111100000", "100110000", "100011111", "100000001", "100000001", "100000001", "100000001", "111111111", "000000000"),
    "back": ("000010000", "000100000", "001000000", "111111110", "001000000", "000100000", "000010000", "000000000", "000000000"),
    "next": ("010000010", "011000010", "011100010", "011110010", "011111010", "011110010", "011100010", "011000010", "010000010"),
    "previous": ("010000010", "010000110", "010001110", "010011110", "010111110", "010011110", "010001110", "010000110", "010000010"),
    "trash": ("000111000", "011111110", "000000000", "010101010", "010101010", "010101010", "010101010", "010000010", "001111100"),
    "lock": ("000111000", "001000100", "010000010", "010111010", "010101010", "010111010", "010000010", "001000100", "000111000"),
    "star": ("000010000", "000010000", "001111100", "111101111", "011111110", "001111100", "001101100", "010000010", "100000001"),
    "document": ("011111100", "010000100", "010110100", "010110100", "010000100", "010110100", "010110100", "010000100", "011111100"),
    "filter": ("111111111", "011111110", "001111100", "000111000", "000111000", "000010000", "000010000", "000010000", "000000000"),
    "sun": ("000010000", "001010100", "000111000", "010111010", "001111100", "010111010", "000111000", "001010100", "000010000"),
    "moon": ("000111000", "001100000", "011000000", "110000000", "110000000", "110001100", "011001100", "001111000", "000000000"),
    "spark": ("000010000", "000111000", "000010000", "010010010", "001111100", "000010000", "000101000", "001000100", "000000000"),
}


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
    pitch = size / 9
    radius = max(0.82, pitch * .38)
    pieces = []
    for row, bits in enumerate(grid):
        for col, bit in enumerate(bits):
            if bit == "1":
                pieces.append(f'<circle cx="{x+(col+.5)*pitch:.2f}" cy="{y+(row+.5)*pitch:.2f}" r="{radius:.2f}" fill="{color}"/>')
    return "".join(pieces)


def button(x, y, w, label, icon=None, primary=False, selected=False, danger=False, h=42, icon_only=False, pressed=False, disabled=False):
    kind = "danger" if danger else "primary" if primary or selected else "quiet"
    radius = min(w/2, max(14, h*.38))
    glow = (f'<rect x="-5" y="-3" width="{w+10}" height="{h+13}" rx="{radius+5}" '
            'fill="url(#warmGlow)" filter="url(#blurGlow)" opacity=".48"/>'
            f'<ellipse cx="{w-19}" cy="8" rx="20" ry="10" fill="var(--warmEdge)" opacity=".46" filter="url(#blurGlow)"/>') if (primary or selected) and not disabled else ""
    # All button roles share the same optical body; only the focused action receives warm light.
    opacity = ".48" if disabled else "1"
    out = [f'<g transform="translate({x} {y})" class="button-{kind}" opacity="{opacity}">', glow]
    shadow_y, shadow_alpha = (1, ".14") if pressed else (3, ".30")
    face_y = 1 if pressed else .5
    out.append(f'<rect x="1" y="{shadow_y}" width="{w-1}" height="{h}" rx="{radius}" fill="var(--shadow)" opacity="{shadow_alpha}" filter="url(#softShadow)"/>')
    out.append(f'<rect x="0.5" y="{face_y}" width="{w-1}" height="{h-1}" rx="{radius}" fill="url(#buttonFace)" stroke="var(--edgeStrong)" stroke-width="1"/>')
    if (primary or selected) and not disabled:
        out.append(f'<rect x="1" y="1" width="{w-2}" height="{h-2}" rx="{max(11,radius-1)}" fill="url(#warmGlow)" opacity=".34"/>')
    out.append(f'<path d="M{min(14,w/2)} 1H{w-min(14,w/2)}" stroke="white" stroke-opacity=".80" stroke-width="1"/>')
    if primary or selected:
        out.append(f'<path d="M{w-20} 1H{w-9}" stroke="var(--warmEdge)" stroke-opacity=".82" stroke-width="1.4"/>')
    if danger:
        out.append(f'<path d="M{w-28} 1H{w-10}" stroke="var(--danger)" stroke-opacity=".62" stroke-width="1.4"/>')
    if pressed:
        out.append(f'<path d="M{radius} 2H{w-radius}" stroke="var(--line)" stroke-opacity=".48" stroke-width="1"/>')
    if icon:
        if icon_only:
            isize = 27 if h >= 72 else 20
            ix, iy = (w-isize)/2, (h-isize)/2
        else:
            ix, iy, isize = 14, (h-20)/2, 20
        out.append(glyph(icon, ix, iy, isize, "var(--dangerInk)" if danger else "var(--glyph)"))
    if label and not icon_only:
        out.append(txt(44 if icon else 16, h/2+5, label, 13, "var(--ink)", 570 if primary or selected else 510))
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


def defs(dark=False):
    if dark:
        vars_ = """
        --scene0:#0a0a0c; --scene1:#0a0a0c; --scene2:#1e2025; --warm:#8b9aff;
        --warmEdge:#a7b3ff; --ink:#efeff3; --muted:#b8bac5; --line:#35363e;
        --glyph:#d3c5aa; --panelTop:#41434c; --panelBottom:#242630; --panelEdge:#60626d;
        --edgeStrong:#70717b; --shadow:#101116; --inset:#111216; --insetEdge:#35363e;
        --good:#a2d6bc; --danger:#f2a09d; --dangerInk:#f2a09d;
        """
    else:
        vars_ = """
        --scene0:#e6e6e8; --scene1:#e6e6e8; --scene2:#f4f4f6; --warm:#b06520;
        --warmEdge:#ffca73; --ink:#27272f; --muted:#656571; --line:#c9c9d2;
        --glyph:#4f493b; --panelTop:#ffffff; --panelBottom:#ececf0; --panelEdge:#fafafd;
        --edgeStrong:#ffffff; --shadow:#5a596f; --inset:#d4d4dc; --insetEdge:#c9c9d2;
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
      <radialGradient id="skyGlow" cx=".92" cy="-.08" r="1.5"><stop offset="0" stop-color="var(--scene2)" stop-opacity=".50"/><stop offset=".48" stop-color="var(--scene2)" stop-opacity=".20"/><stop offset="1" stop-color="var(--scene2)" stop-opacity="0"/></radialGradient>
      <pattern id="sceneGrain" width="128" height="128" patternUnits="userSpaceOnUse">{grain_pattern}</pattern>
      <linearGradient id="panel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--panelTop)" stop-opacity=".90"/><stop offset=".46" stop-color="var(--panelTop)" stop-opacity=".82"/><stop offset="1" stop-color="var(--panelBottom)" stop-opacity=".88"/></linearGradient>
      <linearGradient id="buttonFace" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--panelTop)" stop-opacity=".95"/><stop offset=".52" stop-color="var(--panelTop)" stop-opacity=".82"/><stop offset="1" stop-color="var(--panelBottom)" stop-opacity=".94"/></linearGradient>
      <linearGradient id="inset" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--inset)"/><stop offset="1" stop-color="var(--scene0)"/></linearGradient>
      <linearGradient id="warmGlow" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="var(--warmEdge)" stop-opacity=".9"/><stop offset=".52" stop-color="var(--warm)" stop-opacity=".34"/><stop offset="1" stop-color="var(--warm)" stop-opacity="0"/></linearGradient>
      <filter id="softShadow" x="-25%" y="-25%" width="150%" height="170%"><feGaussianBlur stdDeviation="5"/></filter>
      <filter id="blurGlow" x="-40%" y="-50%" width="180%" height="200%"><feGaussianBlur stdDeviation="8"/></filter>
      <clipPath id="windowClip"><rect x="16" y="16" width="1328" height="868" rx="20"/></clipPath>
      <style>:root {{{vars_}}} text {{font-synthesis:none}} .button-primary {{}} .button-danger {{}}</style>
    </defs>
    """


def shell(title, active="全部功能", subtitle=None, dark=False, search=True, mini=False):
    p = ['<svg xmlns="http://www.w3.org/2000/svg" width="1360" height="900" viewBox="0 0 1360 900">', defs(dark)]
    p.append('<rect width="1360" height="900" fill="#151519"/>')
    p.append('<g clip-path="url(#windowClip)"><rect x="16" y="16" width="1328" height="868" fill="url(#scene)"/><rect x="16" y="16" width="1328" height="868" fill="url(#skyGlow)"/><rect x="16" y="16" width="1328" height="868" fill="url(#sceneGrain)" opacity=".42"/>')
    p.append('<rect x="16" y="16" width="1328" height="42" fill="var(--panelBottom)" opacity=".30"/><path d="M16 58H1344M240 58V884" stroke="var(--line)" stroke-opacity=".72"/>')
    for x, c in ((42,"#f26a5f"),(66,"#f0c34d"),(90,"#49bd6c")):
        p.append(f'<circle cx="{x}" cy="37" r="7" fill="{c}"/>')
    p.append(txt(112,42,"Aggregate",15,"var(--muted)",620))
    p.append(glyph("connection",42,91,17))
    p.append(txt(67,106,"Aggregate",19,"var(--ink)",680))
    p.append(txt(40,153,"我的连接",11,"var(--muted)",560))
    for i, (label, icon) in enumerate((("网易云音乐","music"),("Git CLI","terminal"),("项目 MCP","connection"))):
        y=176+i*42
        p.append(txt(49,y+17,label,13,"var(--ink)",480))
        p.append(f'<circle cx="219" cy="{y+12}" r="2.5" fill="var(--good)"/>')
        if active==label:
            p.append(rect(32,y-5,192,34,"url(#panel)",10,"var(--panelEdge)"))
            p.append(glyph(icon,46,y+2,16))
            p.append(txt(70,y+17,label,13,"var(--ink)",560))
    p.append(line(32,316,224,316))
    for i,(label,icon) in enumerate((("所有功能","search"),("管理连接","connection"),("活动","history"))):
        y=346+i*43
        if active==label:
            p.append(rect(32,y-12,192,34,"url(#panel)",10,"var(--panelEdge)"))
            p.append(f'<path d="M38 {y-7}V{y+5}" stroke="var(--warmEdge)" stroke-width="2" stroke-linecap="round"/>')
        p.append(glyph(icon,48,y-5,17))
        p.append(txt(73,y+10,label,13,"var(--ink)",560 if active==label else 460))
    p.append(rect(32,807,192,38,"url(#panel)",11,"var(--panelEdge)" if active=="设置" else "var(--panelEdge)"))
    p.append(glyph("settings",47,817,17))
    p.append(txt(72,833,"设置",13,"var(--ink)",560 if active=="设置" else 460))
    p.append(tag(41,870,"本机工作空间"))
    if search:
        p.append(rect(984,69,326,38,"url(#panel)",12,"var(--panelEdge)"))
        p.append(glyph("search",1000,79,18))
        p.append(txt(1028,93,"搜索功能…",12,"var(--muted)",450))
        p.append(txt(1292,93,"⌘ K",11,"var(--muted)",520,"end"))
    p.append(txt(280,127,title,25,"var(--ink)",690))
    if subtitle:
        p.append(txt(281,153,subtitle,12,"var(--muted)",440))
    if mini:
        p.append(rect(270,812,1048,58,"url(#panel)",15,"var(--panelEdge)"))
        p.append(glyph("music",290,830,21))
        p.append(txt(322,835,"示例歌曲",14,"var(--ink)",570))
        p.append(txt(322,853,"网易云音乐 · 示例歌手 · 0:12 / 3:20",10,"var(--muted)",430))
        for i,(ico,lab) in enumerate((("previous",""),("pause",""),("next",""),("refresh",""),("close",""))):
            p.append(button(1055+i*48,820,40,lab,ico,primary=(ico=="pause"),h=40,icon_only=True))
    return p


def heading(p, x, y, name, hint=None):
    p.append(txt(x,y,name,16,"var(--ink)",650))
    if hint: p.append(txt(x,y+21,hint,11,"var(--muted)",430))


def small_button(p, x, y, label, icon=None, primary=False, danger=False, w=None):
    w = w or max(86, len(label)*14+44)
    p.append(button(x,y,w,label,icon,primary=primary,danger=danger,h=38))


def row(p, x, y, w, title, sub, icon="document", selected=False, right=None, height=56):
    if selected: p.append(rect(x,y,w,height,"url(#panel)",11,"var(--warmEdge)"))
    else: p.append(line(x+2,y+height,w+x-2,y+height,"var(--line)",1,.65))
    p.append(glyph(icon,x+13,y+15,19))
    p.append(txt(x+42,y+24,title,13,"var(--ink)",560 if selected else 480))
    if sub: p.append(txt(x+42,y+42,sub,10,"var(--muted)",430))
    if right: p.append(txt(x+w-12,y+24,right,10,"var(--muted)",480,"end"))


def screen_workspace():
    p=shell("所有功能","所有功能","搜索并运行当前连接提供的功能",mini=True)
    p.append(field(280,174,570,"","搜索名称、说明或来源",42,"search"))
    for i,(label,sel) in enumerate((("全部",1),("CLI",0),("MCP 工具",0),("资源",0),("提示",0))):
        p.append(button(280+i*103,229,92,label,selected=bool(sel),h=34))
    heading(p,280,302,"功能目录","最近使用 · 收藏 · 全部")
    p.append(txt(570,302,"12 项",11,"var(--muted)",450,"end"))
    for i,(name,sub,icon) in enumerate((("查看 Git 状态","CLI · 示例 Git CLI","terminal"),("读取项目说明","资源 · 示例 MCP","folder"),("两个整数相加","MCP 工具 · 示例 MCP","spark"),("搜索歌曲","CLI · 网易云音乐","music"),("继续播放","CLI · 网易云音乐","play"),("暂停播放","CLI · 网易云音乐","pause"),("生成摘要提示","提示 · 示例 MCP","document"))):
        row(p,280,330+i*60,295,name,sub,icon,i==2, "☆",58)
    p.append(line(596,322,596,776,"var(--line)"))
    p.append(txt(624,353,"两个整数相加",20,"var(--ink)",680))
    p.append(tag(624,380,"示例 MCP · 只读"))
    p.append(txt(624,415,"使用此工具将两个整数相加。",12,"var(--muted)",430))
    heading(p,624,450,"参数","两个字段都会在执行前检查")
    p.append(field(624,486,332,"第一个整数","例如 12"))
    p.append(field(976,486,332,"第二个整数","例如 30"))
    small_button(p,624,544,"选择执行端","connection",w=142)
    small_button(p,776,544,"运行","play",primary=True,w=104)
    p.append(line(624,605,1308,605))
    heading(p,624,638,"运行结果","最近一次调用 · 预览数据")
    p.append(rect(624,663,684,105,"url(#inset)",12,"var(--insetEdge)"))
    p.append(txt(646,696,"结果会显示在这里",13,"var(--muted)",480))
    p.append(txt(646,722,"结构化输出、复制与文件操作只在结果提供时出现。",11,"var(--muted)",430))
    return p+["</g></svg>"]


def screen_connection_home(mcp=False):
    title="UI 检查 · MCP" if mcp else "UI 检查 · Git CLI"
    p=shell(title,title,"查看当前连接提供的能力与最近结果",mini=True)
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
        for i,(name,sub,icon) in enumerate((("查看 Git 状态","显示当前分支与工作区状态","terminal"),("读取项目说明","输出 README 主要内容","document"),("查看最近提交","列出最近提交记录","history"))):
            row(p,280,236+i*68,306,name,sub,icon,i==0,height=60)
    p.append(line(609,204,609,775))
    p.append(txt(642,242,"两个整数相加" if mcp else "查看 Git 状态",20,"var(--ink)",680))
    p.append(tag(642,269,"预览连接 · 仅内存数据"))
    p.append(txt(642,304,"连接参数与结果只显示实际提供的内容。",12,"var(--muted)",440))
    if mcp:
        heading(p,642,352,"参数","来自当前工具输入 schema")
        p.append(field(642,386,320,"第一个整数","请输入数字"))
        p.append(field(978,386,320,"第二个整数","请输入数字"))
        action_y, result_line_y, result_head_y, result_box_y = 442, 502, 535, 561
    else:
        heading(p,642,352,"运行","此能力无需输入参数")
        p.append(rect(642,384,656,44,"url(#inset)",11,"var(--insetEdge)"))
        p.append(glyph("terminal",658,396,18,"var(--muted)"))
        p.append(txt(686,411,"直接检查当前仓库的 Git 状态",12,"var(--muted)",450))
        action_y, result_line_y, result_head_y, result_box_y = 442, 502, 535, 561
    small_button(p,642,action_y,"选择执行端","connection",w=142)
    small_button(p,794,action_y,"运行","play",primary=True,w=104)
    p.append(line(642,result_line_y,1298,result_line_y))
    heading(p,642,result_head_y,"最近结果","不会把参数正文写入活动记录")
    p.append(rect(642,result_box_y,656,142,"url(#inset)",12,"var(--insetEdge)"))
    p.append(txt(664,result_box_y+32,"尚无最近结果",13,"var(--muted)",480))
    p.append(txt(664,result_box_y+59,"运行后在此查看输出、状态和可用操作。",11,"var(--muted)",430))
    return p+["</g></svg>"]


def screen_connections():
    p=shell("管理连接","管理连接","查看连接状态、诊断与可执行的管理操作",mini=True)
    small_button(p,1160,115,"添加连接","plus",primary=True,w=148)
    heading(p,280,203,"连接列表","选择连接查看详情 · 使用操作调整顺序")
    for i,(name,sub) in enumerate((("UI 检查 · Git CLI","CLI 程序 · 本机 · 就绪"),("UI 检查 · MCP","远程 MCP · 本机 · 就绪"),("UI 检查 · 音乐","CLI 程序 · 本机 · 就绪"))):
        y=230+i*70
        p.append(rect(280,y,285,60,"url(#panel)" if i==0 else "url(#buttonFace)",12,"var(--warmEdge)" if i==0 else "var(--panelEdge)"))
        p.append(tag(294,y+22,"就绪"))
        p.append(txt(318,y+25,name,13,"var(--ink)",570 if i==0 else 500))
        p.append(txt(294,y+46,sub,10,"var(--muted)",430))
    p.append(line(589,201,589,780))
    p.append(txt(624,242,"UI 检查 · Git CLI",20,"var(--ink)",680))
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


def screen_activity():
    p=shell("活动","活动","查看近期运行状态；活动不保存参数或结果正文")
    cursor=280
    for label,width,selected in (("全部",66,1),("运行中",78,0),("成功",66,0),("失败",66,0),("取消",66,0),("超时",66,0),("待确认",84,0)):
        p.append(button(cursor,181,width,label,selected=bool(selected),h=34))
        cursor+=width+8
    heading(p,280,251,"运行记录","按发生时间倒序")
    for i,(name,sub,state) in enumerate((("查看 Git 状态","今天 16:42 · UI 检查 · Git CLI","成功"),("两个整数相加","今天 15:18 · UI 检查 · MCP","成功"),("搜索歌曲","今天 14:52 · UI 检查 · 音乐","取消"),("读取项目说明","昨天 18:06 · UI 检查 · MCP","失败"),("查看最近提交","昨天 17:44 · UI 检查 · Git CLI","超时"))):
        y=277+i*66
        row(p,280,y,370,name,sub,"document",i==0,state,58)
    p.append(line(672,249,672,764))
    p.append(txt(708,286,"查看 Git 状态",19,"var(--ink)",650))
    p.append(tag(708,314,"成功")); p.append(txt(768,314,"今天 16:42 · 示例 Git CLI",11,"var(--muted)",430))
    p.append(line(708,342,1298,342))
    heading(p,708,378,"运行信息")
    for i,(k,v) in enumerate((("来源","示例 Git CLI"),("时间","今天 16:42"),("运行 ID","run-preview-001"))):
        y=411+i*38; p.append(txt(708,y,k,11,"var(--muted)",450)); p.append(txt(816,y,v,12,"var(--ink)",480))
    p.append(txt(708,553,"参数与结果正文不会写入活动记录。",11,"var(--muted)",430))
    small_button(p,708,592,"重新打开功能","folder",primary=True,w=164)
    small_button(p,882,592,"复制诊断","document",w=126)
    return p+["</g></svg>"]


def settings_shell(title, selected):
    p=shell("设置","设置","让材质、光线和工作方式保持一致")
    p.append(line(489,182,489,780))
    for i,label in enumerate(("外观","Mac Host","快捷键","本机数据")):
        y=206+i*50
        if label==selected: p.append(rect(298,y-16,178,38,"url(#panel)",11,"var(--warmEdge)"))
        p.append(glyph(("sun","connection","terminal","history")[i],311,y-5,17))
        p.append(txt(340,y+9,label,13,"var(--ink)",570 if label==selected else 450))
    p.append(txt(523,204,title,17,"var(--ink)",650))
    return p


def screen_appearance():
    p=settings_shell("外观","外观")
    p.append(txt(523,232,"拖动玻璃控件，在浅色和深色之间切换。",12,"var(--muted)",440))
    p.append(txt(523,280,"当前模式",11,"var(--muted)",440)); p.append(txt(604,280,"浅色",13,"var(--ink)",560))
    p.extend(switch_art(670,326,490,244))
    p.append(txt(523,662,"切换控件保持原始实时拖动、方向反转与太阳/月亮内部变化。",11,"var(--muted)",430))
    small_button(p,523,699,"跟随 macOS 系统","settings",w=178)
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
    p=settings_shell("Mac Host","Mac Host")
    p.append(tag(523,233,"运行中"))
    p.append(txt(523,265,"允许已配对设备在 Mac 上运行获准的功能。",12,"var(--muted)",440))
    p.append(button(1178,214,120,"停止 Host","stop",danger=True,h=40))
    p.append(button(1118,263,180,"轮换 Mac Host 身份","lock",danger=True,h=40))
    p.append(line(523,294,1298,294))
    heading(p,523,326,"配对邀请","二维码只包含短时邀请和 Host 地址，不含长期设备密钥。")
    small_button(p,1147,301,"生成新邀请","plus",primary=True,w=151)
    p.append(rect(523,356,775,174,"url(#panel)",13,"var(--panelEdge)"))
    p.extend(qr_placeholder(543,376,132))
    p.append(txt(704,392,"邀请于 16:30 到期",13,"var(--ink)",520))
    p.append(txt(704,416,"2 个本机网络地址",11,"var(--muted)",430))
    small_button(p,704,438,"复制配对信息","document",w=151)
    p.append(line(523,548,1298,548))
    p.append(txt(523,579,"待处理设备",16,"var(--ink)",650))
    p.append(txt(523,599,"核对设备与确认码后再审批",10,"var(--muted)",430))
    p.append(button(1260,561,38,"","refresh",h=38,icon_only=True))
    p.append(rect(523,612,775,68,"url(#panel)",13,"var(--panelEdge)"))
    p.append(glyph("connection",535,625,18)); p.append(txt(566,635,"LGE AN10",12,"var(--ink)",560))
    p.append(txt(566,656,"Android · 确认码 4D8K2P",9,"var(--muted)",430))
    action_x=755
    for label,icon,width,primary,danger in (("拒绝","close",82,False,True),("批准只读","check",104,False,False),("允许连接向导","settings",144,True,False),("自定义权限","settings",126,False,False)):
        p.append(button(action_x,626,width,label,icon,primary=primary,danger=danger,h=40))
        action_x+=width+6
    p.append(txt(523,712,"已配对设备",16,"var(--ink)",650))
    p.append(txt(523,732,"权限可随时编辑或撤销",10,"var(--muted)",430))
    p.append(rect(523,744,775,48,"url(#panel)",12,"var(--panelEdge)"))
    p.append(glyph("connection",536,758,18)); p.append(txt(565,768,"Pixel 9 · Android · 读取连接",11,"var(--ink)",520))
    small_button(p,1059,750,"修改权限","settings",w=112)
    small_button(p,1178,750,"撤销","close",danger=True,w=120)
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
    p=settings_shell("快捷键","快捷键")
    p.append(txt(523,232,"名称与组合键沿用当前快捷键配置。",12,"var(--muted)",440))
    for i,(group,items) in enumerate((("导航",(("打开所有功能","⌘ K"),("打开设置","⌘ ,"),("返回","Esc"))), ("运行",(("执行当前操作","⌘ ↵"),)))):
        y=276+i*216
        heading(p,523,y,group)
        for j,(name,key) in enumerate(items):
            yy=y+35+j*48
            p.append(txt(523,yy,name,13,"var(--ink)",460))
            p.append(txt(1290,yy,key,12,"var(--muted)",540,"end"))
            p.append(line(523,yy+16,1298,yy+16,"var(--line)",1,.6))
    return p+["</g></svg>"]


def screen_local_data():
    p=settings_shell("本机数据","本机数据")
    p.append(txt(523,232,"连接配置与活动记录保存在本机。",12,"var(--muted)",440))
    heading(p,523,287,"活动保留时长","仅保存脱敏后的运行状态信息")
    p.append(txt(523,330,"保留最近",12,"var(--muted)",440))
    p.append(rect(1075,302,223,44,"url(#panel)",11,"var(--panelEdge)")); p.append(txt(1093,330,"30 天",13,"var(--ink)",500)); p.append(txt(1279,330,"⌄",14,"var(--muted)",500,"end"))
    p.append(line(523,374,1298,374))
    heading(p,523,414,"清空活动记录","只删除本机保存的调用历史，不移除连接")
    p.append(txt(523,456,"删除后无法恢复。",11,"var(--muted)",430))
    small_button(p,1134,427,"清空记录","trash",danger=True,w=164)
    return p+["</g></svg>"]


def screen_setup():
    p=shell("添加连接","管理连接","设置连接类型、执行目标与认证信息")
    p.append('<rect x="16" y="58" width="1328" height="826" fill="#242329" opacity=".24"/>')
    x,y,w,h=356,116,648,668
    p.append(rect(x,y,w,h,"url(#panel)",20,"var(--panelEdge)",1.4))
    p.append(txt(x+30,y+40,"第 2 步 · 配置连接",20,"var(--ink)",670)); p.append(txt(x+30,y+64,"填写连接信息，测试通过后即可保存。",11,"var(--muted)",430))
    p.append(rect(x+30,y+83,w-60,54,"url(#buttonFace)",12,"var(--panelEdge)"))
    p.append(glyph("connection",x+44,y+101,18))
    p.append(txt(x+73,y+104,"执行设备",10,"var(--muted)",500))
    p.append(txt(x+73,y+124,"本机 Mac",13,"var(--ink)",550))
    p.append(line(x+30,y+151,x+w-30,y+151))
    p.append(txt(x+30,y+170,"适配器",10,"var(--muted)",520))
    p.append(rect(x+30,y+180,w-60,42,"url(#inset)",10,"var(--insetEdge)"))
    p.append(txt(x+45,y+207,"CLI 程序",13,"var(--ink)",500)); p.append(txt(x+w-48,y+207,"⌄",14,"var(--muted)",500,"end"))
    p.append(field(x+30,y+233,w-60,"名称","Git CLI",44))
    p.append(field(x+30,y+289,w-112,"程序绝对路径","/usr/bin/git",44))
    p.append(button(x+w-72,y+289,42,"", "folder", h=44, icon_only=True))
    p.append(field(x+30,y+345,w-60,"启动参数 JSON 数组","[]",58))
    p.append(field(x+30,y+415,w-60,"工作目录（可选）","留空使用默认目录",44))
    p.append(field(x+30,y+471,w-60,"动作清单 JSON（可选）","选择文件…",44))
    p.append(glyph("refresh",x+30,y+538,14,"var(--muted)"))
    p.append(txt(x+52,y+550,"测试后显示诊断；测试可保存时才启用保存。",10,"var(--muted)",430))
    p.append(line(x+30,y+570,x+w-30,y+570))
    small_button(p,x+w-332,y+593,"取消","close",w=92)
    small_button(p,x+w-238,y+593,"测试连接","refresh",w=126)
    # Disabled until the connection check reports a saveable result.
    p.append(button(x+w-128,y+593,98,"保存连接", "check", primary=True, h=38, disabled=True))
    return p+["</g></svg>"]


def overlay(title,subtitle,w,h):
    p=shell("所有功能","所有功能",search=False,mini=False)
    p.append('<rect x="16" y="58" width="1328" height="826" fill="#24232a" opacity=".28"/>')
    x=(W-w)/2; y=(H-h)/2+12
    p.append(rect(x,y,w,h,"url(#panel)",20,"var(--panelEdge)",1.4))
    p.append(txt(x+30,y+42,title,19,"var(--ink)",680))
    if subtitle: p.append(txt(x+30,y+66,subtitle,11,"var(--muted)",430))
    return p,x,y,w,h


def screen_permission():
    p,x,y,w,h=overlay("确认执行","检查执行目标与参数后再继续。",560,520)
    fields=(("功能","演示写入权限确认"),("来源","UI 检查 · Git CLI"),("执行目标","本机 Mac"),("权限","需要外部写入"))
    yy=y+105
    for label,value in fields:
        p.append(txt(x+32,yy,label,10,"var(--muted)",520)); p.append(txt(x+158,yy,value,12,"var(--ink)",520)); yy+=38
    p.append(line(x+32,yy-10,x+w-32,yy-10))
    p.append(txt(x+32,yy+22,"输入参数",10,"var(--muted)",520))
    p.append(rect(x+32,yy+38,w-64,80,"url(#inset)",11,"var(--insetEdge)"))
    p.append(txt(x+48,yy+62,'{"message":"preview only"}',11,"var(--ink)",450))
    p.append(txt(x+32,yy+145,"请确认目标与输入内容。外部写入可能无法撤回。",10,"var(--danger)",500))
    small_button(p,x+w-244,y+h-60,"取消","close",w=98)
    small_button(p,x+w-136,y+h-60,"确认执行","play",primary=True,w=108)
    return p+["</g></svg>"]


def screen_danger_confirmation():
    p,x,y,w,h=overlay("清空本机活动记录？","请确认后继续。",520,330)
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
    p,x,y,w,h=overlay("选择执行目标","选择此连接实际可用的设备。",585,390)
    row(p,x+28,y+103,w-56,"本机 Mac","默认目标 · 在此设备运行","connection",True,None,61)
    row(p,x+28,y+171,w-56,"Pixel 9","已配对 · 连接管理","connection",False,None,61)
    p.append(txt(x+30,y+273,"设备状态与授权说明来自当前运行时。",10,"var(--muted)",430))
    small_button(p,x+w-230,y+h-57,"取消","close",w=94)
    small_button(p,x+w-126,y+h-57,"选择","check",primary=True,w=96)
    return p+["</g></svg>"]


def screen_action_editor():
    p,x,y,w,h=overlay("编辑动作 · UI 检查 · Git CLI","清单版本 1 · 参数以数组传递。",680,700)
    small_button(p,x+30,y+88,"新增动作","plus",primary=True,w=134)
    small_button(p,x+175,y+88,"导入","folder",w=102)
    small_button(p,x+287,y+88,"导出","document",w=102)
    p.append(txt(x+30,y+153,"动作清单 JSON",11,"var(--muted)",520))
    p.append(rect(x+30,y+167,w-60,300,"url(#inset)",12,"var(--insetEdge)"))
    code='''{\n  "schemaVersion": 1,\n  "id": "git-version",\n  "displayName": "UI 检查",\n  "executable": "仅内存预览",\n  "actions": [\n    {\n      "id": "version",\n      "title": "查看版本",\n      "argv": ["--version"]\n    }\n  ]\n}'''
    for i,line_ in enumerate(code.splitlines()): p.append(txt(x+48,y+194+i*20,line_,11,"var(--ink)",440))
    p.append(txt(x+30,y+490,"预览动作",10,"var(--muted)",520)); p.append(txt(x+30,y+516,"查看版本 · version",13,"var(--ink)",560))
    p.append(txt(x+350,y+490,"预览输入 JSON",10,"var(--muted)",520)); p.append(rect(x+350,y+500,300,55,"url(#inset)",10,"var(--insetEdge)")); p.append(txt(x+367,y+532,"{}",12,"var(--ink)",450))
    p.append(txt(x+30,y+558,"检查只生成最终参数数组，不运行程序。",10,"var(--muted)",430))
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
    p.append(txt(48,145,"UI 检查 · Git CLI   $ git status --short",12,"var(--ink)",520))
    p.append(txt(48,166,"执行端：本机 Mac · 权限：读取连接 · 交互会话",10,"var(--muted)",430))
    p.append(button(1270,78,42,"","stop",danger=True,h=42,icon_only=True))
    p.append(rect(32,184,1296,508,"#17181c",15,"#555660",1))
    for i,line_ in enumerate(("$ git status --short"," M README.md","?? draft.md","","█")):
        p.append(txt(58,226+i*27,line_,13,"#d7dccf" if i else "#d8bd8c",450))
    labels=(("Ctrl",64),("Esc",64),("Tab",64),("↑",52),("↓",52),("←",52),("→",52),("复制",90),("粘贴",90))
    cursor=32
    for i,(label,width) in enumerate(labels):
        p.append(button(cursor,718,width,label,"terminal" if label=="Ctrl" else None,selected=(label=="Ctrl"),h=40))
        cursor+=width+10
    return p+["</g></svg>"]


def screen_result():
    p=shell("所有功能","所有功能","查看当前能力本次调用的实际状态和输出",mini=True)
    p.append(field(280,174,570,"","搜索名称、说明或来源",42,"search"))
    for i,(label,sel) in enumerate((("全部",1),("CLI",0),("MCP 工具",0),("资源",0),("提示",0))):
        p.append(button(280+i*103,229,92,label,selected=bool(sel),h=34))
    heading(p,280,302,"功能目录","最近使用 · 收藏 · 全部")
    row(p,280,330,295,"查看 Git 状态","CLI · UI 检查 · Git CLI","terminal",True,"☆",58)
    row(p,280,390,295,"读取项目说明","资源 · UI 检查 · MCP","document",False,"☆",58)
    p.append(line(596,322,596,776,"var(--line)"))
    p.append(txt(624,353,"查看 Git 状态",20,"var(--ink)",680))
    p.append(tag(624,380,"UI 检查 · Git CLI · 成功"))
    p.append(txt(624,415,"结果保留在当前能力详情中，不跳转到独立结果页。",11,"var(--muted)",430))
    p.append(txt(624,468,"结果",16,"var(--ink)",620))
    p.append(tag(1152,468,"成功"))
    p.append(button(1247,437,46,"","document",h=40,icon_only=True))
    p.append(rect(624,486,684,244,"url(#inset)",12,"var(--insetEdge)"))
    for i,line_ in enumerate(("{","  \"branch\": \"main\",","  \"clean\": false,","  \"changes\": 2","}")):
        p.append(txt(646,523+i*27,line_,13,"var(--ink)",460))
    return p+["</g></svg>"]


def screen_states():
    p=shell("通用状态","所有功能","状态文案和操作必须对应真实运行时信息")
    cards=(("加载中","连接正在准备，请稍候。","refresh"),("没有连接","添加一个连接后即可运行功能。","connection"),("没有匹配","尝试更短的搜索词。","search"),("连接失败","检查连接设置或重新测试。","close"))
    for i,(title,copy,icon) in enumerate(cards):
        x=280+(i%2)*525; y=190+(i//2)*275
        p.append(rect(x,y,490,220,"url(#panel)",17,"var(--panelEdge)"))
        p.append(glyph(icon,x+26,y+34,25))
        p.append(txt(x+26,y+94,title,18,"var(--ink)",650))
        p.append(txt(x+26,y+121,copy,11,"var(--muted)",430))
        small_button(p,x+26,y+157,"查看下一步","next",primary=i==1,w=142)
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
    p=shell("所有功能","所有功能","深色模式保持玻璃厚度与点阵清晰度",dark=True,mini=True)
    p.append(field(280,174,570,"","搜索名称、说明或来源",42,"search"))
    for i,(label,sel) in enumerate((("全部",1),("CLI",0),("MCP 工具",0),("资源",0),("提示",0))): p.append(button(280+i*103,229,92,label,selected=bool(sel),h=34))
    heading(p,280,302,"功能目录","最近使用 · 收藏 · 全部")
    for i,(name,sub,icon) in enumerate((("查看 Git 状态","CLI · 示例 Git CLI","terminal"),("读取项目说明","资源 · 示例 MCP","folder"),("两个整数相加","MCP 工具 · 示例 MCP","spark"))): row(p,280,330+i*65,295,name,sub,icon,i==2,"☆",58)
    p.append(line(600,322,600,770))
    p.append(txt(630,354,"两个整数相加",20,"var(--ink)",680)); p.append(tag(630,381,"示例 MCP · 只读"))
    p.append(field(630,425,320,"第一个整数","例如 12")); p.append(field(968,425,320,"第二个整数","例如 30"))
    small_button(p,630,493,"选择执行端","connection",w=142); small_button(p,782,493,"运行","play",primary=True,w=104)
    p.append(rect(630,562,658,128,"url(#inset)",12,"var(--insetEdge)")); p.append(txt(650,599,"输出将显示在这里",12,"var(--muted)",460))
    return p+["</g></svg>"]


def screen_music():
    p=shell("网易云音乐","网易云音乐","播放、搜索和账号状态来自同一音乐会话")
    p.append(rect(280,188,468,530,"url(#panel)",19,"var(--panelEdge)"))
    p.append(txt(310,224,"播放器",16,"var(--ink)",620)); p.append(tag(672,224,"播放中"))
    p.append(rect(310,248,150,150,"url(#inset)",18,"var(--insetEdge)")); p.append(glyph("music",354,292,60))
    p.append(txt(482,300,"示例歌曲",18,"var(--ink)",650)); p.append(txt(482,330,"示例歌手",12,"var(--muted)",450)); p.append(txt(482,356,"0:12 / 3:20",11,"var(--muted)",430))
    for i,ico in enumerate(("previous","pause","next","stop")): p.append(button(314+i*78,432,64,"",ico,primary=(ico=="pause"),h=58,icon_only=True))
    p.append(txt(310,534,"播放信息",11,"var(--muted)",500)); p.append(txt(310,558,"网易云音乐 · 本机输出",12,"var(--ink)",470))
    small_button(p,310,612,"刷新状态","refresh",w=132); small_button(p,452,612,"账号","connection",w=104)
    heading(p,786,220,"找音乐","搜索歌曲并查看结果")
    p.append(field(786,245,522,"","搜索歌曲",44,"search")); small_button(p,1174,299,"搜索","search",primary=True,w=134)
    for i,(name,sub) in enumerate((("示例歌曲一","示例歌手 · 3:20"),("示例歌曲二","示例歌手 · 4:02"),("示例歌曲三","示例歌手 · 2:48"))): row(p,786,365+i*70,522,name,sub,"music",False,"播放",62)
    return p+["</g></svg>"]


def screen_account():
    p,x,y,w,h=overlay("音乐账号","连接端支持时才会显示账号管理。",520,420)
    p.append(rect(x+30,y+95,w-60,90,"url(#inset)",13,"var(--insetEdge)"))
    p.append(glyph("connection",x+49,y+124,24)); p.append(txt(x+88,y+127,"尚未登录",14,"var(--ink)",560)); p.append(txt(x+88,y+151,"使用扫码登录并等待连接端确认。",10,"var(--muted)",430))
    p.append(rect(x+30,y+207,160,150,"#f2f0ec",12,"var(--panelEdge)")); p.append(txt(x+110,y+286,"二维码预览",10,"var(--muted)",440,"middle"))
    p.append(txt(x+214,y+238,"等待扫码",13,"var(--ink)",540)); p.append(txt(x+214,y+264,"刷新二维码后使用音乐客户端扫码。",10,"var(--muted)",430))
    small_button(p,x+214,y+291,"刷新二维码","refresh",w=142)
    small_button(p,x+w-231,y+h-57,"取消扫码","close",w=100)
    small_button(p,x+w-121,y+h-57,"登录","check",primary=True,w=92)
    return p+["</g></svg>"]


def screen_mini():
    p=shell("迷你播放器","活动","跨页控制当前音乐会话；无会话时隐藏")
    p.append(txt(280,211,"迷你播放器",19,"var(--ink)",650))
    p.append(txt(280,239,"固定在窗口底部，不覆盖正文或焦点。",11,"var(--muted)",430))
    p.append(rect(280,300,1028,176,"url(#panel)",20,"var(--panelEdge)"))
    p.append(glyph("music",310,352,26)); p.append(txt(355,357,"示例歌曲",18,"var(--ink)",620)); p.append(txt(355,383,"网易云音乐 · 示例歌手 · 0:12 / 3:20",11,"var(--muted)",430))
    for i,ico in enumerate(("previous","pause","next","stop","refresh","close")):
        p.append(button(792+i*76,354,58,"",ico,primary=(ico=="pause"),h=56,icon_only=True))
    p.append(txt(280,527,"上一首 / 下一首仅在连接提供对应动作且存在目标曲目时出现。",11,"var(--muted)",430))
    p.append(txt(280,550,"输入法打开或没有可见播放会话时按原逻辑隐藏。",11,"var(--muted)",430))
    return p+["</g></svg>"]


def screen_host_permissions():
    p,x,y,w,h=overlay("配置设备权限","全局范围与逐连接权限分开管理。",720,640)
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
    for i,(name,permissions) in enumerate((("UI 检查 · Git CLI",("读取","本机控制")),("UI 检查 · MCP",("读取",)),("UI 检查 · 音乐",("读取","外部写入")))):
        yy=y+414+i*52
        row(p,x+30,yy,w-60,name,"", "connection",False,None,46)
        bx=x+w-280
        for j,permission in enumerate(permissions):
            bw=84 if permission in {"本机控制","外部写入"} else 62
            p.append(button(bx,yy+5,bw,permission,selected=True,h=32))
            bx+=bw+6
    small_button(p,x+w-235,y+h-55,"取消","close",w=96)
    small_button(p,x+w-130,y+h-55,"保存权限","document",primary=True,w=110)
    return p+["</g></svg>"]


def screen_terminal_state():
    p=shell("所有功能","所有功能","先确认执行端状态，再决定是否重跑",mini=True)
    p.append(field(280,174,570,"","搜索名称、说明或来源",42,"search"))
    for i,(label,sel) in enumerate((("全部",1),("CLI",0),("MCP 工具",0),("资源",0),("提示",0))):
        p.append(button(280+i*103,229,92,label,selected=bool(sel),h=34))
    heading(p,280,302,"功能目录","收藏 · 最近使用 · 全部")
    row(p,280,330,295,"查看 Git 状态","CLI · UI 检查 · Git CLI","terminal",True,"☆",58)
    p.append(line(596,322,596,776,"var(--line)"))
    p.append(txt(624,353,"查看 Git 状态",20,"var(--ink)",680))
    p.append(tag(624,380,"结果待确认","warn"))
    p.append(txt(624,424,"操作可能已经发送，但没有收到最终确认。",16,"var(--ink)",600))
    p.append(txt(624,451,"先检查活动状态和执行端，再决定是否重跑。",12,"var(--muted)",460))
    p.append(rect(624,482,684,118,"url(#panel)",14,"var(--panelEdge)"))
    p.append(glyph("history",648,508,22)); p.append(txt(686,515,"本次运行状态尚未确认",13,"var(--ink)",560))
    p.append(txt(686,539,"为避免重复副作用，此状态不会直接提供重跑按钮。",11,"var(--muted)",440))
    small_button(p,624,624,"检查活动状态","search",primary=True,w=162)
    return p+["</g></svg>"]


def screen_mcp():
    return screen_connection_home(True)


def screen_by_name(name):
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
    }
    return mapping[name]()


def main():
    for name in (
        "01-workspace","02-music","03-connections","04-activity","05-settings-appearance",
        "06-settings-host","07-connection-setup","08-terminal-running","09-permission-confirmation",
        "10-states","11-button-motion","12-dark-reference","13-action-editor","14-music-account-login",
        "15-settings-shortcuts","16-result-success","17-connection-home","18-mini-player",
        "19-target-selector","20-host-permissions","21-mcp-home","22-settings-local-data","23-danger-confirmation","24-result-unknown",
    ):
        source="\n".join(screen_by_name(name))
        palette=DARK if name=="12-dark-reference" else LIGHT
        source=re.sub(r"var\(--([A-Za-z][A-Za-z0-9]*)\)",lambda match:palette[match.group(1)],source)
        source="\n".join(line.rstrip() for line in source.splitlines())+"\n"
        (OUT/f"{name}.svg").write_text(source,encoding="utf-8")
    index='''# Aggregate 全功能设计稿 v5.0 · 画板目录

所有画板均为 1360×900 logical px，统一使用同一窗口外壳、侧栏、页面留白、暖光玻璃按钮与 9×9 点阵图案。示例数据仅用于视觉展示。05 外观画板直接嵌入归档的 macOS Profile 开关截图，作为不可修改的材质和控件基准。

| 画板 | 页面 | 画板 | 页面 |
|---|---|---|---|
| [01](01-workspace.svg) | 所有功能 / 参数运行 | [12](12-dark-reference.svg) | 深色工作台 |
| [02](02-music.svg) | 音乐 | [13](13-action-editor.svg) | 动作 JSON 编辑 |
| [03](03-connections.svg) | 连接管理 | [14](14-music-account-login.svg) | 音乐账号 |
| [04](04-activity.svg) | 活动记录 | [15](15-settings-shortcuts.svg) | 快捷键 |
| [05](05-settings-appearance.svg) | 外观 | [16](16-result-success.svg) | 成功结果 |
| [06](06-settings-host.svg) | Mac Host | [17](17-connection-home.svg) | CLI 连接首页 |
| [07](07-connection-setup.svg) | 添加连接配置 | [18](18-mini-player.svg) | 迷你播放器 |
| [08](08-terminal-running.svg) | 交互终端 | [19](19-target-selector.svg) | 执行目标选择 |
| [09](09-permission-confirmation.svg) | 执行授权 | [20](20-host-permissions.svg) | Host 设备权限 |
| [10](10-states.svg) | 通用状态 | [21](21-mcp-home.svg) | MCP 连接首页 |
| [11](11-button-motion.svg) | 按钮与图案 | [22](22-settings-local-data.svg) | 本机数据 |
| [23](23-danger-confirmation.svg) | 危险操作确认 | [24](24-result-unknown.svg) | 结果待确认 |
'''
    (OUT/"README.md").write_text(index,encoding="utf-8")


if __name__ == "__main__":
    main()
