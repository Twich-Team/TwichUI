# Temporary development download

**Remove this entire `test-artifacts/codec-probe/` directory before any merge into
main.** This ZIP is an owner-requested download for draft PR #135, not a release
artifact. Production packaging is unchanged; this directory must not reach a
release.

`TwichUI_CodecProbe-dev-4fd74f4.zip` is the already verified standalone probe from
source commit `4fd74f4f76dce70921e261d324c94508e04e69c3` (852625 bytes).

SHA256: `0d010c4e13d869b40ad8b8c7f0c104820666abea4c5657dbb2c9f8018f25476d`

Exit WoW, extract its single `TwichUI_CodecProbe/` folder into
`<WoW Forever>/Interface/AddOns/`, enable the DEV addon for one session, and run
`/tui codecprobe` out of combat. When finished, copy the selected report with
Ctrl+C. Exit WoW and remove only the probe folder before normal gameplay. No
SavedVariables cleanup is needed.

Only the TOC and four required Lua files are included. All fixtures are public
synthetic data. Actual Forever codec behavior remains unverified until the owner
returns the report. [Full instructions and limitations](../../tools/codec-probe/README.md).
