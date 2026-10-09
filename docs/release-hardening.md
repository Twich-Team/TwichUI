# Release hardening: support scope, layout, resource use

What this records: what TwichUI is meant to run on, how its windows are fitted to the screen, what keeps running while
a feature is off, how much each collection can grow, and how to measure and test the rest in the game. **Nothing in
the "tested in the game" columns has been run yet.** The offline tests (`tests/run.sh`) check TwichUI's own logic with
a simulated game; they do not show how anything looks, whether a click is blocked in combat, or how fast it is.

Client reference: `../wow-ui-source/` branch `forever`, build 1.60.1.70170. The `.toc` says `## Interface: 16001`, which
is what that build and the test harness report.

## 1. Support scope

| | Status |
|---|---|
| WoW: Forever (interface 16001) | **Intended**; not yet tested in the game for this release |
| Any other WoW client (Retail, Classic, Era, other Forever builds) | **Unsupported**. APIs may exist there, but nothing was checked |
| TwichUI alone, no other addon | **Intended**; must be tested (checklist A) |
| With EllesmereUI | **Intended**; skins reach TwichUI's own windows and the four third-party skins only when EllesmereUI's third-party skin option is on. Without it, or before it hands over its toolkit, TwichUI uses its plain warm look |
| Auctionator, WhatsTraining, Forever Dungeon Journal, Attune (skins) | **Intended** when installed and EllesmereUI is present. Each is optional |
| EllesmereUI Bags (upgrade mark painter) | **Intended**; registers once when `EUI_Bags` exists |
| A data bar that lists LibDataBroker launchers (Mage Travel/Conjuring, Chronicle launcher) | **Intended**; no launcher appears without one |
| Leatrix Plus | Only read, to say in a tooltip that it does the same job |
| Navigation (opt-in, off by default) | **Intended**, on one continent: walking (a straight line, shown as a minimum) and flights between the flight points a flight master's map has listed as the character's (none until one has been opened on that continent). Boats, zeppelins, portals, the tram, lifts and the Hearthstone are **not planned**; dungeons and raids are not covered. Needs Blizzard's world map and its filter menu |
| Other addons, other skins, other bag addons | **Not claimed**. No integration, no promise |

Three states are kept apart, in the settings and in `/tui diagnostics` ("Environment"): *installed*
(`R.Setups.AddonState`), *loaded* (`C_AddOns.IsAddOnLoaded`) and *usable* (its API or toolkit is actually there).
An installed-but-not-loaded addon is picked up on its `ADDON_LOADED`, or, for EllesmereUI's toolkit, at login. A missing
or unusable one is reported in neutral words and never stops another feature. Saved integration choices (for example
the skin switches) are kept whatever is installed.

### Character-dependent behaviour
| Feature | Depends on | Notes |
|---|---|---|
| Mage Travel, Mage Conjuring | Mage class | Not offered to other classes |
| Gear hints | class, talent tree, level | No hint when the data isn't there; weights are rough guidance |
| New training card | class, level, bundled data | Shows nothing when there is nothing new |
| Food and Drink | bags, level, (Mage) conjured items | Secure buttons: changes wait for combat to end |
| Chronicle | per character | Never shared or backed up with configuration |
| Navigation | faction, flight points found, run speed | Flight routes and times it learns are account-wide (`TwichUINavigationDB`), never shared or backed up |

### Known external limitations (not TwichUI defects)
- EllesmereUI's target-debuff tracked-bar refresh was reported during testing. Nothing in TwichUI touches those bars,
  so it is recorded as an external observation. No workaround was added. If it is ever reproduced with TwichUI
  disabled, it is not ours; if it only appears with TwichUI enabled, bisect by module and reopen.
- Combat lockdown, protected-frame errors and taint cannot be judged offline.
- Sizes shown in "Addon data" are estimates; the client controls when SavedVariables load.

## 2. Layout

### What changed
- **Windows fit the screen** (`R.FitScale`, `R.FitToScreen` in `Core.lua`). Every TwichUI window is a fixed size.
  When the game window or UI scale leaves less than the window's size plus a 24-unit margin, the window's scale is
  lowered just enough (never below 0.6, never above 1). The scale is always computed from the window's own size, so it
  never compounds, and it returns to full size when there is room. It runs when the window opens (the Welcome
  dialog after its text is measured). Windows: Share/Backups, addon list, backup export/import, saved data,
  sending options, Edit Mode text, Chronicle (and its note editor), Troubleshooting, Addon data, Welcome.
