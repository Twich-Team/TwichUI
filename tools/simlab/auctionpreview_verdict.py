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
def judge(run):
    outcomes, transcripts = [], {}
    def check(label, passed):
        outcomes.append(bool(passed)); print(f"  {'pass' if passed else 'FAIL'} {label}")
    catalog = ('shell', 'replay', 'small', 'scaled', 'empty', 'filtered', 'resized', 'shopping', 'shoppingsmall', 'shoppingpurpose', 'categories', 'loading', 'liveprepare', 'sell', 'sellobserved', 'sellsmall', 'sellscaled', 'sellempty', 'owned', 'ownedsmall', 'ownedempty', 'market', 'marketsmall', 'marketscaled', 'marketsparse', 'marketempty', 'marketrecent', 'marketlong', 'markettracked', 'marketlarge', 'marketmetadata', 'marketstale', 'marketerror', 'marketbridge', 'scopedpriced', 'scopedoutside', 'scopedabsent', 'scopedunknown', 'scopedcorrupt', 'scopedfuture', 'wrong')
    selected = tuple(sys.argv[2:]) or catalog
    if len(set(selected))!=len(selected) or set(selected)-set(catalog):
        raise ValueError('invalid auctionpreview subset')
    if ('wrong' in selected or 'replay' in selected) and 'shell' not in selected:
        raise ValueError('replay/negative control requires shell')
    print('selection: full catalog' if set(selected)==set(catalog) else 'selection: subset ('+', '.join(selected)+')')
    for name in selected:
        text = '\n'.join((run / f'{name}.{suffix}').read_text(errors='replace') for suffix in ('stderr', 'stdout'))
        checks, done = CHECK.findall(text), DONE.search(text)
        failures = [c for c in checks if c[0] == 'FAIL']; transcripts[name] = checks
        check(f'{name}: all steps complete', done and done[1] == '9' and done[5] == done[6] == 'false')
        check(f'{name}: counts agree', done and int(done[3]) == len(checks)-len(failures) and int(done[4]) == len(failures))
        check(f'{name}: full assertions', len(checks) == (141 if name=='marketbridge' or name.startswith('scoped') else 131 if name in ('loading','marketmetadata') else 130) and {c[1] for c in checks} == {'init','construct','interact','state'})
        check(f'{name}: expected outcomes', (len(failures)==1 and failures[0][2]=='Browse default') if name=='wrong' else not failures)
        for label, passed, detail in kf.verdict_lines(kf.classify(text, allow=('voice-settings-unsupplied',), require=('voice-settings-unsupplied',))):
            check(f'{name}: {label} {detail}', passed)
        w,h,rgba = read_rgba(run / f'{name}.png')
        check(f'{name}: image dimensions', (w,h) == ((1000,700) if name in ('small','shoppingsmall','sellsmall','ownedsmall','marketsmall') else (1600,1200)))
        check(f'{name}: window not blank', distinct_colours(rgba,w//5,h//4,w*3//5,h//2) > 150)
    if 'replay' in selected:
        check('independent replay identical', transcripts.get('shell')==transcripts['replay'])
    if 'wrong' in selected: check('negative control retains other outcomes', len(transcripts['shell'])==len(transcripts['wrong']) and all(
        a==b if a[2]!='Browse default' else b[0]=='FAIL' for a,b in zip(transcripts['shell'],transcripts['wrong'])))
    print('PASS: standalone preview; synthetic data, handler-level only' if all(outcomes) else 'FAIL: standalone preview')
    return all(outcomes)
if __name__=='__main__': sys.exit(0 if judge(Path(sys.argv[1])) else 1)
