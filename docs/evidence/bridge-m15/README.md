# M1.5 verification evidence

[Addon acceptance](../../workshop/market-bridge-m15.md) explains the frozen source, results and remaining client gates. [Market's pinned report](https://github.com/Twich-Team/TwichUI-Market/blob/529e7ba354e1ceaec9a02fb0f7e2b089cf7af6a9/docs/workshop-bridge-m15.md) owns the complete capacity/memory matrix and all baseline/candidate samples.

- `verification.json`: final code/test freeze, runtime hashes, actual comprehensive counts and final Market CI run identities.
- `full-cloud.json`: unmodified comprehensive runner report, including simulator catalogs, launches/checks, unsupported coverage and the deliberately false local milestone flag.
- `full-console.log`: unmodified final comprehensive console output.
- `market-mutations.json`: all 234 Market negative-control verdicts; no survivors, invalid mutations, timeouts or infrastructure failures.
- `bridge-mutations.json`: all 16 focused bridge negative-control verdicts, including new deterministic work/identity checks.
- `exploratory-handler-note.json`: one earlier handler observation transcribed from tool output. Its limitations are explicit; it is not raw paired performance evidence.

The comprehensive suite runs once on the final code/test freeze. Later documentation/evidence commits retain the same runtime and test bytes. Cloud no-assets, synthetic fixtures and CI workers do not establish owner Windows/Forever acceptance. No failure, outlier or worst slice is removed to satisfy a target.
