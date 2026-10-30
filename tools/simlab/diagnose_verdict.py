#!/usr/bin/env python3
"""Judges one delayed-failure diagnostic run (docs/simulator-lab.md "Delayed failures"): tools/simlab/diagnose.sh.

A clean exit proves nothing, so each launch is judged on its whole log:
  contract  the simulator refuses exactly the strings that are not UTF-8, at the argument it names, with no addon loaded
  baseline  the clock covered the window with no addon, no addon message was attempted, and the voice error shows up
            anyway (so it is not TwichUI's)
  solo      the group state was verified solo, the clock covered the window, nothing was sent, no unclassified error
  grouped   the party was verified, the clock covered the window, the hello was attempted and the simulator refused its
            bytes, and that refusal is the one classified error (known_failures.py) besides the voice one; and exactly one
            hello came (the 6 s login hello was never scheduled: see the docs, "Event paths, not elapsed time")
  login     as grouped, after the lab fires PLAYER_ENTERING_WORLD itself (synthetic): the 6 s login hello is scheduled, runs
            and attempts a send about 6 s later
Errors are classified by what they are, not by when they happen. An error that matches no rule fails the run; so does a
classified error the run does not permit. A required rule that never shows is reported separately, as REVIEW NEEDED: it is
not a functional failure but a sign the simulator changed, so the classification should be looked at. Only these diagnostic
launches require a known error; the ordinary scenarios (interact.sh) permit one and never depend on it. Four synthetic logs prove the
classifier can fail for each of those reasons.

Usage: diagnose_verdict.py RUN_DIR WINDOW_SECONDS. Exit status 0 is PASS, 1 is FAIL.
"""
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True   # nothing is written beside the scripts
sys.path.insert(0, str(Path(__file__).resolve().parent))
import known_failures as kf  # noqa: E402

CHECK = re.compile(r"^SIMLAB check (PASS|FAIL) \[(\w+)\] (.*?) \| expected=(.*?) \| actual=(.*)$", re.M)
DONE = re.compile(r"^SIMLAB done steps=(\d+) simSeconds=([\d.]+) passed=(\d+) failed=(\d+) aborted=(\w+) stopped=(\w+)$", re.M)
VOICE, HELLO = "voice-settings-unsupplied", "addon-message-invalid-utf8"


def load(run, name):
    text = ""
    for suffix in ("stderr", "stdout"):   # stderr first: it carries both the tick markers and the errors, in order
        text += (run / f"{name}.{suffix}").read_text(errors="replace") + "\n"
    checks = [m.groups() for m in CHECK.finditer(text)]
    done = DONE.search(text)
    ticks = [float(t) for t in re.findall(r"^SIMLAB tick t=([\d.]+)", text, re.M)]
    return {"text": text, "checks": checks, "done": done, "ticks": ticks}


