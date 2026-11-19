#!/usr/bin/env python3
"""AH-7A synthetic integration, structural captures, replay and negative control."""
import re
import sys
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from auctionproof_verdict import CHECK, DONE
from verdict import read_rgba, distinct_colours
import known_failures as kf
POSES = ('integrated', 'integratedreplay', 'integratedsmall', 'integratedscaled', 'integratedblizzard', 'integratedwrong')


def judge(run):
    outcomes, transcripts = [], {}
    def check(label, passed):
        outcomes.append(bool(passed))
        print(f"  {'pass' if passed else 'FAIL'} {label}")
    for name in POSES:
        text = '\n'.join((run / f'{name}.{suffix}').read_text(errors='replace') for suffix in ('stderr', 'stdout'))
        checks, done = CHECK.findall(text), DONE.search(text)
        transcripts[name] = checks
        failures = [c for c in checks if c[0] == 'FAIL']
        check(f'{name}: all eight steps complete', done and done[1] == '8' and done[5] == done[6] == 'false')
        check(f'{name}: counts agree', done and int(done[3]) == len(checks)-len(failures) and int(done[4]) == len(failures))
        check(f'{name}: lifecycle and reachability assertions present', len(checks) == 162 and {c[1] for c in checks} == {'init','construct','interact','state'})
        check(f'{name}: expected outcomes', (len(failures)==1 and failures[0][2]=='existing five-page shell is integrated') if name=='integratedwrong' else not failures)
        for label, passed, detail in kf.verdict_lines(kf.classify(text, allow=('voice-settings-unsupplied',), require=('voice-settings-unsupplied',))):
            check(f'{name}: {label} {detail}', passed)
        w,h,rgba=read_rgba(run / f'{name}.png')
        check(f'{name}: capture dimensions', (w,h)==((1000,700) if name=='integratedsmall' else (1600,1200)))
        check(f'{name}: capture is not blank', distinct_colours(rgba,0,0,w,h)>150)
    check('integrated independent replay identical', transcripts['integrated']==transcripts['integratedreplay'])
    check('integrated negative control preserves every other assertion', len(transcripts['integrated'])==len(transcripts['integratedwrong']) and all(
        a==b if a[2]!='existing five-page shell is integrated' else b[0]=='FAIL'
        for a,b in zip(transcripts['integrated'],transcripts['integratedwrong'])))
    print('PASS: AH-7A synthetic integration/geometry only; Forever acceptance pending' if all(outcomes) else 'FAIL: AH-7A synthetic integration')
    return all(outcomes)


if __name__ == '__main__':
    sys.exit(0 if judge(Path(sys.argv[1])) else 1)
