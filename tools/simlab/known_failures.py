#!/usr/bin/env python3
"""Classifies the Lua errors in a simulator log (docs/simulator-lab.md "Delayed failures").

A lab run used to stay under 2.5 simulated seconds so that two known errors never happened. This module is what replaced
that: the clock runs over the whole declared window, and every error the log holds must match a rule here or the run fails.

A rule matches on what the error IS, never on when it happened: its message, and (when the message alone is too general)
parts of the stack that tie it to the mechanism. A run states which rules it permits; a matching error the run does not
permit fails it, and so does an error that matches no rule. A rule a run requires but never saw also fails it: that means the
classification is out of date (the simulator changed), which is worth knowing.

Nothing here edits a log, hides an error, or looks at the clock to decide anything. "first_tick" is only where in the
window the error was first printed, read from the scenario's own tick markers.
"""
import re
from collections import Counter

RULES = {
    "voice-settings-unsupplied": {
        "label": "C_VoiceChat.CanAccessSettings is not answered by the simulator",
        "category": "Unsupported behavior (simulator), shows up as a delayed error",
        "message": r"^C_VoiceChat\.CanAccessSettings: settings access has not been supplied$",
        "context": [],
        "why": ("Blizzard's own audio-settings registration starts a 5 s ticker that calls C_VoiceChat.CanAccessSettings() until "
                "it returns true (Blizzard_SettingsDefinitions_Shared/Audio.lua:657-669, Forever revision ca8368f2f). The game "
                "documents a non-nil bool; the simulator has the function but raises 'has not been supplied' and offers no "
                "A_Admin setter for it. Reproduces with --no-addons, so no addon is involved."),
    },
    "addon-message-invalid-utf8": {
        "label": "the simulator's SendAddonMessage refuses a payload that is not UTF-8",
        "category": "Known delayed failure (simulator string rule; the game's contract is not established here)",
        "message": r"^string at argument 2 is not valid UTF-8$",
        "context": ["ChatThrottleLib.lua", "PerformSend"],
        "why": ("ChatThrottleLib calls C_ChatInfo.SendAddonMessage under xpcall; the simulator's binding raises this for any "
                "string argument that is not UTF-8 (shown with no addon loaded by scenarios/message_contract.lua). TwichUI's "
                "payloads are LibSerialize + LibDeflate output, which is arbitrary bytes apart from NUL. Whether the game "
                "accepts the same bytes is not established by this lab."),
    },
}

TICK = re.compile(r"^SIMLAB tick t=([\d.]+)")
START = re.compile(r"^Lua error( suppressed (\d+) additional times)?: (.*)$")
TWICH_FRAME = re.compile(r"/!!!TwichUI/(.+?)\]:(\d+): in function (?:'([^']*)'|<[^>]*>)")


def _normalise(message):
    message = message.strip()
    if message.startswith("Lua Error: "):
        message = message[len("Lua Error: "):]
    return message


def blocks(text):
    """One entry per 'Lua error' line: message, how many repeats it stands for, the stack under it, the last tick before it."""
    out, tick, current = [], None, None
    for line in text.splitlines():
        m = TICK.match(line)
        if m:
            tick = float(m.group(1))
        s = START.match(line)
        if s:
            current = {"message": _normalise(s.group(3).splitlines()[0] if s.group(3) else ""),
                       "repeats": int(s.group(2)) if s.group(2) else 1, "suppressed": bool(s.group(1)),
                       "stack": [], "tick": tick}
            out.append(current)
        elif current is not None:
            if line.strip() == "" or line.startswith("SIMLAB "):
                current = None
            else:
                current["stack"].append(line)
    return out


def match(block, seen_with_context):
    """The rule id a block belongs to, or None. A 'suppressed N additional times' summary carries no stack, so it counts
    for a rule only if that rule's full form (message and context) was already seen in the same log."""
    for rid, rule in RULES.items():
        if not re.search(rule["message"], block["message"]):
            continue
        if block["suppressed"]:
            if rid in seen_with_context:
                return rid
            continue
        stack = "\n".join(block["stack"])
        if all(part in stack for part in rule["context"]):
            seen_with_context.add(rid)
            return rid
    return None


def classify(text, allow=(), require=()):
    """Returns {known, unexpected, unknown, missing} for one log.
    known       {rule id: {blocks, repeats, first_tick, origins}} for rules the run permits
    unexpected  rule ids seen although the run does not permit them
    unknown     [(tick, message)] for errors that match no rule
    missing     rule ids the run requires and never saw"""
    allow, require = set(allow) | set(require), set(require)
    known, unexpected, unknown, seen = {}, {}, [], set()
    for block in blocks(text):
        rid = match(block, seen)
        if rid is None:
            unknown.append((block["tick"], block["message"]))
            continue
        if rid not in allow:
            unexpected.setdefault(rid, []).append((block["tick"], block["message"]))
            continue
        k = known.setdefault(rid, {"blocks": 0, "repeats": 0, "first_tick": None, "origins": Counter()})
        k["blocks"] += 0 if block["suppressed"] else 1
        k["repeats"] += block["repeats"] if block["suppressed"] else 0
        if not block["suppressed"] and (k["first_tick"] is None or (block["tick"] is not None and block["tick"] < k["first_tick"])):
            k["first_tick"] = block["tick"]
        frames = ["%s:%s %s" % (f, n, fn or "<anonymous>") for f, n, fn in TWICH_FRAME.findall("\n".join(block["stack"]))]
        if frames:
            k["origins"][" <- ".join(frames)] += 1
    missing = sorted(r for r in require if r not in known)
    return {"known": known, "unexpected": unexpected, "unknown": unknown, "missing": missing}


def verdict_lines(result):
    """(name, passed, detail) for the checks every judged log gets."""
    lines = []
    lines.append(("no Lua error outside the classified rules", not result["unknown"],
                  "; ".join("%s (t=%s)" % (m[:90], t) for t, m in result["unknown"][:2])))
    lines.append(("no classified error the run does not permit", not result["unexpected"],
                  ", ".join(sorted(result["unexpected"]))))
    lines.append(("every required classified error was seen (else the rule is stale)", not result["missing"],
                  ", ".join(result["missing"])))
    return lines


def describe(result, indent="  "):
    """Printable lines saying what was classified, with where in the window it was first printed and where it came from."""
    out = []
    for rid, k in sorted(result["known"].items()):
        rule = RULES[rid]
        out.append(f"{indent}{rule['category']}")
        out.append(f"{indent}  {rid}: {rule['label']}")
        out.append(f"{indent}  seen: {k['blocks']} error(s) printed in full, {k['repeats']} more summarised by the simulator; "
                   f"first printed after simulated t={k['first_tick']} s (ticks are 0.5 s apart)")
        for origin, n in k["origins"].most_common(3):
            out.append(f"{indent}  from TwichUI: {origin} (x{n})")
    return out
