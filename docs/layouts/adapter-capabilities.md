# Layout adapters: capability matrix

The evidence behind `architecture.md` §2–§4. Paths are relative to the repository, or to `../reference_addons/`
(EllesmereUI **9.6.8**; the author's installed copy is 9.6.6, so the reference is the newer one) and
`../wow-ui-source/` (`forever` branch, ca8368f2f). Phase 1 audit, 2026-10-26.

Labels: **S** = verified in source, **T** = covered by an existing offline test, **G** = still needs an in-game check,
**—** = not applicable or not offered. Nothing in this table has been checked in game. The phase blocks below are the evidence
as it was gathered; `architecture.md` is the current contract built on it.

**Phase 2 (2026-10-26).** Both adapters are built (`TwichUI_Layouts/AdapterTwichUI.lua`, `AdapterEllesmere.lua`) and
covered offline by `tests/test_layouts.lua` (EllesmereUI as a stand-in with the real functions' shape). What they use
is narrower than the tables below: TwichUI's restore is `PF.Switch` + `PF.Delete` (not `RS.ApplyOwnAtLoad` or
`TC.Undo`), EllesmereUI's is `SwitchProfile` + `DeleteProfile` (no `EllesmereUIDB` copy), and EllesmereUI blobs are
patched only at the allowlisted fields `minimap.coordsMode` and `minimap.coordsPosition`
(`EllesmereUIMinimap.lua` defaults, `EUI_Minimap_Info.lua` `GetCoordsModePos`/`MAP_POS_ANCHORS`,
`EUI_Minimap_Options.lua` "Show Coordinates"). `minimap.showCoords` exists in the defaults but nothing reads it in
9.6.8, so it is not managed. Still **G** for every row: nothing has run in game. `history.md` (the Phase 2 revisions, §11) has the details.

**Phase 3 (2026-10-26).** Read for the screen layer, in EllesmereUI 9.6.8 and the author's captured profile; none of
it run in game:

| What | Status | Evidence |
|---|---|---|
| Screen-edge link targets: 1-unit strips just outside each UIParent edge | S | `EUI_UnlockMode.lua` `EDGES` (334) |
| Link offsets are edge to edge (side LEFT: child right to target left; TOP: child bottom to target top; …); `edge` pins the other axis to a second screen edge | S, T | `EUI_UnlockMode_Positions.lua` `UM.ApplyAnchorPosition` (1055–1240), `edge` (1556–1567); `tests/test_layout_geometry.lua` §5–6 (the captured offsets come back exactly on the canvas) |
| A link on an element that places itself (`ownsPosition`, main chat) is inert; chat is placed from `chat.chatPosition` (BOTTOMLEFT) and sized from `chat.chatSize`, which EllesmereUI writes into Edit Mode's store itself | S, G | `EUI_UnlockMode_Positions.lua` 1065; `EUI_Chat_Position.lua` 118–175, `EUI_Chat_Init.lua` 1025–1055 |
| Minimap: `minimap.position` (CENTER), `minimap.mapSize` (square) | S | `EUI_Minimap_Apply.lua` 239–245 |
| Damage meter window: `dm.windows[1].position` (CENTER), `width`, `height` | S | `EUI_DamageMeters_State.lua` 259, 296–315 |
| Action bars: `barPositions[key]` `{point, relPoint, x, y}`; DataBars by `bars[i].id` (unlock key `EDB_<id>`) | S | `EUI_ActionBars_Layout.lua` 295; `EllesmereUIDataBars.lua` 2707 |
| Quest tracker: no stored position. Placement is Blizzard's Edit Mode | S | `EllesmereUIQuestTracker_Visibility.lua` header rule 3 |
| The import takes `fonts`, `customColors`, `darkMode`, `euiAccent`, `windowSkinLook`, `_migrations` and the merged `unlockLayout` from a payload; `chatBubbles`, `tooltipFixedPos` are inherited from the active profile | S | `ImportProfile` (3330–3470) |
| Imported layout links replace the base's for every imported module; a link to a screen edge travels with its child | S | `MergeImportedLayout` (586), `FilterLayoutToFolders` (461) |
| Text sizes scaled by the density: `chat.chatFontSize`, `chat.tabFontSize`, `dm.leftFontSize`, `dm.rightFontSize`, `dm.hdrFontSize`, `dm.barHeight` | S | read by `EllesmereUIChat`, `EllesmereUIDamageMeters` |
| TwichUI places: centre offsets in UIParent units (class bars, marker bar, navigation arrow, food and drink); Healer Watch from its own point; training and welcome-back cards from the top centre | S, T | `classbars/Config.lua` `CB.Position`, `markers/Bar.lua` 312, `nav/Arrow.lua` `PlaceOwn`, `modules/FoodDrinkUnlock.lua` 109, `healer/Display.lua` 421, `modules/Training.lua` `T.Position`, `modules/WelcomeBack.lua` `B.Position`; each re-placed on a profile refresh (`OnApply("layout"|"views")`) |

## `twichui` adapter

| Capability | Status | How | Evidence |
|---|---|---|---|
| Capture | S, T | Effective values per field from the explicit schema. Restore-point capture covers every setting key | `setup/TwichConfig.lua` `TC.Build` (2104), `Define` (1603); `setup/Restore.lua` `RS.CaptureOwn` (131), `RS.OWN_KEYS`; `tests/test_twichui_share.lua`, `tests/test_backup_own.lua` |
| Normalize | S, T | Field lookup by schema, never by path. Unknown fields are counted and ignored | `TC.CleanEntry` (2161) |
| Validate | S, T | `KIND` (bool, int range, enum, `AARRGGBB` colour, plain name), feature `DEFAULTS`/`LIMITS`, 1000-value bound, one bad value refuses its group | `TwichConfig.lua` `KIND`, `ENUM`, `TC.LIMITS` |
| Apply | S, T | `TC.Plan` → `TC.PlanKey` stale check → plain assignments → `Profiles.Refresh` | `TC.Plan` (2255), `TC.PlanKey` (2238), `TC.Apply` (2379) |
| Profile activation | S, T | New per-character profile: `PF.Duplicate` then switch. Refused in combat | `Profiles.lua` `PF.Duplicate` (354), `PF.Switch` (327), `Guard` (312) |
| Live refresh | S, T | `Switches.Sync` + `OnApply` phases (`look`, `layout`, `views`) + open settings window redraw | `Profiles.lua` `Apply` (271), `PF.Refresh` (305) |
| Reload requirements | S | Only switches marked `reload` (four skins, media, quiet login) | `Switches.lua` `W.NeedsReload` (284), `W.ReloadPending` (365) |
| Verify | S (partial) | Re-plan against live values: an empty plan means it matches. Positions read through each feature's getter | `TC.Plan`; e.g. `CB.Position` (`classbars/Config.lua` 334), `B.Position` (`markers/Bar.lua` 135) |
| Restore | S, T | One-slot Undo (`TC.Undo`) for an import. Full restore point at the next load (`RS.ApplyOwnAtLoad`) | `TC.Undo` (2480), `Restore.lua` `RS.ApplyOwnAtLoad` (356) |
| Editable presets (format 6) | S, T | A preset option's fragment is the same `groups` shape plus a `reset` list, read by the same `Normalize` (a fragment with only a reset list keeps its resets: fixed 2026-10-28); values checked by `TC.ValueOk` and `TC.CleanEntry`; a reset clears the stored value and is verified by the field's default (a default of `false` included: fixed 2026-10-28). `A.Summarize` / `A.FeatureLabel` give the words the wizard and workspace use | `AdapterTwichUI.lua` `A.Normalize`, `A.Expect`, `A.Plan`, `A.Summarize`; `Package.lua` `PresetSettingOk`; `tests/test_layout_presets.lua` §1, §3 |
| Known limitations | — | Positions are `place` in `TC.LOCAL`, so a layout needs its own `places` handling. Several positions are not centre offsets (`ui.healerWatch.point/x/y`, Edit Mode–placed cards, `ui.cozyBag`, `ui.partyPins.position`). List groups merge on share import but must replace on layout install. `PF.ACCOUNT` keys are never part of a profile | `TC.LOCAL` (50–89), `Profiles.lua` `PF.ACCOUNT` (32) |

## `ellesmereui` adapter

| Capability | Status | How | Evidence |
|---|---|---|---|
| Capture | S | `ExportProfile(name, nil, true, true, nil, true, true, false)` for author strings. A restore point is a copy of live `EllesmereUIDB` (single storage) | `EllesmereUI/EllesmereUI_Profiles.lua` `ExportProfile` (2164), `AutoSaveActiveProfile` no-op (3956); TwichUI `setup/Ellesmere.lua` `ES.Build` (141) |
| Normalize | S | `DecodeImportString` → `payload.data`; canonical module keys `EllesmereUI<suffix>`; TwichUI strips the excluded keys | `DecodeImportString` (2824), `AddonsToCanon`/`CanonToLocal` (106–125), `ADDON_DB_MAP` (39); TwichUI `ES.Payload`/`Sanitize` (267/243) |
| Validate | S, T | `payload.type == "full"`, version ≥ 3, `!EUI_` prefix, known modules only, size bounds (`ES.LIMITS`), `ST.CheckData` | `DecodeImportString`; TwichUI `ES.CleanEntry`, `Sanitize`; `tests/test_ellesmere_share.lua` |
| Apply | S | `ImportProfileSilent{ importString, profileName, cleanSlate, applyUIScale, autoAssignSpecs, disableAddons }`. Refused in combat. Never reloads | `ImportProfileSilent` (4957–5070) |
| Profile activation | S, G | The import activates the new profile unless the current spec is assigned to another one (`"spec_locked"`: stored, not active). `activeProfile` is **account-wide** | `ImportProfile` (3222; activation 3542–3590), `GetProfilesDB` (670), `EllesmereUI.toc` `SavedVariables: EllesmereUIDB` |
| Live refresh | S (not used) | `SwitchProfile` only re-points the DBs. EllesmereUI's own UI follows it with `RefreshAllAddons(true)`. The Wago-style `SetProfile` does not refresh. Imports always need a reload, so layouts never use live refresh | `SwitchProfile` (3852), `RefreshAllAddons` (1524), `EUI_Profiles_Options.lua:275-278`, `SetProfile` (4789) |
| Reload requirements | S | Always after an import ("Reload to finish importing"), after a UI scale change (read at login) and after enable/disable | `ImportReloadMessage` (1912), `EllesmereUI_Startup.lua` `ppUIScale` (65–102), `ImportProfileSilent` header |
| Verify | S, G | `GetActiveProfileName`, `GetProfileList`, `GetProfilesDB().profiles[target].addons[canon]` positions, `IsModuleAddonLoaded`, `C_AddOns` enable state, `EllesmereUIDB.ppUIScale` | `GetActiveProfileName` (3935), `IsModuleAddonLoaded` (695); TwichUI's `ES.Apply` snapshot verify pattern (`Snapshot` 402, `Verify` 419) |
| Restore | S, T (path) | The restore point puts the whole `EllesmereUIDB` back at EllesmereUI's `ADDON_LOADED` (TwichUI runs first). `ES.Blocked` allows it for `restore:` sources. Enable states go back through `C_AddOns` | TwichUI `setup/Setups.lua` `ApplyOne` (619), `ProcessOwner` (650), `Replace` (515); `setup/Ellesmere.lua` `ES.Blocked`; `tests/test_persist.lua` |
| Known limitations | — | (1) The import builds on the recipient's active profile, so modules missing from the payload are inherited. (2) The serializer writes numbers with `tostring`, so a decode→encode round trip is not exact ("a serializer round trip is not identity", 4969). (3) The `uiScale`, window-skin bundle, CDM spells and overrides in a string are applied when present ("presence is consent"), so TwichUI must strip what it does not manage. (4) `activeProfile` is account-wide. (5) The inner module blob shapes are internal and can change between EllesmereUI versions. Only registered position paths are patched, and each needs a version check. (6) The reference folder's `license.txt` (found in Phase 3) reserves all rights. TwichUI calls the API only and ships the author's own settings | `ImportProfile` 3330–3336, `Serializer` 243–281, `ImportProfileSilent` header |

### EllesmereUI facts that shape the contract

- **No AceDB.** Storage is `EllesmereUI.Lite.NewDB`. Every module's data lives in
  `EllesmereUIDB.profiles[active].addons[folder]`, and each child saved variable is wiped and vestigial
  (`EllesmereUI_Lite.lua` `EUILite.NewDB` 250).
- **Profile layout**: `EllesmereUIDB.profiles`, `.activeProfile`, `.profileOrder`, `.specProfiles` (`Profiles.lua`
  659–676).
- **Positions**: CENTER/CENTER offsets from UIParent's centre, in UIParent units (`EUI_UnlockMode_Positions.lua` 2200,
  `ConvertToCenterPos` 2208). Module records are `{point, relPoint, x, y}` (Minimap `m.position`,
  `EUI_Minimap_Lifecycle.lua` 524; Chat `cfg.toastPosition` and `cfg.chatPosition`, `EUI_Chat_Init.lua` 972 and 1033; Damage Meters `EUI_DamageMeters_State.lua` 308).
