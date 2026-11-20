#!/usr/bin/env python3
"""Standalone preview assertions, screenshots, replay and negative control."""
import re
import sys
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from verdict import read_rgba, distinct_colours
import known_failures as kf
CHECK = re.compile(r'^SIMLAB check (PASS|FAIL) \[(\w+)\] (.*?) \| expected=(.*?) \| actual=(.*)$', re.M)
DONE = re.compile(r'^SIMLAB done steps=(\d+) simSeconds=([\d.]+) passed=(\d+) failed=(\d+) aborted=(\w+) stopped=(\w+)$', re.M)
POSES = ('shell', 'replay', 'small', 'scaled', 'empty', 'filtered', 'resized', 'shopping', 'shoppingsmall', 'shoppingpurpose', 'categories', 'loading', 'liveprepare', 'sell', 'sellobserved', 'sellsmall', 'sellscaled', 'sellempty', 'owned', 'ownedsmall', 'ownedempty', 'market', 'markethover', 'marketdrag', 'marketinterval', 'marketsingle', 'marketcopper', 'marketsmall', 'marketscaled', 'marketsparse', 'marketempty', 'marketrecent', 'marketlong', 'markettracked', 'marketlarge', 'marketmetadata', 'marketstale', 'marketerror', 'marketbridge', 'scopedpriced', 'scopedoutside', 'scopedabsent', 'scopedunknown', 'scopedcorrupt', 'scopedfuture', 'companionvalid', 'companionnewer', 'companionolder', 'summaryvalid', 'summarycorrupt', 'summaryfuture', 'wrong')


def select(names):
    selected = list(names) if names else list(POSES)
    if len(selected) != len(set(selected)) or any(n not in POSES for n in selected):
        raise ValueError('invalid or duplicate Auction House pose')
    if 'wrong' in selected and 'shell' not in selected:
        raise ValueError('wrong requires shell for negative-control comparison')
    if 'replay' in selected and 'shell' not in selected:
        raise ValueError('replay requires shell')
    return selected


def judge(run, names=None):
    selected = select(names)
    print('FULL default catalog' if selected == list(POSES) else 'FOCUSED ONLY: ' + ' '.join(selected))
    outcomes, transcripts = [], {}
    def check(label, passed):
        outcomes.append(bool(passed)); print(f"  {'pass' if passed else 'FAIL'} {label}")
    for name in selected:
        text = '\n'.join((run / f'{name}.{suffix}').read_text(errors='replace') for suffix in ('stderr', 'stdout'))
        checks, done = CHECK.findall(text), DONE.search(text)
        failures = [c for c in checks if c[0] == 'FAIL']; transcripts[name] = checks
        check(f'{name}: all steps complete', done and done[1] == '9' and done[5] == done[6] == 'false')
        check(f'{name}: counts agree', done and int(done[3]) == len(checks)-len(failures) and int(done[4]) == len(failures))
        check(f'{name}: full assertions', len(checks) == (149 if name.startswith('summary') else 163 if name.startswith('companion') else 147 if name=='marketbridge' or name.startswith('scoped') else 141 if name in ('markethover','categories','liveprepare') else 139 if name=='marketdrag' else 137 if name in ('loading','marketmetadata','marketinterval') else 136) and {c[1] for c in checks} == {'init','construct','interact','state'})
        check(f'{name}: expected outcomes', (len(failures)==1 and failures[0][2]=='Browse default') if name=='wrong' else not failures)
        for label, passed, detail in kf.verdict_lines(kf.classify(text, allow=('voice-settings-unsupplied',), require=('voice-settings-unsupplied',))):
            check(f'{name}: {label} {detail}', passed)
        w,h,rgba = read_rgba(run / f'{name}.png')
        check(f'{name}: image dimensions', (w,h) == ((1000,700) if name in ('small','shoppingsmall','sellsmall','ownedsmall','marketsmall') else (1600,1200)))
        check(f'{name}: window not blank', distinct_colours(rgba,w//5,h//4,w*3//5,h//2) > 150)
    if 'replay' in selected:
        check('independent replay identical', transcripts['shell']==transcripts['replay'])
    if 'wrong' in selected:
        check('negative control retains other outcomes', len(transcripts['shell'])==len(transcripts['wrong']) and all(
        a==b if a[2]!='Browse default' else b[0]=='FAIL' for a,b in zip(transcripts['shell'],transcripts['wrong'])))
    print('PASS: standalone preview; synthetic data, handler-level only' if all(outcomes) else 'FAIL: standalone preview')
    return all(outcomes)
if __name__ == '__main__':
    if sys.argv[1:] == ['--list']:
        print(' '.join(POSES))
    else:
        sys.exit(0 if judge(Path(sys.argv[1]), sys.argv[2:]) else 1)
