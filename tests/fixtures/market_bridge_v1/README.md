# Frozen bridge v1 mirror

All files listed in [UPSTREAM.json](UPSTREAM.json) are exact bytes from the pinned Market implementation commit. Market owns the authoritative schemas, fixtures and semantic validator. Never regenerate expectations independently in this repository.

Original schema-1 generations and their SHA256SUMS remain unchanged. [AMENDMENT-001.md](AMENDMENT-001.md) coordinates source-sealed schema 2 and the separate desktop delivery receipt. SCHEMA2-SHA256SUMS covers two source generations, fractional daily-close ordering and partial/unknown scope. E2E-SHA256SUMS covers explicitly synthetic observations and independently calculated expected results, including two available dates with an intervening gap. None is a production-history export.

The actual Workshop reader tests validate both supported schemas, identities, integrity and history semantics. The generated BridgeSchema.lua plan is reproduced from these authoritative schemas by Market's scripts/generate-bridge-lua-schema.py. Original pricing research fixtures remain separately pinned in ../pricing_v1.
