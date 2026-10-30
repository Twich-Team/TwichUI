#!/usr/bin/env python3
"""Judges one simulator smoke run (docs/simulator-lab.md). A clean exit proves nothing, so a pass needs all of these:
the real window opened on the real page through R:OpenSettings, finished fading in, constructed rows, raised no Lua
error, lost none of TwichUI's own textures, shows real pixels where the window is, and every other page constructed too.

What a pass is evidence of: initialization and page construction. It is not evidence that any control works (see
interact_verdict.py for the controls it exercises), that anything persists, or of how anything looks.

Usage: verdict.py RUN_DIR PAGE_KEY PAGE_TITLE. Exit status 0 is PASS, 1 is FAIL.
"""
import re
import struct
import sys
import zlib
from pathlib import Path


def read_rgba(path):
    """Decodes an 8-bit RGBA, non-interlaced PNG: the one form the simulator writes."""
    data = path.read_bytes()
    pos, idat, width, height = 8, [], 0, 0
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if (depth, colour, interlace) != (8, 6, 0):
                raise ValueError(f"unexpected PNG form: {depth} {colour} {interlace}")
        elif kind == b"IDAT":
            idat.append(body)
        pos += length + 12
    raw = zlib.decompress(b"".join(idat))
    stride = width * 4
    rows, previous, offset = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[offset]
        line = bytearray(raw[offset + 1:offset + 1 + stride])
        offset += stride + 1
        for i in range(stride):
            left = line[i - 4] if i >= 4 else 0
            up = previous[i]
            corner = previous[i - 4] if i >= 4 else 0
            if kind == 1:
                line[i] = (line[i] + left) & 255
            elif kind == 2:
                line[i] = (line[i] + up) & 255
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif kind == 4:
                estimate = left + up - corner
                near = min((abs(estimate - left), 0, left), (abs(estimate - up), 1, up),
                           (abs(estimate - corner), 2, corner))
                line[i] = (line[i] + near[2]) & 255
        rows.append(line)
        previous = line
    return width, height, rows


def distinct_colours(rows, left, top, width, height):
    seen = set()
    for row in rows[top:top + height]:
        for x in range(left, left + width):
            seen.add(bytes(row[x * 4:x * 4 + 3]))
    return len(seen)


def main():
    run, page, title = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    out = (run / "run.stdout").read_text(errors="replace")
    err = (run / "run.stderr").read_text(errors="replace")
    checks = []

    def check(name, passed, detail=""):
        checks.append(bool(passed))
        print(f"  {'pass' if passed else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))

    says = dict(re.findall(r"SIMLAB (\S+) (.*)", out + err))   # A_Print writes to stderr
    check("TwichUI core is present", says.get("core") == "true")
    check("initialised with no failed hook", "configReady=true" in says.get("life", "")
          and "hookFailures=0" in says.get("life", ""), says.get("life", "no life line"))
    check("R:OpenSettings returned true", says.get("open", "").startswith(f"{page} true"), says.get("open", "no open line"))
    check("load-on-demand companion loaded", "loaded=true" in says.get("companion", ""))
    check("window finished fading in", "shown=true alpha=1 " in says.get("window-settled", ""),
          says.get("window-settled", "no window line"))
    check("the page asked for is the page shown", says.get("page") == page, says.get("page", "no page line"))
    rows = re.search(r"rows=(\d+)", says.get("view", ""))
    check("the page constructed rows", rows and int(rows.group(1)) > 0, says.get("view", "no view line"))
    check("the page title is in the frame tree", f'text="{title}"' in out)

    errors = re.findall(r"^Lua error: .*$", err, re.M)
    check("no Lua error", not errors, f"{len(errors)} found; first: {errors[0][:150]}" if errors else "")
    missing = [m for m in re.findall(r"Not found: (.*)", err) if "twichui" in m.lower()]
    check("no TwichUI texture missing", not missing, ", ".join(missing[:4]))

    frame = re.search(r"^TwichUISettingsWindow \[Frame\] \((\d+)x(\d+)\).* x=(\d+), y=(\d+)", out, re.M)
    if frame:
        win_w, win_h, win_x, win_y = map(int, frame.groups())
        width, height, pixels = read_rgba(run / "settings.png")
        check("screenshot file is the size asked for", (width, height) == (1600, 1200), f"{width}x{height}")
        colours = distinct_colours(pixels, win_x, win_y, win_w, win_h)
        check("screenshot: the window area is not blank (not a visual check)", colours > 500, f"{colours} distinct colours")
    else:
        check("window is in the frame tree", False)

    sweep = (run / "pages.stdout").read_text(errors="replace") + (run / "pages.stderr").read_text(errors="replace")
    counts = re.search(r"SIMLAB pages described=(\d+) constructed=(\d+)", sweep)
    check("every described page constructed without a captured error",
          counts and counts.group(1) == counts.group(2) and int(counts.group(1)) > 0,
          counts.group(0).replace("SIMLAB pages ", "") if counts else "no sweep line")
    sweep_errors = re.findall(r"^Lua error: .*$", sweep, re.M)
    check("no Lua error constructing them", not sweep_errors, sweep_errors[0][:150] if sweep_errors else "")

    print("Evidence: initialization tested, page construction tested. NOT tested here: control interaction, state "
          "mutation, persistence, how anything looks, the real client.")
    print("PASS (initialization and construction only)" if all(checks) else "FAIL")
    return 0 if all(checks) else 1


if __name__ == "__main__":
    sys.exit(main())