def main():
    run, window = Path(sys.argv[1]), float(sys.argv[2])
    results, stale = [], []

    def check(name, passed, detail=""):
        results.append(bool(passed))
        if not passed and name.endswith("(else the rule is stale)"):
            stale.append(name)
        print(f"  {'pass' if passed else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))

    def scenario(label, d, expect_window):
        failed = [c for c in d["checks"] if c[0] == "FAIL"]
        check(f"{label}: the scenario reached its end", d["done"] and d["done"].group(5) == "false", d["done"].group(0) if d["done"] else "no done line")
        check(f"{label}: no check failed", d["checks"] and not failed,
              f"{len(failed)} failed; first: {failed[0][2]} expected={failed[0][3]} actual={failed[0][4]}" if failed else f"{len(d['checks'])} passed")
        check(f"{label}: the printed counts agree with the lines", d["done"] and int(d["done"].group(3)) == len(d["checks"]) - len(failed)
              and int(d["done"].group(4)) == len(failed))
        if expect_window:
            sim = float(d["done"].group(2)) if d["done"] else 0
            check(f"{label}: the clock ran the whole declared window", sim >= window and d["ticks"] and d["ticks"][-1] >= window - 1e-6,
                  f"{sim} s simulated, last tick {d['ticks'][-1] if d['ticks'] else None}, window {window}")

    def classified(label, d, allow, require):
        r = kf.classify(d["text"], allow=allow, require=require)
        for name, passed, detail in kf.verdict_lines(r):
            check(f"{label}: {name}", passed, detail)
        return r

    contract, baseline, solo, grouped, login = (load(run, n) for n in ("contract", "baseline", "solo", "grouped", "login"))
    voice_due = window >= 6   # the ticker's first call comes about 4.5 s after the script starts, its second about 9.5 s

    print("Minimal reproduction, no addon loaded (what the simulator's SendAddonMessage accepts):")
    scenario("contract", contract, False)
    n = [c for c in contract["checks"]]
    check("contract: every UTF-8 case was judged against the simulator's own answer", len(n) >= 20, f"{len(n)} checks")
    classified("contract", contract, (), ())

    print("Baseline, no addon loaded, the clock over the window:")
    scenario("baseline", baseline, True)
    rb = classified("baseline", baseline, (VOICE,), (VOICE,) if voice_due else ())
    check("baseline: no addon message was attempted and the hello rule did not fire", HELLO not in rb["known"] and not rb["unexpected"])

    print("TwichUI, solo (left the sample party, state verified), the clock over the window:")
    scenario("solo", solo, True)
    rs = classified("solo", solo, (VOICE,), ())
    check("solo: the hello rule did not fire (no send was attempted)", HELLO not in rs["known"] and HELLO not in rs["unexpected"])

    print("TwichUI, grouped on purpose (the sample party kept), the clock over the window:")
    scenario("grouped", grouped, True)
    rg = classified("grouped", grouped, (VOICE, HELLO), (HELLO,))
    sends = re.findall(r"^SIMLAB attempt n=(\d+) at=([\d.]+) prefix=(\S+) chatType=(\S+) len=(\d+) strictUtf8=(\w+) ok=(\w+) result=(.*?) hex=(\S+)", grouped["text"], re.M)
    hello_sends = [s for s in sends if s[2] == "TwichUISetup"]
    check("grouped: the hello was attempted and the simulator refused it", hello_sends and hello_sends[0][6] == "false"
          and "not valid UTF-8" in hello_sends[0][7], f"{len(sends)} attempt(s); first: {hello_sends[0][2:8] if hello_sends else None}")
    check("grouped: the refused payload is not UTF-8 and the accepted ones are", all((s[5] == "true") == (s[6] == "true") for s in sends),
          ", ".join(f"{s[2]} len={s[4]} utf8={s[5]} accepted={s[6]}" for s in sends))

    print("TwichUI, grouped, then a SYNTHETIC PLAYER_ENTERING_WORLD fired by the lab (reaches the 6 s login hello):")
    scenario("login", login, True)
    rl = classified("login", login, (VOICE, HELLO), (HELLO,))
    lsends = re.findall(r"^SIMLAB attempt n=(\d+) at=([\d.]+) prefix=(\S+) ", login["text"], re.M)
    check("login: the lab's event was labelled synthetic in the log", "SIMLAB synthetic firing PLAYER_ENTERING_WORLD" in login["text"])
    check("login: two hello attempts (3 s and 6 s); the simulator's own startup gave one", sum(1 for x in lsends if x[2] == "TwichUISetup") == 2,
          ", ".join(f"{x[2]}@{x[1]}" for x in lsends))

    # The settings scenario permits only the voice error. Applied to the real grouped log, that permit set must reject the
    # hello: going solo there is a fixture choice that the checks would catch if it were hiding anything.
    reject = kf.classify(grouped["text"], allow=(VOICE,))
    check("the settings scenario's permit set (voice only) rejects the real grouped log", list(reject["unexpected"]) == [HELLO],
          ", ".join(reject["unexpected"]) or "nothing rejected")

    print("The classifier can fail (synthetic logs; no simulator involved):")
    unknown_log = "SIMLAB tick t=1.0\nLua error: Lua Error: attempt to index a nil value\nstack\n"
    check("an unclassified error fails", bool(kf.classify(unknown_log, allow=(VOICE, HELLO))["unknown"]))
    voice_log = "SIMLAB tick t=1.0\nLua error: C_VoiceChat.CanAccessSettings: settings access has not been supplied\n\n"
    check("a classified error the run does not permit fails", bool(kf.classify(voice_log, allow=())["unexpected"]))
    check("a required error that never came fails", kf.classify("SIMLAB tick t=1.0\n", allow=(VOICE,), require=(VOICE,))["missing"] == [VOICE])
    general = "Lua error: string at argument 2 is not valid UTF-8\n[Interface/AddOns/Other.lua]:1: in function 'x'\n\n"
    check("the UTF-8 message without the SendAddonMessage stack is not classified", bool(kf.classify(general, allow=(VOICE, HELLO))["unknown"]))

    ok = all(results)

    print("What this run found, by kind (not one pass/fail):")
    passed_checks = {n: sum(1 for c in d["checks"] if c[0] == "PASS") for n, d in
                     (("contract", contract), ("baseline", baseline), ("solo", solo), ("grouped", grouped))}
    print("  Passed behavior ........... " + ", ".join(f"{k}: {v} checks" for k, v in passed_checks.items()))
    print(f"  Simulated time ............ {window:g} s declared in baseline, solo and grouped, "
          f"{baseline['done'].group(2) if baseline['done'] else '?'} / {solo['done'].group(2) if solo['done'] else '?'} / "
          f"{grouped['done'].group(2) if grouped['done'] else '?'} s run; {len(grouped['ticks'])} 0.5 s ticks of 0.05 s clock steps each")
    for line in kf.describe(rb) if VOICE in rb["known"] else ["  Unsupported behavior (simulator): none seen"]:
        print(line)
    for line in kf.describe({"known": {k: v for k, v in rg["known"].items() if k == HELLO}}) or ["  Known delayed failure: none seen"]:
        print(line)
    print("  Shimmed behavior .......... C_ChatInfo.RegisterAddonMessagePrefix and IsAddonMessagePrefixRegistered remember names only. "
          "No other API is shimmed; nothing was added for C_VoiceChat, and no error is hidden.")
    print("  Excluded subsystems ....... addon-message delivery and receipt, voice chat, secure actions, real input, reload persistence, the real client.")
    print("  Login hello (6 s) ......... NOT reached by the simulator's own startup: PLAYER_ENTERING_WORLD(true, false) did occur, "
          "IsInGroup() was false at that moment, so the timer was never scheduled. Reached only by the lab's synthetic event ('login' launch).")
    if ok:
        print("PASS WITH KNOWN SIMULATOR LIMITATIONS (diagnostic: the known errors above were reproduced and classified; "
              "this is not a run without runtime errors)")
    elif stale and len(stale) == len([r for r in results if not r]):
        print("REVIEW NEEDED: a classified simulator behavior did not occur. The simulator may have changed; check "
              "known_failures.py and docs/simulator-lab.md before relying on those rules. (Nothing else failed.)")
    else:
        print("FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
