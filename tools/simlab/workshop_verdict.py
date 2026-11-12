#!/usr/bin/env python3
"""Judges one Workshop run (docs/simulator-lab.md "The Workshop scenario"): tools/simlab/workshop.sh.

The scenario prints one "SIMLAB check PASS|FAIL [layer] name | expected=.. | actual=.." line per assertion, "SIMLAB step <name>" per
step and a "SIMLAB done ..." line at its end. A clean exit proves nothing, so a pass needs all of these:
  craft/opps/shop/design  every step ran to the end, every check passed, no Lua error outside the classified rules, every evidence layer was
                   exercised, and the checks before the screenshot pose are IDENTICAL in the four launches (reproducibility)
  wrong            with one expectation made wrong, exactly that check failed and every other one passed (the negative control)
  screenshots      four real images of the size asked for, with a window area that is not blank

Errors are classified (known_failures.py), not avoided. This scenario is solo; permitted: Blizzard's voice-settings error, and the
simulator's refusal of an addon message, which here can only come from the NPC collection's share of a newly noted merchant
(npcs/Share.lua; checked below), never from the Workshop.

Usage: workshop_verdict.py RUN_DIR WRONG_CHECK_NAME ASSETS(0|1). Exit status 0 is PASS, 1 is FAIL.
"""
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True   # nothing is written beside the scripts
sys.path.insert(0, str(Path(__file__).resolve().parent))
from verdict import distinct_colours, read_rgba  # noqa: E402
import known_failures as kf  # noqa: E402

STEPS = [
    "open and navigate", "crafting: unsupported recipe is not ready", "crafting: add, change quantity, remove",
    "crafting: materials against the bags", "crafting: a second profession and Open recipe", "merchant prices noted",
    "opportunities: before any scan", "opportunities: scan against the fake auction house",
    "opportunities: rows, ordering, filtering, unknowns", "opportunities: short tooltip, details with Shift",
    "what's it worth: item tooltip lines", "what's it worth: tooltip designer",
    "opportunities: test-input cut, then removed", "opportunities: Add to queue",
    "shopping: combined list, sources, total, warning", "shopping: source choices", "shopping: Show vendor",
    "shopping: add the suggested subcraft", "shopping: bags change", "close and reopen", "remembered recipes: closed window, background read, nothing open",
    "bank and guild bank: remembered while the window is closed", "bank and guild bank: planned with, collected not bought, labelled, profit unchanged",
    "bank and guild bank: the guild choice, permissions and limits", "bank and guild bank: a withdrawal and a deposit never count twice", "pose for the screenshot",
]
LAYERS = ("init", "display", "click", "direct", "event", "state")
VIEWS = {"overview": "TwichUIWorkshop", "craft": "TwichUIWorkshop", "opps": "TwichUIWorkshop", "shop": "TwichUIWorkshop", "design": "TwichUISettings",
         "small": "TwichUIWorkshop", "empty": "TwichUIWorkshop", "history": "TwichUIWorkshop", "craftlong": "TwichUIWorkshop",
         "shopmix": "TwichUIWorkshop", "shopcollect": "TwichUIWorkshop"}
SHOTS = ("overview", "craft", "opps", "shop", "design", "small", "empty", "history", "craftlong", "shopmix", "shopcollect")
VOICE, UTF8 = "voice-settings-unsupplied", "addon-message-invalid-utf8"
CHECK = re.compile(r"^SIMLAB check (PASS|FAIL) \[([^\]]+)\] (.*?) \| expected=(.*?) \| actual=(.*)$", re.M)


def load(run, name):
    text = ""
    for suffix in ("stdout", "stderr"):
        text += (run / f"{name}.{suffix}").read_text(errors="replace") + "\n"
    checks = [(m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)) for m in CHECK.finditer(text)]
    steps = re.findall(r"^SIMLAB step (.*)$", text, re.M)
    done = re.search(r"^SIMLAB done steps=(\d+) simSeconds=([\d.]+) passed=(\d+) failed=(\d+) aborted=(\w+) stopped=(\w+)$", text, re.M)
    cls = kf.classify(text, allow=(VOICE, UTF8))
    errors = [m for _, m in cls["unknown"]] + [f"{rid} (not permitted here)" for rid in cls["unexpected"]]
    # the only permitted addon-message refusal is the NPC collection's share, never anything of the Workshop
    for k_id, k in cls["known"].items():
        if k_id == UTF8 and not all("npcs/Share.lua" in origin for origin in k["origins"]):
            errors.append("addon-message refusal that does not come from npcs/Share.lua")
        if k_id == UTF8 and any("Workshop" in origin for origin in k["origins"]):
            errors.append("addon-message refusal that involves the Workshop")
    return {"text": text, "checks": checks, "steps": steps, "done": done, "errors": errors, "cls": cls}


