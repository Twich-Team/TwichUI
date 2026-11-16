# Amendment 001: immutable server generations and delivery receipts

Status: coordinated M1b review amendment. Contract version 1 and transport version 1 remain; new producer generations declare **schema version 2**. Original schema-1 fixtures and their manifest remain immutable. The new schema and fixtures have a separate checksum manifest and are mirrored from one pinned Market commit.

## Defects found in M1b review

The schema-1 generation requires `desktop_sync_completed_at` and hashes it into its identity. A server cannot truthfully supply the completion time of an unfinished desktop download. Changing it after download also changes the generation identity, defeating cross-component identity verification. Supplying a server timestamp under this name or a predicted completion time would invent delivery provenance.

The schema-1 fractional timestamp regular expression is overescaped and rejects valid UTC fractional seconds, despite the normative precision requirement. This would reject actual retained collector timestamps or encourage unsafe truncation.

## Selected resolution

Schema 2 permits `desktop_sync_completed_at=null` for a server-sealed generation, with `producer.desktop_build=not-applicable-server-export`. Those values stay unchanged through server pagination, cache, generated addon and Workshop. Actual acquisition completion time, desktop build and generation identity are recorded in a separate bounded desktop delivery receipt, outside the source-generation hash. No account/device identifiers or credentials enter game files. A validated older schema-1 artifact retains its original timestamp and identity.

Schema 2 corrects fractional UTC timestamp patterns to accept 0..6 fractional digits and preserves them exactly. No daily-close selection truncates source timestamps.

Recomputing identity per delivery, relabeling server time as desktop completion, stripping timestamps and silently changing the old schema were rejected. Schema version 2 is an explicit compatibility boundary; schema-1-only readers must reject it. Algorithm IDs, history bases, quality policy, bounds and canonical hash definitions do not change.

## Engineering review and acceptance

Verify schema-1 bytes unchanged; validate schema-1 and schema-2 independent fixtures in Python/Rust/Lua; verify null versus known delivery provenance, fractional chronology, stable identity after transport and receipt updates, future-schema rejection and byte-identical pinned mirrors. The M1b PR pair carries this amendment for owner review; nothing is activated or deployed by the amendment.