- **UI scale**: `EllesmereUIDB.ppUIScale`, applied with `UIParent:SetScale` at login. On a first install it is seeded
  from Blizzard's scale, clamped to 0.40–1.15. Pixel-perfect is `768 / physH` (`EllesmereUI_Startup.lua` 125–170,
  `EllesmereUI_PixelPerfect.lua` 55–68).
- **First-run picker**: suppressed for a session when `EllesmereUI._externalInstaller` is set before `PLAYER_LOGIN` +
  0.5 s. Set it with `RegisterExternalInstaller` (5080). Fail-open (`EllesmereUI_FirstInstall.lua` 556–590).
- **Keybinds and actions**: not in profile strings. Bindings are Blizzard's (`SetBinding` in
  `EUI_ActionBars_QuickKeybind.lua`). `profileKeybinds` is account-global and not exported (`Profiles.lua` 1598).
- **Chat history**: `EllesmereUIChatScrollDB`, per character (`EllesmereUIChat.toc`,
  `EllesmereUIChat_SessionHistory.lua` 27). Excluded.
- **Full-account export** (`ExportFullAccountData`, 2420) carries the whole store, including keybinds and
  click-cast. Never used by layouts.
- **Interactive import** (`ImportProfileInteractive`, 4843) opens EllesmereUI's own dialog flow. Not used, because
  TwichUI owns the review. Kept as a fallback idea if the silent path is ever withdrawn.

