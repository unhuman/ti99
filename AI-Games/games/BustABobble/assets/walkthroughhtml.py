#!/usr/bin/env python3
"""
BUST-A-BOBBLE -- walkthrough.json  ->  a self-contained HTML round book.

Renders what solvelevels.py --report found: every round's opening board in the
game's real colours, and the shot-by-shot line that clears it.

The boards are drawn from the same data the cartridge holds, at the same hex
stagger (odd rows 7 wide, offset half a cell), and every board is drawn to the
SAME depth with the death line marked -- so how much headroom a round gives you
is comparable at a glance instead of being buried in a number.

Run:  python3 solvelevels.py --report        (first, to make walkthrough.json)
      python3 walkthroughhtml.py [out.html]
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
JSON = os.path.join(HERE, "walkthrough.json")

# Straight out of genart.py's BUBBLE table -- the colours the ROM draws.
CNAME = {1: "red", 2: "green", 3: "blue", 4: "yellow",
         5: "cyan", 6: "magenta", 7: "grey", 8: "white"}
CHEX = {1: "#e05c4a", 2: "#5cc85c", 3: "#5a5aec", 4: "#ded46a",
        5: "#5ad4e0", 6: "#c85ac8", 7: "#cccccc", 8: "#ffffff"}

# A bubble reaching this grid row ends the round at the starting ceiling
# (check_death: top + 2*row >= 18, so row 9 with top 0).
DEATHR = 9


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def board_html(grid):
    out = ['<div class="board" role="img" aria-label="opening board">']
    for r in range(DEATHR):
        p = r & 1
        out.append('<div class="brow%s">' % (" odd" if p else ""))
        for c in range(8 - p):
            k = grid[r * 8 + c] & 15
            if k:
                out.append('<i class="bub k%d" title="%s"></i>' % (k, CNAME[k]))
            else:
                out.append('<i class="bub e"></i>')
        out.append("</div>")
    out.append('<div class="deathline"><span>death line</span></div>')
    out.append("</div>")
    return "".join(out)


def dial(aim):
    """The launcher itself: a needle at the shot's real angle off vertical."""
    deg = (aim - 31) * 80.0 / 31.0
    return ('<span class="dial" aria-hidden="true">'
            '<i style="transform:rotate(%.1fdeg)"></i></span>' % deg)


def aim_words(aim, bl, br):
    d = aim - 31
    deg = abs(d) * 80.0 / 31.0
    if d == 0:
        s = "straight up"
    else:
        s = "%s&nbsp;%d <span class=\"deg\">%.0f&deg;</span>" % (
            "right" if d > 0 else "left", abs(d), deg)
    n = bl + br
    if n == 1:
        s += ' <span class="bank">%s bank</span>' % ("left" if bl else "right")
    elif n > 1:
        s += ' <span class="bank">%d banks</span>' % n
    return s


def result_html(ev):
    if ev["cell"] is None:
        return '<span class="res none">no contact</span>'
    if ev["pop"] == 0:
        return '<span class="res stick">sticks</span>'
    bits = '<span class="res pop">pops %d</span>' % ev["pop"]
    if ev["drop"]:
        bits += ' <span class="res drop">drops %d</span>' % ev["drop"]
    bits += ' <span class="pts">+%s</span>' % "{:,}".format(ev["pts"])
    return bits