- **Cards and movers are not scaled or moved.** They are laid out in `UIParent` units from their saved offsets and are
  clamped to the screen by the client for display; the saved offset is never rewritten because a window got small.
  Recovery stays as it was: Edit Mode, right-click the outline to put it back. (`Position()` already rejects
  non-numbers, NaN and offsets beyond ±10000; tests cover the Food and Drink, Training and Friend login cases.)
- **Cut-short rows can be read in full** (`R.Interact.TipTruncated`): backup names (typed by you or imported) and
  addon titles from another player's list show the whole text in a tooltip, only when the label is actually cut.
  Confirmation dialogs already quote the full name.
- The backup-name hint is kept inside its box instead of spilling past it in a wider font or language.

### Surfaces and risks (to check in the game)
| Surface | Risk | Handling |
|---|---|---|
| Addon data (900×580), Share/Backups (720×580), Troubleshooting (700×520), Chronicle (540×580) | Larger than a small window | `FitToScreen` |
| Welcome dialog | Height follows its text; long text, large fonts, other languages | Re-measured at each opening, then fitted |
| Zone, training, friend, Welcome Back cards | Long place/spell/friend names | Deliberately cut with "..." (the Chronicle holds the full place name); cards are not interactive |
| Training card, two columns (≈206 units per name) | Long spell names cut | Same; one column when there are few spells |
| Backup rows, addon list rows | Long names | Tooltip with the full text |
| Diagnostic report | Long report | Scrolls; the whole text is one edit box that selects and copies; typing puts the text back |
| Blizzard Options pages | None of ours | TwichUI does not skin Blizzard's panel |
| Tooltips | Edge overflow | The game's `GameTooltip` keeps itself on screen |
| Movers (Edit Mode) | Off-screen saved offsets | Client clamp + right-click reset |

### Screen matrix to run (record the real numbers)
Use `/run print(GetPhysicalScreenSize(), UIParent:GetWidth(), UIParent:GetHeight(), UIParent:GetEffectiveScale())`
and note the output with each screenshot.
1. Default setup.
2. Smallest window the client allows (≈800×600) at the default UI scale.
3. A wide display (21:9 or 32:9).
4. Lowest and highest UI scale on the default window.

## 3. Resource use

### Inventory (static analysis, 2026)
| Work | Trigger | Runs while off? | Bound |
|---|---|---|---|
| Event bus (`Core.lua`) | one frame; events registered only while a listener exists | no | listeners unregister themselves |
| Chronicle, Arrival, Training, Friend login, Welcome Back, Welcome, Food and Drink, QoL | `Want(event, …)` on `Refresh()` | **no**: unregistered when off | – |
| Food and Drink bag scan | `BAG_UPDATE_DELAYED`, item/spell data events | no | one timer for any burst; deferred in combat |
| Bag upgrade marks | hook on bag redraw | was: one item lookup per slot per redraw even when off. **Now:** only hides leftover marks | per open bag |
| Gear cache | equipment/talent events | cheap wipe only | 300 items, then cleared |
| Group check | `GROUP_ROSTER_UPDATE` | was: a 3-second timer per roster growth even when off. **Now:** none | one pending timer |
| Share/backup packing, Addon data counting | `OnUpdate` while a job exists | no | 12 ms per frame; handler removed when the queue empties |
| Sender watchdog | 5-second ticker while a send is in progress | no | cancels itself when the send ends |
| Auctionator/Attune/WhatsTraining/Dungeon Journal skins | one hook each, installed once | module switch needs a reload | skinned frames remembered once |
| Diagnostics | off until asked | no | 200 records, 10 errors, rate limit, stops by itself after 15 minutes; Clear empties them |
| Notification coordinator | no `OnUpdate`; timers per notice | idle when empty | queue of 6; dropped notices are released |
| Navigation route | 0.5-second ticker while a route is active; planning every 10 s while walking (a few dozen flight points, costs cached) | **no**: no ticker, events or map drawing when off or with no route | the ticker is cancelled when the route ends |
| Navigation arrow | `OnUpdate` at 20 updates a second while it is shown | no | handler removed when hidden; no tables made per update |
| Navigation map drawing | world map open, on zoom/map change, and every ≥ 1 s while you move ≥ 15 yards | no: data provider removed when off | 500 dots, 300 dashes, 24 marks |
| Navigation flight learning | flight master map opened, take-off and landing events, a watch on `TakeTaxiNode` (installed once; checks the setting) | no events when off | see Collections |

