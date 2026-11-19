#!/usr/bin/env python3
"""Judges one simulator smoke run (docs/simulator-lab.md). A clean exit proves nothing, so a pass needs all of these:
the real window opened on the real page through R:OpenSettings, finished fading in, constructed rows, raised no unclassified Lua
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
sys.path.insert(0, str(Path(__file__).resolve().parent))
import known_failures as kf


def read_rgba(path):
    """Decodes an 8-bit RGBA, non-interlaced PNG: the one form the simulator writes."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("invalid PNG signature")
    pos, idat, width, height = 8, [], 0, 0
    ended, idat_closed = False, False
    while pos < len(data):
        if pos + 12 > len(data):
            raise ValueError("truncated PNG chunk")
        length, kind = struct.unpack_from(">I4s", data, pos)
        end = pos + 8 + length
        if end + 4 > len(data):
            raise ValueError("truncated PNG chunk body")
        body = data[pos + 8:end]
        if zlib.crc32(kind + body) != struct.unpack_from(">I", data, end)[0]:
            raise ValueError("invalid PNG chunk CRC")
        if pos == 8 and kind != b"IHDR":
            raise ValueError("PNG must start with IHDR")
        if kind == b"IHDR":
            if width or length != 13:
                raise ValueError("invalid or duplicate PNG header")
            width, height, depth, colour, compression, filtering, interlace = struct.unpack(">IIBBBBB", body)
            if (depth, colour, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                raise ValueError("unexpected PNG form")
            if not width or not height or width > 16384 or height > 16384 or (width * 4 + 1) * height > 256 * 1024 * 1024:
                raise ValueError("PNG dimensions exceed decoder budget")
        elif kind == b"IDAT":
            if idat_closed:
                raise ValueError("nonconsecutive PNG image data")
            idat.append(body)
        elif kind == b"IEND":
            if length or not idat or end + 4 != len(data):
                raise ValueError("invalid PNG end")
            ended = True
            break
        elif not kind[0] & 32:
            raise ValueError("unsupported critical PNG chunk")
        if idat and kind != b"IDAT":
            idat_closed = True
        pos = end + 4
    if not ended:
        raise ValueError("missing PNG end")
    expected = (width * 4 + 1) * height
    decoder = zlib.decompressobj()
    try:
        raw = decoder.decompress(b"".join(idat), expected + 1)
    except zlib.error as exc:
        raise ValueError("corrupt PNG compressed data") from exc
    if len(raw) != expected or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
        raise ValueError("invalid PNG scanline length or compressed stream")
    stride = width * 4
    rows, previous, offset = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[offset]
        line = bytearray(raw[offset + 1:offset + 1 + stride])
        offset += stride + 1
        if kind == 1:
            for i in range(4, stride):
                left = line[i - 4]
                line[i] = (line[i] + left) & 255
        elif kind == 2:
            for i, up in enumerate(previous):
                line[i] = (line[i] + up) & 255
        elif kind == 3:
            for i in range(stride):
                left = line[i - 4] if i >= 4 else 0
                up = previous[i]
                line[i] = (line[i] + (left + up) // 2) & 255
        elif kind == 4:
            for i in range(stride):
                left = line[i - 4] if i >= 4 else 0
                up = previous[i]
                corner = previous[i - 4] if i >= 4 else 0
                # Equivalent Paeth threshold form; avoids three abs calls per
                # byte. Ties still prefer left, then up, then upper-left.
                low, high = (left, up) if left < up else (up, left)
                threshold = 3 * corner - left - up
                near = high if threshold <= low else low if threshold >= high else corner
                line[i] = (line[i] + near) & 255
        elif kind != 0:
            raise ValueError(f"unexpected PNG filter: {kind}")
        rows.append(line)
        previous = line
    return width, height, rows


def distinct_colours(rows, left, top, width, height):
    seen = set()
    for row in rows[top:top + height]:
        pixels = row[left * 4:(left + width) * 4]
        seen.update(zip(pixels[0::4], pixels[1::4], pixels[2::4]))
    return len(seen)


def classify_smoke(text):
    """Disclose the group hello and evidenced native timer limitation; fail other origins."""
    voice = 'voice-settings-unsupplied'
    result = kf.classify(text, allow=('addon-message-invalid-utf8', voice))
    begin, end = 'SIMLAB smoke-clock begin\n', 'SIMLAB smoke-clock end\n'
    before, separator, rest = text.partition(begin)
    window, closing, after = rest.partition(end)
    probe = 'SIMLAB voice-capability native=true unavailable=true'
    evidenced = (separator and closing and text.count(begin) == text.count(end) == 1
                 and before.splitlines().count(probe) == 1)
    # v0.1.37 drops the timer callback's Audio.lua frame. Only its observed native
    # AdvanceTime traceback (plus Blizzard's duplicate error reporter) is accepted.
    frame = re.compile(r"(?:stack traceback:|\(string\):\d+: in main chunk|"
                       r"\[C\]: in function 'AdvanceTime'|\[C\]: \?|"
                       r"=\(string\):\d+: in main chunk|=\[C\]:: in function 'AdvanceTime'|\?: \?|"
                       r"\[Interface/AddOns/Blizzard_ScriptErrors/Blizzard_ScriptErrors\.lua\]:\d+: "
                       r"in function (?:'GetErrorData'|<[^>]+>))")
    native_seen = False
    for section, in_window in ((before, False), (window, True), (after, False)):
        for block in kf.blocks(section):
            if not re.fullmatch(kf.RULES[voice]['message'], block['message']):
                continue
            stack = [line.strip() for line in block['stack']]
            native_stack = (len(stack) >= 5 and stack[:3] == [
                'stack traceback:', '(string):1: in main chunk', "[C]: in function 'AdvanceTime'"]
                and re.fullmatch(r"\(string\):\d+: in main chunk", stack[3])
                and stack[4] == '[C]: ?' and all(frame.fullmatch(line) for line in stack))
            valid = evidenced and in_window and (native_seen if block['suppressed'] else native_stack)
            if valid and not block['suppressed']:
                native_seen = True
            if not valid:
                result['unknown'].append((block['tick'], 'voice error without native smoke-clock evidence'))
    for block in kf.blocks(text):
        if block['message'] == 'string at argument 2 is not valid UTF-8' and not block['suppressed']:
            stack = '\n'.join(block['stack'])
            if not all(part in stack for part in ('Group.lua', 'SayHello', 'Share.lua', 'SendControl')):
                result['unknown'].append((block['tick'], 'UTF-8 error outside the group hello chain'))
    return result


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

    classified = classify_smoke(err)
    for name, passed, detail in kf.verdict_lines(classified):
        check(name, passed, detail)
    for line in kf.describe(classified):
        print(line)
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
    print("PASS (initialization and construction only; classified simulator limits disclosed)" if all(checks) else "FAIL")
    return 0 if all(checks) else 1


if __name__ == "__main__":
    sys.exit(main())
