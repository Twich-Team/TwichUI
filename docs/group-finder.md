# Group Finder

TwichUI's five-player dungeon browser uses Forever's native listings. **Find a group** shows group openings; **Recruit players** shows the roles a solo player advertised. Listing creation, editing, delisting and Who remain in the native finder. The **Blizzard Browse** button returns to it. The existing opt-in **Show zones in the Group Finder** feature still owns only Blizzard's row labels.

## Verified source contract

Source inspection used Gethe's `wow-ui-source` `forever` checkout at `bebcb6bf309cf41b41bd74f8ca651e6a105b2676` (Forever `1.60.1.70938`). This is source-backed behavior, **not real-client-tested**. Simulator FrameXML is the older pinned `1.60.1.70532` source.

| Contract | Source and implication |
| --- | --- |
| Multi-activity search | `Blizzard_GroupFinder_VanillaStyle/Blizzard_LFGVanilla_Browse.lua`, `LFGBrowse_DoSearch`, calls `C_LFGList.Search(categoryID, 0, 0, nil, false, nil, activityIDs)`. The generated API labels Search restricted. A user click/key initiates a query; timers never initiate one. Actual server coverage for multiple activities remains unverified. |
| Result families | Native Browse separates solo and groups using `numMembers <= 1`. Result info supplies activity IDs, leader, member count, age, social counts and a never-secret `partyGUID`. |
| Openings versus advertised roles | Group counts use `TANK_REMAINING`, `HEALER_REMAINING`, `DAMAGER_REMAINING`. Solo player info exposes `lfgRoles.tank`, `.healer`, `.dps`. These answer different questions and are filtered separately. |
| Player detail | Generated `LfgSearchResultPlayerInfo` supplies nullable name, level, area and spec; class, assigned role, advertised roles, leader flag. Missing or restricted values cannot be assumed usable. |
| Location | `qol/GroupFinderZones.lua` reads leader info first, then member 1 only if that member is the leader. `Nearby` compares public reported zone names against the player's current zone/subzone names. Matching areas do not establish the same layer or phase. |
| Results and events | `GetSearchResults()` returns total count and IDs. `LFG_LIST_SEARCH_RESULTS_RECEIVED` has no query ID; `LFG_LIST_SEARCH_FAILED` has an optional reason; `LFG_LIST_SEARCH_RESULT_UPDATED` provides result ID. Thus server events cannot prove ownership when another addon makes a concurrent request. |
| Contact | Native Browse uses `ChatFrameUtil.SendTell(leaderName)` to open a whisper. A click must re-read the listing and match its identity before any contact. Invite additionally needs current party authority and space. |

Dungeon choices are discovered from available category/activity data rather than a hard-coded list of dungeon IDs. Suggested activity-level ranges, where present, are distinct from recruit character-level bounds. Unavailable saved activity IDs cannot force an invalid query.

### Melee and ranged coverage

The exported `specName` field exists and is nullable, but **no live solo listings were available** in this session. Its usable, public coverage and Forever-specific specialization semantics have not been established. Recruit damage style remains **Unknown**; there is no class-based melee/ranged guess, particularly for hybrids. Class filters remain usable. Group openings remain generic DPS. A future refinement needs actual coverage evidence before presenting an inferred specialization as fact.

## Read-only owner probe

This is optional live acceptance. Run the snippet in a trusted developer Lua console before and after clicking the native **Refresh**, then after TwichUI **Refresh**, and after switching views. It performs no search and prints only counts and field coverage, with no player names, zone names or GUIDs. Do not paste it into public chat. The WoW chat macro length limit is too short for this full snippet.

```lua
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value, other = pcall(fn, ...)
    if not ok then return nil end
    return Plain(value), Plain(other)
end
local total, ids = Read(C_LFGList.GetSearchResults)
local stats = { results=0, solo=0, multi=0, leader=0, level=0, area=0, spec=0, roles=0, guid=0 }
if type(ids) == "table" then
    for _, rawID in ipairs(ids) do
        local id = Plain(rawID)
        if type(id) == "number" then
            local info = Read(C_LFGList.GetSearchResultInfo, id)
            if type(info) == "table" then
                stats.results = stats.results + 1
                local n = Plain(info.numMembers)
                local acts = Plain(info.activityIDs)
                if type(acts) == "table" and #acts > 1 then stats.multi = stats.multi + 1 end
                if type(Plain(info.partyGUID)) == "string" then stats.guid = stats.guid + 1 end
                if type(n) == "number" and n <= 1 then
                    stats.solo = stats.solo + 1
                    local p = Read(C_LFGList.GetSearchResultPlayerInfo, id, 1)
                    if type(p) == "table" then
                        for _, item in ipairs({ {"leader","name"}, {"level","level"}, {"area","areaName"}, {"spec","specName"}, {"roles","lfgRoles"} }) do
                            local v = Plain(p[item[2]])
                            if v ~= nil then stats[item[1]] = stats[item[1]] + 1 end
                        end
                    end
                end
            end
        end
    end
end
for _, key in ipairs({"results","solo","multi","leader","level","area","spec","roles","guid"}) do
    print("TwichUI LFG probe", key, stats[key])
end
```