No permanent `OnUpdate`, no recurring ticker and no polling loop for an optional integration was found.
`ADDON_LOADED` listeners that remain (EllesmereUI, skin status, Settings) compare a name and return.

### Collections that grow
| Collection | Bound | Notes |
|---|---|---|
| Notification queue | 6 | oldest of the lowest priority is released |
| Diagnostic trace | 200 records, 10 errors, 64 labels per kind | `Clear` wipes records, errors and labels |
| Lifecycle reason codes | 32 kinds | counts only |
| Navigation learned flight data | 3000 routes, 1000 flight times, 24 stops per route, 400 flight points per character, 60 characters | oldest first; Forget (Navigation options) empties it |
| Navigation result counts | 32 kinds | counts only, this session |
| Gear judgement cache | 300 | cleared when full |
| Chronicle | 500 entries per character | when full, the oldest automatic zone entry goes first, then other automatic ones; your notes and the first "begun" line are kept |
| Imported backups | 20 points, 32 MiB total | |
| Received setups | one per sender, stored only after you accept an offer; a newer one from the same sender replaces it | no total limit; deletable in Received setups |
| **Backups you create yourself** | **none** | **needs your decision, below** |

**For approval, not changed:** backups made with *Create backup* have no count or size limit; only imports are capped
(20 points, 32 MiB). Each is a full copy of the chosen addons' settings (the Addon data / Saved data lists show the
sizes). Every backup is also loaded with the rest of TwichUI's saved variables at login. Options: (a) leave it and
show the total next to the list; (b) warn, but never delete, past a total size; (c) refuse a new backup past the same
cap the imports use and ask you to delete one. Nothing is deleted without you in any option. Pick one if you want it.

## 4. Measuring

### What exists
- `C_AddOnProfiler` (documented in the Forever API docs): `IsEnabled()`, `GetAddOnMetric(name, metric)` with
  `Enum.AddOnProfilerMetric.RecentAverageTime | SessionAverageTime | PeakTime | CountTimeOver1Ms…`. These are **CPU
  time per frame** for the addon named `!!!TwichUI`, not memory and not FPS.
- `UpdateAddOnMemoryUsage()` / `GetAddOnMemoryUsage("!!!TwichUI")`: memory, in kilobytes, which includes garbage not yet
  collected; compare after several seconds, not once.
- `/tui diagnostics`: lifecycle counts, notification statistics, tracked events per module.

None of these is run by TwichUI; nothing was added to normal operation.

### Procedure (per scenario)
Record: client build (`/run print(GetBuildInfo())`), TwichUI version, which modules are on, which integrations are
loaded, and whether the profiler is enabled (`/run print(C_AddOnProfiler.IsEnabled())`). Run a scenario for a fixed
time, then:

```
/run local m=Enum.AddOnProfilerMetric; for _,k in ipairs({"RecentAverageTime","SessionAverageTime","PeakTime","CountTimeOver1Ms","CountTimeOver5Ms"}) do print(k, C_AddOnProfiler.GetAddOnMetric("!!!TwichUI", m[k])) end
/run UpdateAddOnMemoryUsage(); print(GetAddOnMemoryUsage("!!!TwichUI"))
```
Reload between scenarios so `SessionAverageTime` starts clean, and repeat each at least three times. Instrumentation
overhead: the profiler is the game's own and adds nothing to TwichUI code; the memory call itself allocates a little.

| # | Scenario | Do | Compare |
|---|---|---|---|
| 1 | Idle, normal features | 5 min standing in a town | Session average; memory at 1 and 5 min |
| 2 | Idle, optional features off | Same with Food and Drink, cards, Chronicle auto-entries, group check off | Should be at or below #1 |
| 3 | Combat | 5 min of normal play with Food and Drink on | Peak, count over 5 ms |
| 4 | Loading screens | 10 hearth/flight/dungeon transitions | Peak time around transitions; no repeated cards |
| 5 | Settings | Open every TwichUI page, 3 times | Peak while opening; memory before/after |
| 6 | Notification burst | Preview sequence, 3 times | Peak; queue stays ≤ 6 (`/tui diagnostics`) |
| 7 | Preview start/clear | 20 times each preview | Memory should plateau, not rise per cycle |
| 8 | Module toggle | Toggle each of Zone card, Friend login, Welcome Back, Food and Drink, Chronicle zones 20 times | One copy of each; memory plateau; `/tui diagnostics` shows one set of events |
| 9 | Bags | Open bags, move items, with upgrade marks off, then on | Off should cost less than on |

