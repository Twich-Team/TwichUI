#!/usr/bin/env python3
"""Judges one interaction run (docs/simulator-lab.md): tools/simlab/interact.sh.

The scenario prints one "SIMLAB check PASS|FAIL [layer] name | expected=.. | actual=.." line per assertion, and a
"SIMLAB done" line when it reaches its end. A clean exit proves nothing, so a pass needs all of these:
  a      every step ran to the end, every check passed, no Lua error, and each layer (init, construct, interact,
         state) was exercised
  a2     a second run from a new empty install gave the same checks and the same saved result (reproducibility)
  before the first step alone passed, and its screenshot is a real image
  wrong  with one expectation made wrong, exactly that check failed and every other one passed (the negative
         control: the scenario can fail, and fails for the reason it was given)
and both screenshots are real images of the size asked for.

Usage: interact_verdict.py RUN_DIR WRONG_CHECK_NAME ASSETS(0|1). Exit status 0 is PASS, 1 is FAIL.
"""
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True   # nothing is written beside the scripts
sys.path.insert(0, str(Path(__file__).resolve().parent))
from verdict import distinct_colours, read_rgba  # noqa: E402  (the smoke test's PNG reader)

STEPS = ["initial", "choose a card", "toggle own look", "slider and number box", "dropdown", "close and reopen"]
CHECK = re.compile(r"^SIMLAB check (PASS|FAIL) \[(\w+)\] (.*?) \| expected=(.*?) \| actual=(.*)$", re.M)


def load(run, name):
    text = ""
    for suffix in ("stdout", "stderr"):
        text += (run / f"{name}.{suffix}").read_text(errors="replace") + "\n"
    checks = [(m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)) for m in CHECK.finditer(text)]
    steps = re.findall(r"^SIMLAB step (.*)$", text, re.M)
    done = re.search(r"^SIMLAB done steps=(\d+) simSeconds=([\d.]+) passed=(\d+) failed=(\d+) aborted=(\w+) stopped=(\w+)$", text, re.M)
    digest = re.findall(r"^SIMLAB digest(?:-shared)? (.*)$", text, re.M)
    errors = re.findall(r"^Lua error: .*$", text, re.M)
    return {"text": text, "checks": checks, "steps": steps, "done": done, "digest": digest, "errors": errors}