Also compare one-dungeon and two-dungeon queries, including a Forever-added dungeon. If coverage is truncated or query-specific, record which query produced it. Test a second LFG addon initiating a search while TwichUI is open; no-query-ID events leave this an inherent attribution limit. Do not infer that a success event belongs to TwichUI merely because TwichUI is visible.

## Simulator evidence

Run `bash tools/simlab/run.sh groupfinder` after activating the prepared environment. The runner stages the actual addon into the disposable lab and produces `groups.png`, `players.png`, and `small.png`, with per-pose stdout/stderr logs. The fixture supplies native-shaped C_LFGList data for the four mockup groups, four healer recruits, two selected dungeons, and a four-player party missing a healer. It drives real Refresh controls and delivers synthetic search success/failure events.

These are **simulator-tested handler/state checks**, not hardware or server evidence. The fixture does not send a whisper or invite. It checks query deduplication, local leader-name search, filtered empty state, last-good snapshots on failed refresh, recovery, recruit minimum levels, multi-dungeon detail, dungeon/class/custom-level popup construction and named preset save/load/remove through their real controls. It also verifies action notices remain visible alongside refresh age in the footer. The group/player captures enlarge the already constructed window to 1.48 scale to match the references’ image proportions; the small pose captures at 0.75 scale. The normal window is first constructed at its default fitted scale in every pose. Offline tests cover additional safety boundaries.

Screenshots are structural comparisons only: the simulator falls back from addon serif/sans fonts to its game font. This environment has no licensed game asset installation. The browser packages the original Blackrock Depths and Scholomance illustrations, with an existing painted entrance fallback for other dungeons, and uses packaged TwichUI crest, class shields, role icons and check artwork. Native font metrics, localized wrapping, texture fidelity and actual pointer/keyboard reachability remain **not tested**.

## Intentional visual differences

The shared frame keeps the references’ landscape proportions, roughly 64/36 content split, four-row rhythm, two filter rows, teal selection, amber rail and primary action. It uses TwichUI's production crest, class shields and role artwork rather than duplicating the mockup's crest, priest sun and green healer cross. Blackrock Depths and Scholomance receive original framed doorway artwork; other dungeons use the existing painted entrance. Source artwork and packaging details are recorded in [the asset note](../assets/groupfinder-art.md).

The implementation uses the addon's existing CraftLook material sheets and Spectral/Alegreya fonts. Simulator captures substitute a game font, so they cannot establish exact serif appearance or localized text fit. Menus provide the additional filters and arbitrary listed dungeons without expanding the mockups’ main surface.

## Native acceptance

1. From a clean login with native finder unloaded, open Group Finder, enter TwichUI, close with Escape and reopen. Return with **Blizzard Browse**. Confirm creation, edit, delist and Who still work in the native view, and the opt-in zone setting continues to affect Blizzard rows.
2. Click Refresh with two dungeons selected (including a Forever-added dungeon), compare coverage with native Browse, and verify no search occurs from typing, tab changes or the footer age timer. Retry after a failed search; last-good rows should remain but invalid entries must not be actionable.
3. Verify groups filter remaining role slots and recruits filter advertised roles. Change party roles/leadership and fill the party; Fill missing roles and Invite must respond. Check unknown party roles leave manual filtering available.
4. Select a recruit, delist or replace that listing, and attempt Whisper/Invite. Confirm stale or recycled results cannot target a different player. Whisper opens the game's input; Invite requires a deliberate click and current authority. Check session contact marks only appear for identities the client can establish.
5. Save named presets in both modes, reload, load/remove them, and test a preset containing an unavailable activity. Verify custom player levels remain separate from suggested dungeon levels.
6. Check scrolling, selected-row retention, long/localized names, the two filter rows, dropdown boundaries and buttons at default and smaller supported UI scales. Compare both modes to the supplied references using the real fonts and assets.
7. Refresh in another LFG addon and native Browse during an in-flight TwichUI query. Confirm shared-result changes make stale selections safe; record that no server query ID exists.
