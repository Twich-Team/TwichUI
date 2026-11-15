# Unified pricing fixture mirror

These five JSON/schema/checksum files are an exact mirror of Market's M0.5 fixtures. `UPSTREAM.json` pins the upstream commit and draft PR. Do not regenerate expectations from Workshop code. Review algorithm/fixture changes in both repositories together.

The set contains 23 snapshot cases, eight synthetic calendars and 30 boundary cases. Four snapshot cases are genuine captured one-listing excerpts, with preserved provenance and `scope_complete=false`; they are not full markets or current live observations. Remaining cases are explicitly synthetic.

Run the authoritative offline checker at the pinned Market commit with Python 3 and its JSON Schema test dependency:

```sh
python3 contracts/pricing/v1/verify.py --workshop-source /path/to/isolated/TwichUI
```

Verify the local mirror by hashing `snapshots.json`, `temporal.json`, `boundaries.json` and `fixture.schema.json` against `SHA256SUMS.json`, and comparing all five bytes to the pinned upstream files. The checker does not write fixtures, SavedVariables or databases. Future Lua consumer tests must parse money as strings and compare numbers/reasons/provenance against these same authored expectations, with unsupported values rejected before numeric conversion.

This mirror is outside addon TOCs and is not packaged as runtime pricing or a synchronization bridge. See `docs/workshop/unified-pricing-m05.md` for compatibility and approval decisions.
