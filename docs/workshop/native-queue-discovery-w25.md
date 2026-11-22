# W25: add a native profession selection to the queue

Discovery only, 2026-11-22, against addon base `cf188dd`. No button, hooks,
settings or runtime behavior changed. W25 remains a product candidate; the
[roadmap](../product-roadmap.md#workshop-crafting-experience--new-owner-requests-november-22-2026)
does not contain an approved implementation spec.

## Evidence and missing native facts

**Repository-verified / unit-tested:** [Observe.lua](../../TwichUI_Workshop/Observe.lua)
reads the player's own profession through `C_TradeSkillUI.GetBaseProfessionInfo`,
`GetRecipeInfo`, `GetRecipeSchematic`, and filtered/all recipe lists. It refuses
combat, changing data sources, linked/guild/NPC views, and unknown ownership.
It accepts learned ordinary recipes, excluding recraft/dummy/gathering/salvage
entries. `Observe.Fill` reuses the existing material parser; unsupported materials
remain explicitly unknown. These APIs enumerate/read recipes; they do **not**
identify the native currently selected recipe or requested craft count.

`Observe.lua` attributes its API choices to prior Forever generated documentation
and native code inspection. That is **historical documented evidence**, not a
fresh source verification. The expected read-only `../wow-ui-source` and
`../reference_addons` trees are absent in this workspace. No client or simulator
was available. Retail frame names, schematic widget methods, selection callbacks
and quantity accessors must not be substituted as Forever facts.

| Required native fact | Status / consequence |
| --- | --- |
| Profession addon name, root, detail pane and safe unused button space | Unknown; no concrete frame anchor approved |
| Selected recipe accessor and selection-change notification | Unknown; cannot use the first recipe in a filtered list or last remembered recipe |
| Quantity accessor, meaning, bounds, Create All and blank-field behavior | Unknown; output units must not be confused with craft operations |
| Load/show/hide/close ordering and protection/taint of candidate anchor | Unknown; `TRADE_SKILL_SHOW` is an existing addon load trigger, not proof of a safe attachment point |

## Smallest proposed implementation after verification

Recommend **one craft per click**, visibly described as such. This matches
`Session.Add(rec)` exactly and avoids an unverified native quantity dependency.
The existing Workshop controls can change the number afterwards. Owner review
of this quantity choice and native placement remains open. If native quantity is
later required, validate an integer number of operations in `1..W.MAX_CRAFTS`
(currently 999), show the count before the click, and extend the Session boundary
to make one atomic `Queue.Add(rec, count)` call. Do not add one and then change
its count in a second save, infer a count from bags, or silently clamp it.

The future adapter should resolve/revalidate the native selection on the player's
click, require a fresh own-profession learned recipe record using the existing
Observe eligibility rules, then call `Session.Add`. Session fills the recipe,
uses `Queue.Add(rec, 1)`, bumps Strategy, and sets the existing success/refusal
note. Queue owns persistence rollback, held/newer-data refusal, the 30-recipe
limit, and duplicate rejection. An existing recipe should say “Already queued”;
do not silently increase it or implement a second queue. Missing reagent data
can retain the existing unresolved-recipe behavior, visibly labeled.

Use one Workshop-owned control attached only to a **source/client-verified**
nonprotected native location; do not move/reparent native controls or replace
native scripts. Create/attach/reanchor outside combat only. Reuse
`WorkshopLauncher.Load` and `W.Active()` consent/suspension semantics: the
existing launcher loads an enabled Workshop on `TRADE_SKILL_SHOW` without opening
its window. Disabled Workshop must create no native integration; unloaded/missing
native frames must be a no-op until the verified load/show point. On close or
data-source change discard selection state and hide the owned control. On
disable/profile change cancel owned work and make any retained hook inert;
reload must not duplicate controls/listeners. Combat must refuse the action at
the handler boundary even if presentation updates must wait for combat to end.
`Session.Add` and `Queue.Add` do not themselves establish native ownership,
experimental consent, or a combat guard; the adapter must enforce these checks.

## Exact owner evidence to collect

1. In a disposable development Forever profile record `/dump GetBuildInfo()`
   and addon revision. Supply the matching read-only UI source revision with
   generated TradeSkill documentation, profession XML/Lua and load manifest;
   do not substitute another client branch.
2. Open an own profession. With Blizzard's frame stack tool (`/fstack`, if
   installed), hover the recipe details, native create controls and quantity
   field; capture root/parent names and free space at normal/narrow UI scale.
   Close and reopen, change profession, and inspect an unlearned/linked view.
   Record which frame survives/rebuilds. If the tools are unavailable, obtain
   the source first; no guessed slash/API fallback is needed.
3. From that source identify the actual selected-recipe getter, its notification,
   and native requested-quantity getter. Read them in the client for recipe A,
   recipe B, cleared selection, quantities 1/3, Create All, insufficient reagents,
   and an output recipe making multiple items per operation. Record actual
   values and visible labels; use read-only inspection, never invoke Craft APIs.
4. Review the chosen anchor's protection and close/load lifecycle in source.
   A later implemented adapter needs owner checks with Workshop disabled,
   enabled but unloaded, already loaded, native addon absent, close/reopen,
   profile disable/re-enable, combat entry/exit, queue duplicate/full/held and
   save failure. This discovery does not claim those checks have run.

Verification: existing `test_workshop.lua` and `test_workshop_login.lua` pass
with Lua 5.1/bitop. These establish synthetic reader/queue and launcher behavior;
no native selection, placement, quantity, input, combat or taint acceptance is
claimed. Documentation-only work does not require a simulator or mutation run.
