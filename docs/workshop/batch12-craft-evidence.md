# W13 — Batch 12 craft-event evidence collection

Implemented diagnostics only. Workshop automatic credit remains off; manual
Done/Undo is unchanged. This supersedes the old probe's “EVIDENCE OK” verdict:
observations alone cannot establish one success per completed craft.

## Owner workflow (development Test Lab only)

Install/open the [development Test Lab](../testlab.md#installation-development-only),
open your own profession, and keep it open. Leave automatic credit off and do not
press Workshop Done during recording. Open `/tuilab`, select only **Crafting
progress probe (opt-in)**, and run `crafting.progress.events`. Complete one scenario
per run within 180 seconds, then click the guided **Done**. Use cheap learned
recipes and ordinary profession controls; the Lab never crafts for you.

Run separately:

1. Three individual Create operations, waiting for each to complete.
2. A three-operation repeated batch.
3. A five-operation batch cancelled after exactly two completed operations.
4. A failed or interrupted attempt; record which happened and how. A normal
   insufficient-material refusal is useful even if it emits no cast event.
5. A recipe producing multiple output items, if available. Record operations
   separately from output quantity; two outputs need not mean two crafts.

For every run, write down the addon revision, selected recipe ID, requested and
actually completed operations, actual output quantity, cancellation/failure action
and whether any unrelated spells were cast. The report includes the client build.
Copy the Test Lab report using its existing report/export view and paste these
written observations beside it. Share the five reports for analysis. If the report
says TRUNCATED, repeat with a smaller scenario; do not interpret missing lines as
missing events. Closing/stopping the run or entering combat cancels capture and
cleans up the listener; finish normally to obtain evidence notes.

## Reading the report

- Registration lists each event: `yes`/`no` are checked registration state;
  `raised` means RegisterEvent threw; `refused` means it returned false without a
  check; `call-ok` means the call returned without error but registration could
  not be queried; `unknown` means a restricted result. Registered does not mean
  an event actually fired. Raw API error text is omitted.
- Codes: SENT/START/OK/FAIL/INT/STOP are UNIT_SPELLCAST events; BEGIN is
  TRADE_SKILL_CRAFT_BEGIN; RESULT is TRADE_SKILL_ITEM_CRAFTED_RESULT; BAG is
  BAG_UPDATE_DELAYED. Timeline entries are numbered in arrival order.
- `EVENT(n)` gives the actual argument count, including trailing nils. Argument
  types and safely readable numeric values are shown up to eight arguments;
  additional arguments are explicitly marked ARGS TRUNCATED. Arbitrary strings
  are represented by their type; unit identity is only player/other. Cast GUIDs
  use local cN aliases for correlation, never raw GUIDs. SENT's target is redacted;
  its cast GUID/spell slots are 3/4, rather than 2/3 used by the other cast events.
- For a result table, only itemID, quantity and numeric operationID are read;
  other fields are intentionally omitted. Missing/restricted fields are unknown
  or secret. Unexpected positional payloads retain their numeric/type structure,
  without silently reinterpreting them as the documented table.
- Counts describe unique observed successful cast identities, duplicate success
  events, and failed/interrupted identities with no success. A recipe lookup
  indicates GetRecipeInfo returned a table at summary time, not proof of selected
  recipe identity or a learned recipe. Starts, STOP and bags never count as success.
- At most 400 sanitized events and run-local identity aliases are retained.
  Dropped events are counted. The existing report's sixteen-note/four-hundred-byte
  contract is preserved: up to ten bounded timeline lines, with shown/omitted
  event counts and explicit TRUNCATED. No saved history, names, links, target text,
  arbitrary table contents or raw error strings enter the diagnostic report.

## Evidence and limitations

Source-grounded: Forever reference branch at
`bebcb6bf309cf41b41bd74f8ca651e6a105b2676`, generated
`UnitDocumentation.lua` and `TradeSkillUIDocumentation.lua`, declares SENT's
four arguments, START's optional castBarID, CRAFT_BEGIN(recipeSpellID), and
CRAFTED_RESULT(data table). These declarations establish expected shapes, not
native timing, delivery, selected-recipe mapping or batch cardinality.

Unit-tested: synthetic privacy/secret handling, trailing nils, SENT correlation,
result table and unexpected positional shapes, report/capture truncation,
registration failure reporting, and owned-frame event/script cleanup. Existing
probe summary tests remain. No real-client evidence was collected; event support,
actual completion counts, restricted payloads and cancellation ordering remain
inconclusive until compared with the owner's observations. No performance claims
or production credit authorization follow from this report. The rare, opt-in,
bounded listener needs no additional performance scope; it uses the existing Test
Lab lifecycle and owned-frame pool.
