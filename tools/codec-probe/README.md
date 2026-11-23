# Temporary Forever codec probe

Development-only, removable addon. It obtains native evidence; it is **not** the
13-addon implementation or a production compression library. `tools/` is excluded
by the existing release packager. No Market server, Companion, login or credentials
are needed. No Market/account/character/realm data is read.

## Owner: install, run, copy, remove

1. Exit WoW. Unzip **only** `TwichUI_CodecProbe/` into your Forever installation:
   `<WoW Forever>/Interface/AddOns/TwichUI_CodecProbe/`.
   That folder must directly contain its `.toc` and four Lua files. It must not be
   nested inside a second `TwichUI_CodecProbe` folder. No existing addon is replaced.
2. Enable **TwichUI Codec Probe (DEV ONLY)** for this test session, then log in.
3. Out of combat, run **`/tui codecprobe`** once. The report window opens and runs
   the finite test sequence. A chat summary appears when it finishes.
4. The complete report is selected automatically: press **Ctrl+C** and paste the
   text back to Codex. The **Select report** button selects it again. No screenshots
   are needed. Escape/close cancels remaining work; `/tui codecprobe show` reopens
   the last report without another run.
5. Exit WoW and delete **only** `Interface/AddOns/TwichUI_CodecProbe/`. Remove it
   before normal gameplay. No SavedVariables cleanup or Market rollback is needed.

The standalone alias is **`/tuicodecprobe`** (and `/tuicodecprobe show`). With
TwichUI installed, the removable addon intercepts only the exact `codecprobe`
subcommand and delegates every other `/tui` command unchanged. It does not edit
TwichUI's private command table or source. Without TwichUI, it registers `/tui`
only if that alias is unoccupied. If another addon owns `/tui`, use the standalone
alias. No existing command named `codecprobe` exists in the inspected main/prepared
sources. Removing the addon and restarting removes this temporary registration.

## What runs

Nothing decompresses and no timers start at login. Only fixed synthetic fixtures
and command handlers load. Tests start only from the explicit command. One owned
one-shot timer processes one case at a time; closing cancels it. There is no
OnUpdate/polling loop, network, downloaded Lua execution, SavedVariables, settings
change, forced collection or GC tuning. Entering combat cancels remaining tests.

The API calls match the available Forever reference 1.60.1.70938 at
`bebcb6bf309cf41b41bd74f8ca651e6a105b2676`: `DecodeBase64(string)` (standard
variant), `DecompressString(bytes, Enum.CompressionMethod.Deflate)`. Deflate's
numeric value zero is supported. Missing APIs/methods are reported, not substituted
with a Lua codec.

* Known externally generated raw-Deflate and zlib streams must return exact
  original bytes. Known Base64 must return the exact original binary stream.
  A self round trip is never sufficient. An identity stub produces failures.
* Refused raw/zlib wrappers are marked unsupported **only if** another external
  wrapper works; a present decoder that accepts neither is a failure.
* Malformed tests are only a one-byte reserved block (or seven-byte zlib form)
  and a truncated tiny stream whose complete output is 4,600 bytes. Nil/exception
  refusal is recorded; non-nil output is recorded as failed refusal.
* Valid performance fixtures: 200,263-byte fixed-width/proof-like current data,
  336,400-byte 60-day historical JSON and 524,288-byte historical JSON, each twice.
  A 16-callback group repeats the 336,400-byte history sample. The report labels
  this repetition; it is not sixteen different complete Market partitions.
* Known streams/expected bytes come from `generate_vectors.py` with seeded public
  synthetic inputs. Large zlib streams reuse a raw stream plus literal externally
  generated header/trailer bytes to keep the package small. No runtime encoder or
  checksum implementation is introduced. Host zlib and existing offline LibDeflate
  independently verify byte equality. LibDeflate is **not shipped or used in-game**.

At most 27 cases, largest known output **512 KiB per call**, about 1 MiB of resident
expected strings plus encoded fixtures/code. A failed large fixture, >50 ms native
call, >100 ms engine step, ten-second wall budget, close or combat stops remaining
work. These are tool bounds and circuit breakers, **not native allocation limits**.
No bomb, arbitrary input or unknown expansion is tested. A native call cannot be
interrupted by a Lua timer once entered.

## Reading the report

It separates passed, unsupported, failed and deliberately not-performed cases.
It records the source commit, client build, clock, exact input/output byte counts,
Base64 and synchronous decompression elapsed time, worst engine-step callback,
sampled Lua heap deltas and the sum of native history-group calls.

Timing is synchronous elapsed time, **not exclusive CPU** or a WoW frame scheduler
reproduction. Engine-step timing includes Base64/codec/heap query/equality but
excludes export-window formatting and other addons. Heap samples are not allocator
peaks, RSS or native buffer measurements. Expected Lua strings are resident and
can be interned/reused; zero heap delta does not establish allocation-free decoding.
Natural GC can yield negative deltas. The native decoder's resource ceilings remain
unknown even when every safe fixture passes.

A successful report supplies missing interoperability/timing evidence; it does
not certify 13 physical TOCs, full Opportunities performance, migration, ownership,
atomic publication or rollback. Those remain separate held work. Actual native
Forever behavior is **not claimed** until the owner returns a real report.

## Development commands

From the repository root, using the existing Lua5.1/bit test environment:

```bash
python tools/codec-probe/generate_vectors.py
luac5.1 -p tools/codec-probe/TwichUI_CodecProbe/*.lua
./tests/run.sh development market-performance --jobs 2
python tools/codec-probe/package_probe.py --out /path/to/TwichUI_CodecProbe-dev.zip
```

Packaging requires clean committed source, includes only the five required files,
embeds its exact commit and source-file hashes, fixes ZIP metadata for repeatability
and writes a SHA256 sidecar. Do not use this ZIP as a TwichUI/Companion release.
The large `Vectors.lua` is generated at packaging time rather than checked into
source. The committed generator/reference hashes and independent decoder tests
cover its bytes; the ZIP sidecar records the actual generated-file hash and zlib
runtime. The native report records the build's source commit.

Fast checks include actual independent fixture decoding, ZIP/TOC/release-exclusion
validation, explicit invocation, stub rejection, exceptions, unsupported wrappers,
slow/error/budget stops, cancellation, report reopens, standalone command conflicts
and delegation. Simulator checks validate construction/flow and expose identity
stubs; they are **not** native codec evidence. No slow benchmark is added to normal
development commands.