## Client APIs (Forever)

| API | Status | Evidence |
|---|---|---|
| `GetPhysicalScreenSize`, `GetScreenWidth`, `GetScreenHeight`, `GetScreenDPIScale`, `GetDefaultScale` | S (documented) | `Blizzard_APIDocumentationGenerated/ScreenDocumentation.lua` |
| `UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED` events | S (documented) | `UIManagerDocumentation.lua` 91, `VideoDocumentation.lua` 137 |
| `C_AddOns.EnableAddOn` / `DisableAddOn` / `GetAddOnEnableState` / `LoadAddOn` | S (used by TwichUI and EllesmereUI) | `SettingsLauncher.lua` `L.Load`; `ImportProfileSilent` |
| `C_EditMode.ConvertStringToLayoutInfo`, `SaveLayouts`, `SetActiveLayout` | S (documented), G (unused) | `EditModeManagerDocumentation.lua`. Not in the first release |
| `ReloadUI` from a button click | S (TwichUI already does it) | `setup/Setups.lua` `ST:Queue` |
| Saved variables written after `PLAYER_LOGOUT` | G | `docs/persistence.md`, "Newer data is never touched" |

## Other reference addons looked at

| Addon | Relevance | Use |
|---|---|---|
| NaowhForever (`Core/Onboarding/Setup.lua`, `Core/Profiles/Setups.lua`) | Prior art for Forever onboarding: a plan of on/off changes and reload, a one-slot `setupBefore` backup, addon enable states per character | Architecture reference only. License: all rights reserved (`LICENSE.md`). Nothing copied |
| EllesmereUI Chat, Quest Tracker, Minimap, Damage Meters | The only implementations of these surfaces in the reference set and the installed AddOns | Covered by the `ellesmereui` adapter |
| RXPGuides, WaypointUI, OpenMap, Attune | Not layout surfaces in the first release | None |