A change in one number is not evidence of a change in another (CPU time, memory and how smooth it feels are different
things). Report before/after only from the same scenario, same character, same modules, same screen.

### Findings so far (static; hypotheses until measured)
- **Fixed, behaviour unchanged:** bag redraw hook did a per-slot item lookup while upgrade marks were off (the default).
  Test: `tests/test_gear.lua` (fails on the old code, passes now). Expected effect: less CPU on bag updates. Not
  measured.
- **Fixed:** the group check started a timer on roster growth when switched off. Test: `tests/test_release.lua`.
- **Hypothesis, not changed:** several `ADDON_LOADED`/`PLAYER_LOGIN` listeners stay registered after they have done their
  work. They run once per addon load or once per login; measured cost would be negligible.
- **No leak found by reading** in diagnostics, notification queue, job runners or hooks. "No leak" is not claimed:
  only a memory plateau in scenarios 7 and 8 shows that.

## 5. Manual acceptance checklist (in the game)

Turn on **Display Lua Errors** in the game's options first. After each step check for Lua errors and
"action blocked" messages. Everything below is **untested**.

**A. TwichUI alone.** Disable every other addon. Log in. *Expect:* no errors; options open from Esc > Options > AddOns
> TwichUI; skin rows say "Not installed"; `/tui diagnostics` Environment lists EllesmereUI as not installed and
"EllesmereUI integration: not active".

**B. With EllesmereUI.** Enable it and its third-party skins. *Expect:* TwichUI's windows use the EllesmereUI look; the
Welcome dialog keeps its warm umber/bronze look; the report says skin toolkit received = yes. Turn the third-party skin
off and reload: plain look, no errors.

**C. Optional dependencies absent / present but not yet loaded.** Remove Auctionator, then install it (load on demand
or after login). *Expect:* skin status goes "Not installed" → loads → skinned on the next Auction House visit with no
error and without a reload for the status text.

**D. Characters.** A Mage (Travel/Conjure appear on a data bar), a non-Mage (they don't), a level 1 and a level 60
character (training card, Food and Drink), two specs (upgrade hints change with the tree).

**E. Fresh and migrated configuration.** Fresh: Welcome opens once. Migrated from the previous release's saved
variables: no Welcome, settings intact, positions kept.

**F. Windows at each screen in section 2.** Open every window: close box and bottom buttons reachable, nothing clipped,
text readable, window back to full size when you return to the large setup. Check each at the smallest window.

**G. Long text.** Name a backup with 80 characters: the row is cut with "...", hovering shows the whole name, Restore and
Delete confirmations show it. Import a recommended-addons list with a very long title: same. Select all in the
Troubleshooting report (click in it, Ctrl+A, Ctrl+C): the whole report copies; the scroll bar reaches the last line.

**H. Movers and resizing.** In Edit Mode move the Food and Drink buttons, Welcome Back, Training and Friend login
outlines. Make the game window smaller, then restore it. *Expect:* each stays on screen while small and returns to
exactly where you put it; right-click on an outline resets it. Reopen the settings: nothing moved.

**I. Edges.** Place cards at each screen edge and preview them; hover rows near the edges so tooltips open at the
border: nothing is cut off or unreachable.

**J. Repeated previews and toggles.** Scenario 7 and 8 above. *Expect:* one card, one sound, one entry per event after
20 toggles.

**K. Profiling.** Scenarios 1–9 with the numbers written down.

**L. Reload and profile changes.** `/reload`, then switch an EllesmereUI profile. *Expect:* positions, switches and
backups intact; no card or tooltip stuck on screen; Welcome does not return.

**M. Errors and blocked actions.** Ten minutes of play including combat with Food and Drink on, bag changes in combat,
a flight path and a dungeon entrance: no Lua errors, no "action blocked", `/tui diagnostics` shows no `init-failed`.
