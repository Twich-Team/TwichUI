#!/usr/bin/env python3
"""Added dev-mode workflow, replay and deliberately wrong expectation."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from auctionproof_verdict import CHECK, DONE
import known_failures as kf


def judge(run):
    outcomes, transcripts = [], {}
    def check(label, passed):
        outcomes.append(bool(passed))
        print(f"  {'pass' if passed else 'FAIL'} {label}")
    for name in ('debug', 'debugreplay', 'debugwrong'):
        text = '\n'.join((run/f'{name}.{suffix}').read_text(errors='replace') for suffix in ('stdout', 'stderr'))
        checks, done = CHECK.findall(text), DONE.search(text)
        transcripts[name] = checks
        failed = [c for c in checks if c[0] == 'FAIL']
        check(f'{name}: four full steps and 61s active', done and done[1]=='4' and float(done[2])>=61 and done[5]==done[6]=='false')
        check(f'{name}: assertions and counts', len(checks)>=44 and done and int(done[3])+int(done[4])==len(checks))
        check(f'{name}: expected outcome', len(failed)==1 and failed[0][2]=='full interface opens directly' if name=='debugwrong' else not failed)
        for label, passed, detail in kf.verdict_lines(kf.classify(text, allow=('voice-settings-unsupplied',), require=('voice-settings-unsupplied',))):
            check(f'{name}: {label} {detail}', passed)
    check('independent dev workflow replay matches', transcripts['debug']==transcripts['debugreplay'])
    check('negative control preserves other outcomes', len(transcripts['debug'])==len(transcripts['debugwrong']) and all(
        a==b if a[2]!='full interface opens directly' else b[0]=='FAIL' for a,b in zip(transcripts['debug'],transcripts['debugwrong'])))
    print('PASS: synthetic dev-mode workflow; native acceptance pending' if all(outcomes) else 'FAIL: dev-mode workflow')
    return all(outcomes)


if __name__ == '__main__':
    sys.exit(0 if judge(Path(sys.argv[1])) else 1)
