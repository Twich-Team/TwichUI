#!/usr/bin/env python3
"""Judges one Test Lab window run (docs/testlab.md "The window"): tools/simlab/testlab.sh.

The scenario prints "SIMLAB check PASS|FAIL [layer] name | expected=.. | actual=.." per assertion, "SIMLAB step <name>" per step and a
"SIMLAB done ..." line at the end. A clean exit proves nothing, so a pass needs, for every launch: the scenario ran to its end, every step ran
in order, every check passed, the printed counts agree, no Lua error outside the classified rules, and a real screenshot of the size asked for
with a window area that is not blank. The launches share their first step, which must read the same in each (reproducibility).

What a pass is evidence of: the window built from the real registry and drew synthetic recorded results; the emulated hit test found its
controls reachable. It is not evidence of real input, the clipboard, or how anything looks in the game: the screenshots are for a person.

Usage: testlab_verdict.py RUN_DIR ASSETS(0|1). Exit status 0 is PASS, 1 is FAIL.
"""
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from verdict import distinct_colours, read_rgba  # noqa: E402
import known_failures as kf  # noqa: E402

VIEWS = ("idle", "running", "allpass", "mixed", "failfilter", "problems", "long", "guided", "small")
STEPS = ["load and open", "recorded results for this view", "the controls take the pointer, and the text fits", "pose for the screenshot"]
CHECK = re.compile(r"^SIMLAB check (PASS|FAIL) \[([^\]]+)\] (.*?) \| expected=(.*?) \| actual=(.*)$", re.M)
VOICE = "voice-settings-unsupplied"


def load(run, name):
    text = ""
    for suffix in ("stdout", "stderr"):
        text += (run / f"{name}.{suffix}").read_text(errors="replace") + "\n"
    checks = [m.groups() for m in CHECK.finditer(text)]
    steps = re.findall(r"^SIMLAB step (.*)$", text, re.M)
    done = re.search(r"^SIMLAB done steps=(\d+) simSeconds=([\d.]+) passed=(\d+) failed=(\d+) aborted=(\w+) stopped=(\w+)$", text, re.M)
    cls = kf.classify(text, allow=(VOICE,))
    errors = [m for _, m in cls["unknown"]] + [f"{rid} (not permitted here)" for rid in cls["unexpected"]]
    return {"text": text, "checks": checks, "steps": steps, "done": done, "errors": errors, "cls": cls}


def main():
    run, assets = Path(sys.argv[1]), sys.argv[2] == "1"
    results = []

    def check(name, passed, detail=""):
        results.append(bool(passed))
        print(f"  {'pass' if passed else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))

    runs = {v: load(run, v) for v in VIEWS}
    for v in VIEWS:
        r = runs[v]
        print(f"The scenario, view {v}:")
        d = r["done"]
        check(f"{v}: the scenario reached its end", d and d.group(5) == "false" and d.group(6) == "false", d.group(0) if d else "no done line")
        check(f"{v}: every step ran, in order", r["steps"] == STEPS, ", ".join(r["steps"]))
        failed = [c for c in r["checks"] if c[0] == "FAIL"]
        check(f"{v}: no check failed", not failed and len(r["checks"]) > 8,
              f"{len(failed)} failed; first: {failed[0][2]} expected={failed[0][3]} actual={failed[0][4]}" if failed else f"{len(r['checks'])} passed")
        check(f"{v}: the printed counts agree with the lines", d and int(d.group(3)) == len(r["checks"]) - len(failed) and int(d.group(4)) == len(failed))
        check(f"{v}: no Lua error outside the classified rules", not r["errors"], r["errors"][0][:150] if r["errors"] else "")
        if v in ("mixed", "allpass", "failfilter", "problems", "long", "small"):
            names = [c[2] for c in r["checks"]]
            check(f"{v}: the controls' reachability was checked (Run, Copy, chips, a row, the search)",
                  sum(1 for n in names if n.startswith("REACH:")) >= 9, str(sum(1 for n in names if n.startswith("REACH:"))))
            check(f"{v}: the text-fit check ran", any(n.startswith("no card label") for n in names))

    print("Reproducibility, from a new empty install each time:")
    first = [[c for c in runs[v]["checks"] if c[1] == "init" or c[2].startswith("one sidebar") or c[2].startswith("before a run")] for v in VIEWS]
    check(f"the opening checks are identical in the {len(VIEWS)} launches", all(x == first[0] for x in first) and len(first[0]) > 3, " / ".join(str(len(x)) for x in first))

    print("Screenshots (files only; whether they look right is for a person to judge):")
    for v in VIEWS:
        path = run / f"{v}.png"
        size = (1000, 700) if v == "small" else (1600, 1200)
        # the window is centred and fills most of the screen; look at its middle
        box = (150, 120, 700, 460) if v == "small" else (260, 200, 1080, 800)
        try:
            width, height, pixels = read_rgba(path)
            check(f"{v}.png is {size[0]}x{size[1]}", (width, height) == size, f"{width}x{height}")
            colours = distinct_colours(pixels, *box)
            check(f"{v}.png: the window area is not blank", colours > (80 if v == "guided" else 500), f"{colours} distinct colours")
        except (OSError, ValueError) as err:
            check(f"{v}.png is readable", False, str(err))

    ok = all(results)
    r = runs["mixed"]
    layers = {}
    for c in r["checks"]:
        layers[c[1]] = layers.get(c[1], 0) + 1
    print("Evidence from this run:")
    print(f"  Window loaded by LoadAddOn ....... {'yes' if layers.get('init') else 'NO'} ({layers.get('init', 0)} init checks)")
    print(f"  Displayed text and state ......... {'yes' if layers.get('display') else 'NO'} ({layers.get('display', 0)} checks, read from the drawn frames)")
    print("  Hit test ......................... EMULATED by Reach.lua over the simulator's frames (the simulator has no pointer)")
    print("  Results .......................... SYNTHETIC recorded results handed to Window.OnProgress / OnDone; no case ran")
    print("  Persistence, clipboard, input .... NOT tested")
    print(f"  Screenshots ...................... {'captured' if assets else 'captured WITHOUT game assets'}: {', '.join(v + '.png' for v in VIEWS)} (small is 1000x700; addon fonts are drawn in Friz Quadrata)")
    print("  Real-client tested ............... NO")
    print(f"{len(r['checks'])} checks in the mixed launch; {r['done'].group(2) if r['done'] else '?'} s of simulated time.")
    known = kf.describe(r["cls"])
    print("Classified errors (kept in the log, not hidden):" if known else "Classified errors: none")
    for line in known:
        print(line)
    if not ok:
        print("FAIL")
    elif r["cls"]["known"]:
        print("PASS WITH KNOWN SIMULATOR LIMITATIONS (every assertion held, but the log holds the classified simulator errors listed above)")
    else:
        print("PASS (no runtime errors in the log)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