**Tooltip placement and friendly plates (2026-10-28).** Read in EllesmereUI 9.6.8 (`reference_addons`); the installed Forever copy is 9.6.9
and its tooltip, nameplate and profile files are byte-identical to these. Supersedes the "Cursor-following tooltip: not backed" row below.

| What | Status | Evidence |
|---|---|---|
| Follow mouse is the account-wide root key `EllesmereUIDB.tooltipAnchorCursor`; cursor position, offsets and growth direction are `tooltipCursorPosition`, `tooltipCursorOffsetX/Y`, `tooltipGrowthDirection` | S | `EUI_BlizzardSkin_TooltipAnchor.lua` 125–181 (`ApplyCursorAnchor`, `_repointTooltipAtCursor`), `EUI_BlizzardSkin_Options.lua` 335–405 |
| The options toggle is a direct write of that one key; there is no public narrow setter | S | `EUI_BlizzardSkin_Options.lua` 335–345 |
| The only public writer, `EllesmereUI.ApplyBlizzSkinGlobals`, sets every key of `BLIZZ_SKIN_GLOBAL_KEYS`, nil included, and runs inside the import | S | `EllesmereUI_Profiles.lua` 2043–2160, 3325 |
| Fixed mode is the baseline whenever the flag is off and `customTooltips ~= false`; the place is the per-profile `profiles[name].tooltipFixedPos = { centerX, centerY }` (centre offsets from UIParent's centre), seeded once from Blizzard's container if absent; the tooltip's nearest corner is pinned to a 280 × 165 box | S | `EUI_BlizzardSkin_TooltipAnchor.lua` 200–330, 400–420 |
| The import builds the new profile from the active one and takes only `fonts`, `darkMode`, `euiAccent`, `windowSkinLook`, `_migrations`, `unlockLayout` and the modules from a payload: `tooltipFixedPos` is inherited from the active profile, never carried | S | `EllesmereUI_Profiles.lua` `ImportProfile` 3338–3470 |
| `showFriendlyPlayers` (default true) is "Show EUI Friendly Player Nameplates": off, EllesmereUI relinquishes friendly player plates to Blizzard's own settings and, at load, stops writing the friendly CVars. `classColorFriendly` (default true) is "Class Colored Health Bar"; `friendlyNameOnly` defaults to true. All are fields of the nameplate module's profile blob | S | `GeneralPage_Options.lua` 59–90, 143–150; `EUI_Nameplates_CastState.lua` 240–315; `EllesmereUINameplates.lua` 258–284 |
| Flipping the toggle in EllesmereUI's window resets `nameplateShowOnlyNameForFriendlyPlayerUnits`, `ShowClassColorInFriendlyNameplate` and `nameplateUseClassColorForFriendlyPlayerUnitNames` to their defaults at once; a saved value read at load does not (the load path skips them while it is off). EllesmereUI has no blue of its own: the blue is Blizzard's plate | S | `GeneralPage_Options.lua` 80–90; `EUI_Nameplates_CastState.lua` 266–315 |
| The author's saved profiles all hold `tooltipFixedPos = (900.83, -496.67)` and `tooltipAnchorCursor = false`: the tooltip's bottom level with the damage meter's, 5 units left of it | S (read from the saved files) | Retail `EllesmereUI.lua` saved variables; `Classic.lua` geometry (meter at 1233.33, −504.17, 375 × 150) |
| The nameplate fields' effect on screen, the place on real screens, Unlock Mode keeping a written place, and that EllesmereUI reads the flag at load | **G** | in-game checks |

**Phase 4 (2026-10-26).** Read for the wizard's choices, in EllesmereUI 9.6.8; none of it run in game:

| What | Status | Evidence |
|---|---|---|
| The accent is a profile-root key `euiAccent = { custom = { r, g, b }, useClass }`; the import copies it whole; EllesmereUI reads exactly those two keys and writes them only from its own accent swatch | S | `EllesmereUI_Profiles.lua:3464` (`merged.euiAccent = DeepCopy(imported.euiAccent)`), `EllesmereUI_UICore.lua:527` (`SetActiveProfileAccent`), `:556` (`ResolveProfileAccent`) |
| The serializer writes numbers with `tostring` (14 digits), so a colour read back is not bit-equal: TwichUI compares the accent by a three-place signature | S (the existing note on `Serializer`), T | `AdapterEllesmere.lua` `A.AccentSig`; `tests/test_layouts.lua` §17 |
| **Cursor-following tooltip: not backed** (superseded 2026-10-28: managed narrowly, see the block above). `tooltipAnchorCursor` (and `tooltipCursorPosition`, `tooltipCursorOffsetX/Y`, `tooltipGrowthDirection`) are root keys of `EllesmereUIDB`, in the Blizzard-skin globals list | S | `EllesmereUI_Profiles.lua:2043` `BLIZZ_SKIN_GLOBAL_KEYS`; `EUI_BlizzardSkin_TooltipAnchor.lua:125, 148, 463` |
| The only writer is the import's `blizzSkinGlobals` bundle, and it sets **every** key of the list from the payload, nil included | S | `EllesmereUI_Profiles.lua:2157` `ApplyBlizzSkinGlobals`; applied at `:3326`; stripped from a payload by `ImportProfileSilent` when the Blizzard-skin module is disabled (`:5009`) |
| The fixed tooltip position is per profile (`tooltipFixedPos`) but is not a root key the import takes (`AdapterEllesmere.lua` `ROOT`) | S | `EUI_BlizzardSkin_TooltipAnchor.lua:200-300`; `EllesmereUI_Profiles.lua:2038` (the comment that the account-level key is stale) |
| TwichUI has no tooltip-anchor setting | S | searched `!!!TwichUI/` and `TwichUI_Settings/` |
| Registering an installer, importing, switching and deleting profiles: unchanged since Phase 2; the wizard calls only the engine, never EllesmereUI directly | S | `TwichUI_LayoutWizard/*.lua` call nothing of EllesmereUI (the only read of it is `E._firstInstallPending`, as Phase 2's plan does) |

**Phase 5 (2026-10-26).** Read for Compact Adventure and the preview, in EllesmereUI 9.6.8 and the author's captured
`TwichUI - Minimal Adventure` profile; none of it run in game:

| What | Status | Evidence |
|---|---|---|
| Compact differs from Classic only in 7 module blobs (Action Bars, Cooldown Manager's tracked-buff group, Damage Meters' style slots, QoL, Raid Frames, Resource Bars, Unit Frames) and the layout links; the look, fonts, accent and the other 11 modules are identical | S (measured on the saved files) | `capture-compact-adventure.md` (fingerprints) |
| The block is bottom-edge linked: Bar 2 and Bar 4 to `SCREEN_BOTTOM`, bar 1 on bar 2, the player and target frames on bar 1, bars 5 and 6 on bar 4, bar 7 on the damage meter, `TwichUI_FoodDrink` on bar 3 | S | `unlockLayout.anchors` in the capture; `UM.ApplyAnchorPosition` (existing) |
| An action bar's size: `overrideNumIcons` or `numIcons` buttons in `overrideNumRows` rows of `buttonWidth` × `buttonHeight` with `buttonPadding` between; a vertical bar swaps rows and columns. Check against the author's own layout: bar 7 = 377 wide, the damage meter = 375 | S | `EUI_ActionBars_Layout.lua` `ComputeBarLayout` (read; formula re-derived, nothing copied), `tests/test_layout_geometry.lua` §9 |
| A unit frame is `frameWidth` × (`healthHeight` + `powerHeight`); a cast bar `playerCastbarWidth`/`castbarWidth` × `…Height`; the player's own cast bar is hidden when `showPlayerCastbar` is off (the Resource Bars cast bar is used) | S (approximate: EllesmereUI snaps to its pixel grid) | the saved keys; `EllesmereUIUnitFrames` blob |
| Raid and party frames: `unlockPos` and `partyUnlockPos` `{ point, relPoint, x, y }`; centre offsets in Compact | S | the capture; `partyFrameWidth`, `partyFrameHeight`, `partyHorizontal` |
| The game's default tooltip place: `GameTooltipDefaultContainer`, `BOTTOMRIGHT` at (-9, 85), read through its first point like `GameTooltip_SetDefaultAnchor` | S | `wow-ui-source` (forever) `Blizzard_GameTooltip/Mainline/GameTooltip.xml`, `Blizzard_SharedXML/SharedTooltipTemplates.lua` 87–112 |
| Not placed by the screen layer: the Battle Res frame (`EllesmereUIQoL.battleRes.pos`, stored as `centerX`/`centerY`), the CDM's other bars and class power (left at the author's coordinates, which in Compact sit above the block) | S | the capture |


**Phase 7 (2026-10-27).** Read for updates, in EllesmereUI 9.6.8; none of it run in game:

| What | Status | Evidence |
|---|---|---|
| `RenameProfile(old, new)` moves the same profile table to the new name, with its CDM spell bucket, order, spec assignments, sync groups, colour sources, keybind; renaming the active profile keeps it active | S | `EllesmereUI_Profiles.lua:3808` |
| `DeleteProfile` drops spec assignments and the spell bucket for that name; deleting the active profile falls back to "Default" (why an update switches away first) | S | `EllesmereUI_Profiles.lua:3758` |
| `SaveCurrentAsProfile` copies the active profile and switches to it: not used (it would change the active profile and copy unrelated stores) | S | `EllesmereUI_Profiles.lua:3686` |
| Blobs gain defaults at load, so a blob is compared only with its own read-back; which keys EllesmereUI writes at runtime without the player is unknown | S (defaults), **G** (runtime keys) | `history.md` §11.10; `updates.md` checklist 10 |
| `_migrations` decides whether a player's blob can be carried into a package payload (same stamps only) | S (the import takes `_migrations`), G (what a migration rewrites) | `ImportProfile` |
| Moving a frame in Unlock Mode: whether EllesmereUI rewrites the link offset, the stored position, or both | **G** | the edge-link fix-up assumes the live link and position agree |

**RH-1 (2026-10-28).** Read for the hardening pass, in EllesmereUI 9.6.8, TwichUI and the author's captured profiles; none of it
run in game:

| What | Status | Evidence |
|---|---|---|
| The bundled minimap blob holds `minimap.coordsMode` and `coordsPosition` inside the blob; `Excluded` leaves them out of the blob's fingerprint, so they are only seen as units of their own | S, T | `ClassicData.lua` (`coordsMode = "never"`); `AdapterEllesmere.lua` `Excluded`, `UnitsOf`; `test_layout_hardening.lua` A1 |
| A missing field reads as EllesmereUI's default (`FIELDS[*].default`, from the module's defaults), so fields are compared and verified by their effective value | S, T | `EllesmereUIMinimap.lua` defaults (Phase 2 reading); `A.Normal`, `A.Verify` |
| Importing a profile replaces a module blob whole, so a sub-unit is kept only by writing it into the payload's blob | S | `ImportProfile` (Phase 1 reading, `EllesmereUI_Profiles.lua:3330`) |
| TwichUI fills defaults into its saved data only for feature switches (`modules`), not for looks-and-behaviour fields, so clearing a field's stored value makes the feature read `f.default` | S | `!!!TwichUI/Persist.lua` `P.Normalize`; `TwichConfig.lua` `Effective` |
| The battle resurrection timer is stored as `EllesmereUIQoL.battleRes.pos = { centerX, centerY }`, a form the screen layer doesn't read | S | `ClassicData.lua`, `CompactData.lua` |
| UIParent is `768 / UI scale` units tall (the author's 1440-pixel screen at 0.64 is 1200 tall); the effective scale is not the UI scale | S | the author's canvas (Phase 3), `EllesmereUI_PixelPerfect.lua` (Phase 1 reading) |
| `LibDeflate:DecompressDeflate` has no output limit; TwichUI's encoder compresses one 32 KB slice per piece | S | `Libs/LibDeflate`; `setup/Share.lua` `EncodeBig` (`SLICE`) |
| The author's `MyFonts` font file and TwichUI's `AlegreyaSansSC-Bold.ttf` share a file name, and TwichUI registers it as "Alegreya Sans SC Bold", the name the profile uses; the files were not byte-compared (the MyFonts copy isn't on this machine) | S (names), **G** (the same font) | `ClassicData.lua` `unitNameFont`; `modules/Media.lua` |

