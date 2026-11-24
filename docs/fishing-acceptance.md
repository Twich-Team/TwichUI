# Fishing owner acceptance (WoW Forever)

Automated and simulated checks do not certify native fishing interactions. Run this on the candidate build in a development client, in a safe fishing spot, with spare bag slots, a fishing pole, a few lures and your usual equipment. Keep automatic container opening set to **Queue**. Record the build/commit, client version, enabled addons and whether EllesmereUI/controller support is installed. Do not test consequential auctions, trades, selling or mail.

1. **Prepare and record.** Open TwichUI Settings → Fishing. Bind **Fishing: the next step**, **Open the next fishing container**, **Fishing Mode: on or off**, and **Reveal the interface (hold)** to your own keys/controller buttons. Note the original weapon/offhand/outfit and camera position. Open `/tui fish status` and the Journal to record initial totals.
2. **Optional service absent.** With Workshop disabled/unloaded, press the fishing key yourself through pole equip, lure application and cast. Reel with your own key/button when the bobber bites. Confirm immediate catch notification, correct icon/name/quantity and one attribution per loot item. Unavailable estimates must not stop fishing or become zero-valued catches.
3. **Lure and equipment.** Confirm the selected lure appears on the pole and its timer updates. End with `/tui fish stop`; verify your original equipment returns. Test an interrupted lure attempt without repeated automatic use. A pending restore must be visible; recover out of combat with `/tui fish restore`.
4. **Immersive view.** Confirm EllesmereUI’s cast bar and quest tracker fade (including quest-item buttons) and restore on reveal, stop, combat and recovery; chat stays visible. Inspect repeated fish and pearl cards on bright/dark scenery at your usual UI scale. Enter Fishing Mode. Check cast bar, transparent catch/treasure lists, notifications and duration/counts. Chat stays visible; EllesmereUI fading follows the selected settings. Minimap and its decorations disappear and return on exit. Hold/release Reveal with keyboard and controller. Exit/re-enter mode, then use `/tui fish recover`; camera and faded UI must return without duplicate bindings or stuck frames.
5. **Combat/recovery.** At a safe opportunity, enter combat while Fishing Mode is active, then leave combat. Check camera/UI/minimap recovery and equipment restore/pending state. Confirm casting/reeling/equipping still require your own permitted input. Do not force an unsafe combat test merely to finish the checklist.
6. **Container provenance.** Catch multiple clams in a named zone/session. Open some with your own container key; compare actual bag contents against Journal Treasures and the original session. Open another after `/tui fish stop`, in a different zone and after `/reload`. Contents must stay with the original fishing session/location. A repeated refresh/reopen must not increase counts twice.
7. **Partial/failed containers.** Leave loot in a clam, close the window and finish it later. Attempt opening with insufficient bag space/locked loot where practical. Confirm only items actually taken are recorded. Opened shells have no provisional value. An ambiguous partial lot may show an incomplete known subtotal with its shell estimates withheld; it must never be valued as both intact shells and confirmed contents.
8. **Prices.** Load/enable Workshop explicitly, select the intended market and inspect one known fish/pearl against Workshop's selected valuation method. Enable Fishing estimates and compare quantity × unit value, session total, vendor value and hourly value. Test each method and provisional-container switch. Listing estimates must never be called realized income. Purchase expenses/net income remain unavailable without historical evidence.
9. **Journal and refresh.** Visit Overview, Sessions (including the ended session), Collections, Locations, Treasures and the completion summary. Confirm direct catches versus opened contents, exact/unknown/earlier/overflow location distinctions and separate provisional values. Keep the Journal/HUD open while existing Market data finishes loading or a normal data generation arrives. Values must refresh without another catch; notifications must never wait for prices. Disable Workshop again and confirm fishing remains usable.
10. **Timers and copy evidence.** Watch **Time fishing** advance during a live line and freeze between casts. Leave Fishing Mode: the HUD disappears but the session remains open, as stated by the command. Use `/tui fish stop`: note the exact final session duration; wait, reopen the Journal and reload, and confirm it stays fixed. Test idle end, combat interruption and a short reload without a phantom active line. Then copy evidence: If the development-only `TwichUI_TestLab` is installed, open the data bar → **Test Lab (development)...** or `/tuilab`, select only **Fishing**, then **Run**. Use **Copy report**, press Ctrl+C and paste it below. The Lab reports APIs, restoration/presentation capabilities and economic availability/cache/queue facts; it never casts, equips or opens a clam for you. Add any client Lua/blocked-action errors, exact failed step and expected/observed behavior. Optional `/tui perf` captures can measure actual valuation callbacks.

Pasteable acceptance record:

```text
Fishing candidate commit:
WoW Forever version:
EllesmereUI/controller addons:
Steps passed (1–10):
Steps failed/not run and reason:
Original session/zone; late/partial clam observations:
Workshop market/method; fish/pearl unit × quantity and shown total:
Camera/minimap/combat/equipment recovery:
Lua/blocked-action errors (exact text):
Fishing Test Lab report:
```

A checked box or synthetic report is not proof of native gameplay. Keep the final mainline PR open for owner acceptance while critical interactions above remain unverified. Merging code does not authorize a release workflow or publication.