def main():
    run, wrong_name, assets = Path(sys.argv[1]), sys.argv[2], sys.argv[3] == "1"
    results = []

    def check(name, passed, detail=""):
        results.append(bool(passed))
        print(f"  {'pass' if passed else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))

    runs = {n: load(run, n) for n in SHOTS + ("wrong",)}

    for n in SHOTS:
        r = runs[n]
        print(f"The scenario, ending on {n}:")
        d = r["done"]
        check(f"{n}: the scenario reached its end", d and d.group(5) == "false" and d.group(6) == "false", d.group(0) if d else "no done line")
        check(f"{n}: every step ran, in order", r["steps"] == STEPS, ", ".join(r["steps"]))
        failed = [c for c in r["checks"] if c[0] == "FAIL"]
        check(f"{n}: no check failed", not failed,
              f"{len(failed)} failed; first: {failed[0][2]} expected={failed[0][3]} actual={failed[0][4]}" if failed else f"{len(r['checks'])} passed")
        check(f"{n}: the printed counts agree with the lines",
              d and int(d.group(3)) == len(r["checks"]) - len(failed) and int(d.group(4)) == len(failed))
        layers = {c[1] for c in r["checks"]}
        check(f"{n}: every evidence layer was exercised", set(LAYERS) <= layers, ", ".join(sorted(layers)))
        check(f"{n}: no Lua error outside the classified rules", not r["errors"], r["errors"][0][:150] if r["errors"] else "")

    print("Reproducibility, from a new empty install each time:")
    def common(r):
        out = []
        for c in r["checks"]:
            if c[2].startswith("pose:"):
                break
            out.append(c)
        return out
    first = [common(runs[n]) for n in SHOTS]
    check(f"the checks before the screenshot pose are identical in the {len(SHOTS)} launches", all(x == first[0] for x in first) and len(first[0]) > 0,
          " / ".join(str(len(x)) for x in first))

    print("Negative control (one expectation made wrong on purpose):")
    w = runs["wrong"]
    wrong_failed = [x for x in w["checks"] if x[0] == "FAIL"]
    check("wrong: it ran to its end (a failure, not a crash)",
          w["done"] and w["done"].group(5) == "false" and not w["errors"], w["done"].group(0) if w["done"] else "no done line")
    check("wrong: exactly the doctored check failed", [x[2] for x in wrong_failed] == [wrong_name],
          ", ".join(x[2] for x in wrong_failed) or "nothing failed")
    check("wrong: every other check passed", len(w["checks"]) == len(runs["craft"]["checks"]) and len(wrong_failed) == 1,
          f"{len(w['checks'])} checks, {len(wrong_failed)} failed")

    print("Screenshots (files only; whether they look right is for a person to judge):")
    for n in SHOTS:
        path = run / f"{n}.png"
        size = (1000, 700) if n == "small" else (1600, 1200)
        # the Workshop window is 1080x700, centred (the settings window of the design shot is smaller, centred too); on the small screen
        # it is scaled to fit, so the middle of the screen is inside it
        box = (150, 120, 700, 460) if n == "small" else (260, 250, 1080, 700)
        try:
            width, height, pixels = read_rgba(path)
            check(f"{n}.png is {size[0]}x{size[1]}", (width, height) == size, f"{width}x{height}")
            check(f"{n}.png: the window area is not blank", distinct_colours(pixels, *box) > 500,
                  f"{distinct_colours(pixels, *box)} distinct colours")
        except (OSError, ValueError) as err:
            check(f"{n}.png is readable", False, str(err))

    ok = all(results)
    r = runs["craft"]
    by_layer = {layer: sum(1 for x in r["checks"] if x[1] == layer) for layer in LAYERS}
    print("Evidence from this run (one launch; the others repeat it, then end in another view):")
    print(f"  Window opened by /tui workshop ... {'yes' if by_layer['init'] else 'NO'} ({by_layer['init']} init checks)")
    print(f"  Displayed text and state ......... {'yes' if by_layer['display'] else 'NO'} ({by_layer['display']} checks, read from the drawn frames)")
    print(f"  Control interaction .............. {'yes, HANDLER-LEVEL' if by_layer['click'] else 'NO'} ({by_layer['click']} checks): "
          "Button:Click(). No pointer, hit test, focus or keyboard.")
    print(f"  Game events ...................... {'yes' if by_layer['event'] else 'NO'} ({by_layer['event']} checks): fired by the simulator "
          "(BAG_UPDATE_DELAYED, TRADE_SKILL_LIST_UPDATE, MERCHANT_SHOW, REPLICATE_ITEM_LIST_UPDATE)")
    print(f"  Direct handler calls ............. {'yes' if by_layer['direct'] else 'NO'} ({by_layer['direct']} checks): "
          "Session functions called by the scenario, not through a control")
    print(f"  Underlying state ................. {'yes, in memory' if by_layer['state'] else 'NO'} ({by_layer['state']} checks)")
    print("  Game data ........................ FAKE and deterministic (professions, items, bags, auction listings, merchant); "
          "the world map and NpcMap.Locate are stand-ins in the Show vendor step")
    print("  Persistence tested ............... NO: nothing is reloaded or written to disk. Closing and reopening the window is not persistence.")
    print(f"  Screenshots ...................... {'captured' if assets else 'captured WITHOUT game assets'}: overview.png, craft.png, opps.png, shop.png, design.png, small.png (1000x700), empty.png, history.png, craftlong.png, shopmix.png, shopcollect.png "
          "(a script cannot judge them; look at them, and remember custom fonts are not drawn)")
    print("  Real-client tested ............... NO")
    print(f"{len(r['checks'])} checks per launch; {r['done'].group(2) if r['done'] else '?'} s of simulated time.")
    known = kf.describe(r["cls"])
    print("Classified errors (kept in the log, not hidden):" if known else "Classified errors: none")
    for line in known:
        print(line)
    if not ok:
        print("FAIL")
    elif r["cls"]["known"]:
        print("PASS WITH KNOWN SIMULATOR LIMITATIONS (handler-level interaction over fake game data; every assertion held, but the log "
              "holds the classified simulator errors listed above: this is not a run without runtime errors)")
    else:
        print("PASS (handler-level interaction over fake game data; no runtime errors in the log)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
