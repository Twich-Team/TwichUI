#!/usr/bin/env python3
"""Opt-in Linux command telemetry. No simulator or assertion behavior changes.

Usage: python3 tools/measure_command.py OUTPUT.json -- COMMAND [ARGS ...]
CPU is reaped child CPU; sampled tree RSS is a lower bound, not peak heap.
"""
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import time


def tree_sample(root, cpu):
    records = {}
    for path in Path('/proc').glob('[0-9]*/stat'):
        try:
            fields = path.read_text().rsplit(')', 1)[1].split()
            records[int(path.parent.name)] = (int(fields[1]), int(fields[21]), int(fields[19]), int(fields[11]), int(fields[12]))
        except (OSError, ValueError, IndexError):
            continue
    selected = {root}
    while True:
        children = {pid for pid, (parent, *_) in records.items() if parent in selected}
        if children <= selected:
            break
        selected |= children
    for pid in selected.intersection(records):
        _, _, started, user, system = records[pid]
        cpu[(pid, started)] = (user, system)
    return sum(records[pid][1] for pid in selected if pid in records) * os.sysconf('SC_PAGE_SIZE')


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) < 3 or args[1] != '--':
        raise ValueError(__doc__)
    output, command = Path(args[0]), args[2:]
    start = time.monotonic()
    proc = subprocess.Popen(command)
    # Keep the existing process group: the outer runner kills all descendants
    # on timeout. For direct use, forward termination and reap the child.
    previous = {}
    for sig in (signal.SIGTERM, signal.SIGINT):
        previous[sig] = signal.signal(sig, lambda signum, frame: proc.send_signal(signum) if proc.poll() is None else None)
    peak, samples, cpu = 0, 0, {}
    try:
        while proc.poll() is None:
            peak = max(peak, tree_sample(proc.pid, cpu))
            samples += 1
            try:
                proc.wait(timeout=.1)
            except subprocess.TimeoutExpired:
                pass
        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        report = dict(command=command, exit_code=proc.returncode,
                      wall_seconds=time.monotonic() - start,
                      reaped_child_user_seconds=usage.ru_utime, reaped_child_system_seconds=usage.ru_stime,
                      sampled_tree_user_seconds=sum(t[0] for t in cpu.values()) / os.sysconf('SC_CLK_TCK'),
                      sampled_tree_system_seconds=sum(t[1] for t in cpu.values()) / os.sysconf('SC_CLK_TCK'),
                      cpu_method='100ms per-PID accumulated ticks, including nested simulator; lower bound (short-lived processes may escape samples); reaped-child counters can omit nested PID namespaces',
                      max_reaped_child_rss_kib=usage.ru_maxrss,
                      sampled_peak_tree_rss_bytes=peak, samples=samples,
                      rss_method='100ms /proc descendant RSS sum; shared pages counted more than once; sampling lower bound')
        output.write_text(json.dumps(report, indent=2) + '\n')
        return proc.returncode if proc.returncode >= 0 else 128 - proc.returncode
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


if __name__ == '__main__':
    sys.exit(main())