def main():
    run, wrong_name, assets = Path(sys.argv[1]), sys.argv[2], sys.argv[3] == "1"
    results = []

    def check(name, passed, detail=""):
        results.append(bool(passed))
        print(f"  {'pass' if passed else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))

    a, a2, before, wrong = (load(run, n) for n in ("a", "a2", "before", "wrong"))

    print("The scenario:")
    check("a: the scenario reached its end", a["done"] and a["done"].group(5) == "false" and a["done"].group(6) == "false",
          a["done"].group(0) if a["done"] else "no done line")
    check("a: every step ran, in order", a["steps"] == STEPS, ", ".join(a["steps"]))
    failed = [c for c in a["checks"] if c[0] == "FAIL"]
    check("a: no check failed", not failed, f"{len(failed)} failed; first: {failed[0][2]} expected={failed[0][3]} actual={failed[0][4]}" if failed else f"{len(a['checks'])} passed")
    check("a: the printed counts agree with the lines", a["done"] and int(a["done"].group(3)) == len(a["checks"]) - len(failed)
          and int(a["done"].group(4)) == len(failed))
    layers = {c[1] for c in a["checks"]}
    check("a: every layer was exercised", {"init", "construct", "interact", "state"} <= layers, ", ".join(sorted(layers)))
    check("a: no Lua error", not a["errors"], a["errors"][0][:150] if a["errors"] else "")

    print("Reproducibility, from a new empty install:")
    check("a2: reached its end with no failed check and no Lua error",
          a2["done"] and a2["done"].group(4) == "0" and a2["done"].group(5) == "false" and not a2["errors"],
          a2["done"].group(0) if a2["done"] else "no done line")
    check("a2: the same checks with the same expected and actual values", a["checks"] == a2["checks"] and len(a["checks"]) > 0,
          f"{len(a['checks'])} vs {len(a2['checks'])}")
    check("a2: the same saved result", a["digest"] == a2["digest"] and len(a["digest"]) == 2, " / ".join(a["digest"]))

    print("The page before any interaction:")
    check("before: stopped after the first step with every check passing",
          before["done"] and before["done"].group(6) == "true" and before["done"].group(4) == "0" and not before["errors"],
          before["done"].group(0) if before["done"] else "no done line")

    print("Negative control (one expectation made wrong on purpose):")
    wrong_failed = [c for c in wrong["checks"] if c[0] == "FAIL"]
    check("wrong: it ran to its end (a failure, not a crash)", wrong["done"] and wrong["done"].group(5) == "false"
          and not wrong["errors"], wrong["done"].group(0) if wrong["done"] else "no done line")
    check("wrong: exactly the doctored check failed", [c[2] for c in wrong_failed] == [wrong_name],
          ", ".join(c[2] for c in wrong_failed) or "nothing failed")
    check("wrong: every other check passed", len(wrong["checks"]) == len(a["checks"]) and len(wrong_failed) == 1,
          f"{len(wrong['checks'])} checks, {len(wrong_failed)} failed")

    print("Screenshots (files only; whether they look right is for a person to judge):")
    for name, label in (("after", "after"), ("before", "before")):
        path = run / f"{name}.png"
        out = load(run, "a" if name == "after" else "before")["text"]
        frame = re.search(r"^TwichUISettingsWindow \[Frame\] \((\d+)x(\d+)\).* x=(\d+), y=(\d+)", out, re.M)
        try:
            width, height, pixels = read_rgba(path)
            check(f"{label}.png is {1600}x{1200}", (width, height) == (1600, 1200), f"{width}x{height}")
            if frame:
                w, h, x, y = map(int, frame.groups())
                colours = distinct_colours(pixels, x, y, w, h)
                check(f"{label}.png: the window area is not blank", colours > 500, f"{colours} distinct colours")
            else:
                check(f"{label}.png: the window is in the frame tree", False)
        except (OSError, ValueError) as err:
            check(f"{label}.png is readable", False, str(err))

    ok = all(results)
    n = len(a["checks"])
    by_layer = {layer: sum(1 for c in a["checks"] if c[1] == layer) for layer in ("init", "construct", "interact", "state")}
    print("Evidence from this run:")
    print(f"  Initialization tested ........ {'yes' if by_layer['init'] else 'NO'} ({by_layer['init']} checks)")
    print(f"  Page construction tested ..... {'yes' if by_layer['construct'] else 'NO'} ({by_layer['construct']} checks)")
    print(f"  Control interaction tested ... {'yes, HANDLER-LEVEL' if by_layer['interact'] else 'NO'} ({by_layer['interact']} checks): "
          "Button:Click, Slider:SetValue, EditBox:SetText + OnEnterPressed. No pointer, hit test, focus or keyboard.")
    print(f"  State mutation tested ........ {'yes, in memory' if by_layer['state'] else 'NO'} ({by_layer['state']} checks): "
          "TwichUIDB, the model, and what the controls show.")
    print("  Persistence tested ........... NO: nothing is reloaded or written to disk. Closing and reopening the window is not persistence.")
    print(f"  Screenshot ................... {'captured' if assets else 'captured WITHOUT game assets'}: after.png, before.png "
          "(a script cannot inspect them; look at them, and remember custom fonts are not drawn)")
    print("  Real-client tested ........... NO")
    sim = a["done"].group(2) if a["done"] else "?"
    print(f"{n} checks in the full run; {sim} s of simulated time (budget 2.5 s, see scenarios/lib.lua).")
    print("PASS (handler-level interaction and in-memory state only)" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