CSS = """
:root{
  --void:#f4f6f8; --panel:#ffffff; --line:#d3dae2; --line2:#e6ebf0;
  --text:#161c24; --muted:#5c6a7a; --accent:#0f8a97; --accent-dim:#7fc3cb;
  --shadow:0 1px 2px rgba(18,28,40,.07),0 8px 24px -12px rgba(18,28,40,.18);
  --well:#0b0d10;
  --mono:ui-monospace,"SF Mono","Cascadia Mono",Menlo,Consolas,"Liberation Mono",monospace;
  --sans:system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    --void:#0b0d10; --panel:#151a21; --line:#2a3340; --line2:#1e252e;
    --text:#dfe6ee; --muted:#8b98a8; --accent:#5ad4e0; --accent-dim:#2b6b74;
    --shadow:0 1px 0 rgba(255,255,255,.03),0 18px 40px -24px rgba(0,0,0,.8);
  }
}
:root[data-theme="dark"]{
  --void:#0b0d10; --panel:#151a21; --line:#2a3340; --line2:#1e252e;
  --text:#dfe6ee; --muted:#8b98a8; --accent:#5ad4e0; --accent-dim:#2b6b74;
  --shadow:0 1px 0 rgba(255,255,255,.03),0 18px 40px -24px rgba(0,0,0,.8);
}

*{box-sizing:border-box}
body{
  margin:0; background:var(--void); color:var(--text);
  font-family:var(--sans); font-size:15px; line-height:1.6;
  -webkit-font-smoothing:antialiased;
}
.wrap{max-width:1120px;margin:0 auto;padding:0 20px 80px}

/* ---- masthead ------------------------------------------------------- */
.mast{padding:56px 0 28px;border-bottom:1px solid var(--line)}
.eyebrow{
  font-family:var(--mono); font-size:11px; letter-spacing:.16em;
  text-transform:uppercase; color:var(--muted); margin:0 0 14px;
}
h1{
  font-family:var(--mono); font-weight:600; font-size:clamp(30px,5.2vw,46px);
  letter-spacing:-.02em; line-height:1.05; margin:0 0 14px; text-wrap:balance;
}
h1 .dot{color:var(--accent)}
.lede{max-width:62ch;color:var(--muted);margin:0 0 26px}
.lede strong{color:var(--text);font-weight:600}

.stats{display:flex;flex-wrap:wrap;gap:34px;margin:0 0 30px;padding:0;list-style:none}
.stats div{display:flex;flex-direction:column;gap:2px}
.stats b{
  font-family:var(--mono); font-size:26px; font-weight:600;
  font-variant-numeric:tabular-nums; letter-spacing:-.02em;
}
.stats span{
  font-family:var(--mono); font-size:10.5px; letter-spacing:.14em;
  text-transform:uppercase; color:var(--muted);
}

.legend{display:flex;flex-wrap:wrap;gap:6px 18px;align-items:center}
.legend .lb{display:flex;align-items:center;gap:7px;font-size:12.5px;color:var(--muted)}
.legend .lb b{
  font-family:var(--mono);color:var(--text);font-weight:600;font-size:12px;
}

/* ---- index ---------------------------------------------------------- */
.index{
  position:sticky; top:0; z-index:5; background:var(--void);
  border-bottom:1px solid var(--line); padding:10px 0; margin-bottom:8px;
}
.index .row{display:flex;flex-wrap:wrap;gap:5px}
.index a{
  font-family:var(--mono); font-size:12px; font-variant-numeric:tabular-nums;
  color:var(--muted); text-decoration:none; padding:3px 7px; border-radius:3px;
  border:1px solid transparent;
}
.index a:hover{color:var(--text);border-color:var(--line)}
.index a:focus-visible{outline:2px solid var(--accent);outline-offset:1px}

/* ---- a round -------------------------------------------------------- */
.round{padding:38px 0;border-bottom:1px solid var(--line2);scroll-margin-top:56px}
.rhead{display:flex;flex-wrap:wrap;align-items:baseline;gap:12px 18px;margin-bottom:22px}
.rnum{
  font-family:var(--mono); font-size:13px; font-weight:600; letter-spacing:.1em;
  text-transform:uppercase; color:var(--accent);
}
h2{font-family:var(--mono);font-weight:600;font-size:22px;letter-spacing:-.01em;margin:0}
.rmeta{
  font-family:var(--mono); font-size:12px; color:var(--muted);
  font-variant-numeric:tabular-nums; display:flex; gap:14px; flex-wrap:wrap;
}
.rmeta em{font-style:normal;color:var(--text)}

.cols{display:grid;grid-template-columns:auto minmax(0,1fr);gap:32px;align-items:start}
@media (max-width:820px){.cols{grid-template-columns:1fr;gap:22px}}

/* ---- the board ------------------------------------------------------ */
.boardcard{
  background:var(--well); border:1px solid var(--line); border-radius:4px;
  padding:14px; box-shadow:var(--shadow); width:max-content;
}
.board{display:flex;flex-direction:column;gap:0;position:relative}
.brow{display:flex;gap:0;height:22px;flex:0 0 auto}
.brow.odd{margin-left:11px}   /* the hex stagger: exactly half a cell */
/* flex:none matters -- as flex items these would otherwise shrink to fit and
   the hex lattice would stop lining up with the odd-row offset. */
.bub{width:22px;height:22px;display:block;border-radius:50%;flex:0 0 auto}
.bub.e{background:transparent}
.deathline{
  margin-top:5px;border-top:1px dashed #6b4a4a;padding-top:4px;
}
.deathline span{
  font-family:var(--mono);font-size:9px;letter-spacing:.14em;
  text-transform:uppercase;color:#a86a6a;
}
.seqline{
  margin-top:12px;font-family:var(--mono);font-size:11px;color:var(--muted);
  max-width:222px;word-break:break-all;line-height:1.5;
}
.seqline b{
  display:block;font-size:9.5px;letter-spacing:.14em;text-transform:uppercase;
  color:var(--muted);margin-bottom:3px;font-weight:400;
}

/* ---- shot table ----------------------------------------------------- */
.tablewrap{overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:13.5px}
thead th{
  font-family:var(--mono); font-size:10px; letter-spacing:.13em;
  text-transform:uppercase; color:var(--muted); font-weight:400;
  text-align:left; padding:0 10px 7px 0; border-bottom:1px solid var(--line);
  white-space:nowrap;
}
tbody td{
  padding:6px 10px 6px 0; border-bottom:1px solid var(--line2);
  vertical-align:middle;
}
tbody tr:last-child td{border-bottom:none}
.n{font-family:var(--mono);font-variant-numeric:tabular-nums;color:var(--muted);
   text-align:right;padding-right:14px;width:1%}
.ball{white-space:nowrap}
.ball i{
  width:13px;height:13px;border-radius:50%;display:inline-block;
  vertical-align:-2px;margin-right:7px;
}
.aim{font-family:var(--mono);font-size:12.5px;white-space:nowrap}
.deg{color:var(--muted)}
.bank{
  font-size:10px;letter-spacing:.08em;text-transform:uppercase;
  color:var(--accent);border:1px solid var(--accent-dim);
  border-radius:2px;padding:1px 4px;margin-left:4px;white-space:nowrap;
}
.cell{font-family:var(--mono);font-size:12.5px;color:var(--muted);white-space:nowrap}
.res{font-size:12.5px}
.res.stick,.res.none{color:var(--muted)}
.res.pop{color:var(--text);font-weight:600}
.res.drop{color:var(--accent);font-weight:600}
.pts{font-family:var(--mono);font-size:11.5px;color:var(--muted);
     font-variant-numeric:tabular-nums}
.left{font-family:var(--mono);font-variant-numeric:tabular-nums;text-align:right;
      color:var(--muted);width:1%;padding-right:0}
tbody tr.clears .left{color:var(--accent);font-weight:600}

/* the launcher needle, at the shot's real angle */
.dial{
  display:inline-block;width:15px;height:15px;position:relative;
  vertical-align:-3px;margin-right:8px;
}
.dial::before{
  content:"";position:absolute;left:6px;bottom:0;width:3px;height:3px;
  border-radius:50%;background:var(--line);
}
.dial i{
  position:absolute;left:6.5px;bottom:1px;width:2px;height:12px;
  background:var(--accent);transform-origin:bottom center;border-radius:1px;
}

.outro{padding:40px 0 0;color:var(--muted);font-size:13px;max-width:70ch}
.outro code{font-family:var(--mono);font-size:12px;color:var(--text)}
"""


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "roundbook.html")
    data = json.load(open(JSON, encoding="utf-8"))
    wins = [d for d in data if d.get("win")]

    H = []
    w = H.append
    w("<title>Bust-A-Bobble Round Book</title>")
    w("<style>%s</style>" % CSS)
    w('<div class="wrap">')

    # masthead
    w('<header class="mast">')
    w('<p class="eyebrow">TI-99/4A &middot; ColecoVision &middot; solved offline</p>')
    w('<h1>Bust-A-Bobble<br>Round Book<span class="dot">.</span></h1>')
    w('<p class="lede">A cleared line for every one of the 30 rounds. Each was found by '
      'simulating the <strong>shipped cartridge data</strong> under the game\'s own rules '
      '&mdash; the real fixed-point flight, the real wall bounces, the real match and '
      'orphan-drop logic &mdash; so every line below is a solution you can actually play, '
      'not a sketch.</p>')

    tot_shots = sum(len(d["shots"]) for d in wins)
    tot_bub = sum(d["bubbles"] for d in wins)
    w('<div class="stats">')
    for val, lab in ((len(wins), "rounds solved"),
                     ("{:,}".format(tot_shots), "shots total"),
                     ("{:,}".format(tot_bub), "bubbles cleared"),
                     (min(len(d["shots"]) for d in wins), "shortest round"),
                     (max(len(d["shots"]) for d in wins), "longest round")):
        w("<div><b>%s</b><span>%s</span></div>" % (val, lab))
    w("</div>")

    w('<div class="legend">')
    for k in range(1, 9):
        w('<span class="lb"><i class="bub k%d" style="width:14px;height:14px"></i>'
          '<b>%d</b> %s</span>' % (k, k, CNAME[k]))
    w("</div>")
    w("</header>")

    # index
    w('<nav class="index" aria-label="rounds"><div class="row">')
    for d in data:
        w('<a href="#r%d">%02d</a>' % (d["lvl"], d["lvl"]))
    w("</div></nav>")

    w("<main>")
    for d in data:
        w('<section class="round" id="r%d">' % d["lvl"])
        if not d.get("win"):
            w('<div class="rhead"><span class="rnum">Round %02d</span>'
              '<h2>no line found</h2></div>' % d["lvl"])
            w("<p>%s</p></section>" % esc(d.get("reason", "")))
            continue

        shots = d["shots"]
        w('<div class="rhead">')
        w('<span class="rnum">Round %02d</span>' % d["lvl"])
        w("<h2>%d shots</h2>" % len(shots))
        w('<div class="rmeta">')
        w("<span><em>%d</em> bubbles</span>" % d["bubbles"])
        w("<span><em>%s</em></span>"
          % " / ".join(CNAME[c] for c in d["colours"]))
        w("<span>ceiling drops every <em>%.2f s</em></span>" % (d["droprl"] / 60.0))
        w("<span>clears in <em>%.1f s</em></span>" % (d["frames"] / 60.0))
        w("<span><em>%s</em> pts</span>" % "{:,}".format(d["score"]))
        if d["top"]:
            w("<span>ceiling drops <em>%d&times;</em> en route</span>" % d["top"])
        w("</div></div>")

        w('<div class="cols">')
        w('<div><div class="boardcard">%s</div>' % board_html(d["start"]))
        w('<p class="seqline"><b>fixed shot sequence</b>%s</p>'
          % "".join(str(k) for k in d["seq"]))
        w("</div>")

        w('<div class="tablewrap"><table>')
        w("<thead><tr><th></th><th>Ball</th><th>Aim</th><th>Lands</th>"
          "<th>Result</th><th>Left</th></tr></thead><tbody>")
        for i, ev in enumerate(shots):
            cell = ("r%d c%d" % (ev["cell"] // 8, ev["cell"] % 8)
                    if ev["cell"] is not None else "&mdash;")
            w('<tr%s>' % (' class="clears"' if ev["left"] == 0 else ""))
            w('<td class="n">%d</td>' % (i + 1))
            w('<td class="ball"><i class="bub k%d"></i>%s</td>'
              % (ev["k"], CNAME[ev["k"]]))
            w('<td class="aim">%s%s</td>'
              % (dial(ev["aim"]), aim_words(ev["aim"], ev["bl"], ev["br"])))
            w('<td class="cell">%s</td>' % cell)
            w("<td>%s</td>" % result_html(ev))
            w('<td class="left">%d</td>' % ev["left"])
            w("</tr>")
        w("</tbody></table></div>")
        w("</div></section>")
    w("</main>")

    w('<p class="outro">Aim is the launcher\'s step count from straight up: 63 positions, '
      '31 either side, one step &asymp; 2.6&deg;. It moves one step per frame while you '
      'hold the stick and <em>stays where you left it between shots</em>, so these counts '
      'are absolute. A colour no longer on the field is skipped when the next ball is '
      'dealt, which is why the Ball column can differ from the raw sequence. '
      'Generated by <code>assets/solvelevels.py --report</code> and '
      '<code>assets/walkthroughhtml.py</code>.</p>')
    w("</div>")

    # bubble colours last so they win on specificity-ties, and are theme-independent
    # (they are data, not decoration -- the same ball is the same colour either way).
    w("<style>")
    for k, hx in CHEX.items():
        w(".bub.k%d{background:radial-gradient(circle at 34%% 28%%,"
          "rgba(255,255,255,.55),rgba(255,255,255,0) 46%%),%s;"
          "box-shadow:inset 0 0 0 1px rgba(0,0,0,.28)}" % (k, hx))
    w("</style>")

    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(H) + "\n")
    print("wrote %s  (%d rounds, %.0f KB)"
          % (os.path.normpath(out_path), len(data),
             os.path.getsize(out_path) / 1024.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
