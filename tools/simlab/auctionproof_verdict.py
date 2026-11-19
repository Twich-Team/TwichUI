#!/usr/bin/env python3
"""AH-1a structured checks, replay, failure control and existing error rules."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import known_failures as kf

CHECK = re.compile(r'^SIMLAB check (PASS|FAIL) \[(\w+)\] (.*?) \| expected=(.*?) \| actual=(.*)$', re.M)
DONE = re.compile(r'^SIMLAB done steps=(\d+) simSeconds=([\d.]+) passed=(\d+) failed=(\d+) aborted=(\w+) stopped=(\w+)$', re.M)


def judge(run):
    results, transcripts = [], {}

    def check(name, passed):
        results.append(bool(passed))
        print(f"  {'pass' if passed else 'FAIL'} {name}")

    for name in ('unloaded', 'replay', 'loaded', 'wrong'):
        text = '\n'.join((run / f'{name}.{suffix}').read_text(errors='replace') for suffix in ('stderr', 'stdout'))
        checks, done = CHECK.findall(text), DONE.search(text)
        transcripts[name] = checks
        failures = [c for c in checks if c[0] == 'FAIL']
        check(f'{name}: all eight steps complete', done and done[1] == '8' and done[5] == 'false' and done[6] == 'false')
        check(f'{name}: counts agree', done and int(done[3]) == len(checks) - len(failures) and int(done[4]) == len(failures))
        check(f'{name}: all evidence layers', {c[1] for c in checks} == {'init', 'construct', 'interact', 'state'})
        check(f'{name}: full timeout window', done and float(done[2]) >= 30.4)
        if name == 'wrong':
            check('wrong: only deliberate check fails', len(failures) == 1 and failures[0][2] == 'explicit activation parks')
        else:
            check(f'{name}: every lifecycle assertion passes', len(checks) >= 90 and not failures)
        faults = re.findall(r'^SIMLAB injected-fault (.*)$', text, re.M)
        check(f'{name}: only the intended fault was intercepted', len(faults) == 1
              and faults[0].startswith('auction proof activate ')
              and faults[0].endswith('injected AH-1a anchor failure'))
        classified = kf.classify(text, allow=('voice-settings-unsupplied',), require=('voice-settings-unsupplied',))
        for label, passed, detail in kf.verdict_lines(classified):
            check(f'{name}: {label} {detail}', passed)
    check('independent replay has identical assertions', transcripts['unloaded'] == transcripts['replay'])
    wrong = transcripts['wrong']
    check('negative control retains every other outcome', len(wrong) == len(transcripts['unloaded']) and all(
        a == b if a[2] != 'explicit activation parks' else b[0] == 'FAIL'
        for a, b in zip(transcripts['unloaded'], wrong)))
    print('PASS: synthetic lifecycle only; no real-client/taint/input/server proof' if all(results) else 'FAIL: AH-1a simulator proof')
    return all(results)


if __name__ == '__main__':
    sys.exit(0 if judge(Path(sys.argv[1])) else 1)
