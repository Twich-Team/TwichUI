# Frozen bridge v1 mirror

These four contract files are mirrored byte for byte from the exact Market commit in [UPSTREAM.json](UPSTREAM.json). The authoritative [contract and semantic validator](https://github.com/Twich-Team/TwichUI-Market/tree/941f0f2d80019665f7caa2a3c4d76cfb6910c91c/contracts/bridge/v1) define identities, bases, integrity and bounds. Both generations are synthetic; they contain no production export.

`tests/test_pricing_conformance.py` verifies hashes and the dormant Lua module's header capabilities. This is not a full packet validator or import path. Unknown contract/algorithm/basis versions must fail closed. The original research fixtures remain separately pinned in `../pricing_v1`.
